%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright (c) 2001 by Erik Johansson.  All Rights Reserved 
%% Time-stamp: <01/08/09 12:13:36 happi>
%% ====================================================================
%%  Filename : 	hipe_x86_ra_postconditions.erl
%%  Module   :	hipe_x86_ra_postconditions
%%  Purpose  :  
%%  Notes    : 
%%  History  :	* 2001-07-24 Erik Johansson (happi@csd.uu.se): 
%%               Created.
%%  CVS      :
%%              $Author: mikpe $
%%              $Date: 2001/09/12 15:07:04 $
%%              $Revision: 1.9 $
%% ====================================================================
%%  Exports  :
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(hipe_x86_ra_postconditions).
-export([check_and_rewrite/4]).
-include("hipe_x86.hrl").
-define(HIPE_INSTRUMENT_COMPILER, true).
-include("../main/hipe.hrl").
-define(count_temp(T), ?cons_counter(counter_mfa_mem_temps, T)).


check_and_rewrite(X86Defun, Coloring, DontSpill, Options) ->  
  %% io:format("Converting\n"),
  TempMap = hipe_temp_map:cols2tuple(Coloring,hipe_x86_specific),
  %% io:format("Rewriting\n"),
  #defun{code=Code0} = X86Defun,
  {Code1, NewDontSpill} = do_insns(Code0, TempMap, [], DontSpill),
  {X86Defun#defun{code=Code1,
		  var_range={0, hipe_gensym:get_var()}}, 
   Coloring, NewDontSpill}.

do_insns([I|Insns], TempMap, Is, DontSpill) ->
  {NewIs, NewDontSpill} = do_insns(Insns, TempMap, Is, DontSpill),
  {NewI, FinalDontSpill} = do_insn(I, TempMap, NewDontSpill),
%%  case [I] of
%%    NewI -> ok;
%%    _ ->
%%      io:format("\n~w ->\n ~w\n------------\n",[I,NewI]),
%%  end,
  {NewI ++ NewIs, FinalDontSpill};
do_insns([],_, Is, DontSpill) ->
    {Is, DontSpill}.

do_insn(I, TempMap, DontSpill) ->	% Insn -> Insn list
    case I of
	#alu{} ->
	    do_alu(I, TempMap, DontSpill);
	#cmp{} ->
	    do_cmp(I, TempMap, DontSpill);
	#jmp_switch{} ->
	    do_jmp_switch(I, TempMap, DontSpill);
	#lea{} ->
	    do_lea(I, TempMap, DontSpill);
	#move{} ->
	    do_move(I, TempMap, DontSpill);
	_ ->
	    %% comment, jmp*, label, pseudo_jcc, pseudo_call, pseudo_tailcall,
	    %% push, ret
	    {[I], DontSpill}
    end.

%%% Fix an alu op.

do_alu(I, TempMap, DontSpill) ->
  #alu{src=Src0,dst=Dst0} = I,
  {FixSrc,Src,FixDst,Dst, NewDontSpill} = 
    do_binary(Src0, Dst0, TempMap, DontSpill),
  {FixSrc ++ FixDst ++ [I#alu{src=Src,dst=Dst}], NewDontSpill}.

%%% Fix a cmp op.

do_cmp(I, TempMap, DontSpill) ->
  #cmp{src=Src0,dst=Dst0} = I,
  {FixSrc, Src, FixDst, Dst, NewDontSpill} = 
    do_binary(Src0, Dst0, TempMap, DontSpill),
  {FixSrc ++ FixDst ++ [I#cmp{src=Src,dst=Dst}], NewDontSpill}.

%%% Fix a jmp_switch op.

do_jmp_switch(I, TempMap, DontSpill) ->
  #jmp_switch{temp=Temp} = I,
  case is_spilled(Temp, TempMap) of
    false ->
      {[I], DontSpill};
    true ->
      
      NewTmp = hipe_x86:mk_new_temp('untagged'),
      {[hipe_x86:mk_move(Temp, NewTmp), I#jmp_switch{temp=NewTmp}],
       [NewTmp|DontSpill]}
  end.

%%% Fix a lea op.

do_lea(I, TempMap, DontSpill) ->
    #lea{temp=Temp} = I,
    case is_spilled(Temp, TempMap) of
	false ->
	    {[I], DontSpill};
	true ->
	    NewTmp = hipe_x86:mk_new_temp('untagged'),
	    {[I#lea{temp=NewTmp}, hipe_x86:mk_move(NewTmp, Temp)],
	     [NewTmp| DontSpill]}
    end.

%%% Fix a move op.

do_move(I, TempMap, DontSpill) ->
  #move{src=Src0,dst=Dst0} = I,
  {FixSrc, Src, FixDst, Dst, NewDontSpill} = 
    do_binary(Src0, Dst0,
	      TempMap, DontSpill),
  {FixSrc ++ FixDst ++ [I#move{src=Src,dst=Dst}],
   NewDontSpill}.

%%% Fix the operands of a binary op.
%%% 1. remove pseudos from any explicit memory operands
%%% 2. if both operands are (implicit or explicit) memory operands,
%%%    move src to a reg and use reg as src in the original insn

do_binary(Src0, Dst0, TempMap, DontSpill) ->
    {FixSrc, Src, DontSpill1} = fix_src_operand(Src0, TempMap),
    {FixDst, Dst, DontSpill2} = fix_dst_operand(Dst0, TempMap),
    {FixSrc3, Src3, DontSpill3} =
	case is_mem_opnd(Src, TempMap) of
	    false ->
		{FixSrc, Src, []};
	    true ->
		case is_mem_opnd(Dst, TempMap) of
		    false ->
			{FixSrc, Src, []};
		    true ->
			Src2 = clone(Src),
			FixSrc2 = FixSrc ++ [hipe_x86:mk_move(Src, Src2)],
			{FixSrc2, Src2, [Src2]}
		end
	end,
    {FixSrc3, Src3, FixDst, Dst, 
     DontSpill3 ++ DontSpill2 ++
     DontSpill1 ++ DontSpill}.

%%% Fix any x86_mem operand to not refer to any spilled temps.

fix_src_operand(Opnd,TmpMap) ->
    fix_mem_operand(Opnd, TmpMap).

fix_dst_operand(Opnd, TempMap) ->
    fix_mem_operand(Opnd,TempMap).

fix_mem_operand(Opnd, TempMap) ->	% -> {[fixupcode], newop, DontSpill}
  case Opnd of
    #x86_mem{base=Base,off=Off} ->
      case is_mem_opnd(Base, TempMap) of
	false ->
	  %% XXX: (Mikael) this test looks wrong to me, since it will
	  %% falsely trigger for temps that are actual registers.
	  %% ra_dummy uses src_is_pseudo() here.
	  case  hipe_x86:is_temp(Off) of
	    false ->
	      {[], Opnd, []};
	    true ->		% pseudo(pseudo)
	      Temp = clone(Off),
	      {[hipe_x86:mk_move(Base, Temp),
		hipe_x86:mk_alu('add', Off, Temp)],
	       Opnd#x86_mem{base=Temp, off=hipe_x86:mk_imm(0)},
	       [Temp]}

	  end;
	true ->
	  Temp = clone(Base),
	  case is_mem_opnd(Off, TempMap) of
	    false ->		% imm/reg(pseudo)
	      {[hipe_x86:mk_move(Base, Temp)],
	       Opnd#x86_mem{base=Temp},
	       [Temp]};
	    true ->		% pseudo(pseudo)
	      {[hipe_x86:mk_move(Base, Temp),
		hipe_x86:mk_alu('add', Off, Temp)],
	       Opnd#x86_mem{base=Temp, off=hipe_x86:mk_imm(0)},
	       [Temp]}
	  end
      end;
    _ ->
      {[], Opnd, []}
  end.

%%% Check if an operand denotes a memory cell (mem or pseudo).

is_mem_opnd(Opnd, TempMap) ->
  R =
  case Opnd of
    #x86_mem{} -> true;
    #x86_temp{} -> 
      Reg = hipe_x86:temp_reg(Opnd),
      case hipe_x86:temp_is_allocatable(Opnd) of
	true -> 
	  case size(TempMap) > Reg of 
	    true ->
		  case 
		      hipe_temp_map:is_spilled(Reg,
					       TempMap) of
		      true ->
			  ?count_temp(Reg),
			  true;
		      false -> false
		  end;
	    _ -> false
	  end;
	false -> true
      end;
    _ -> false
  end,
  %%  io:format("Op ~w mem: ~w\n",[Opnd,R]),
  R.

%%% Check if an operand is a spilled Temp.

src_is_spilled(Src, TempMap) ->
  case hipe_x86:is_temp(Src) of
    true ->
      Reg = hipe_x86:temp_reg(Src),
      case hipe_x86:temp_is_allocatable(Src) of
	true -> 
	  case size(TempMap) > Reg of 
	    true ->
	      case hipe_temp_map:is_spilled(Reg, TempMap) of
		true ->
		  ?count_temp(Reg),
		  true;
		false ->
		  false
	      end;
	    false ->
	      false
	  end;
	false -> true
      end;
    false -> false
  end.

is_spilled(Temp, TempMap) ->
  case hipe_x86:temp_is_allocatable(Temp) of
    true -> 
      Reg = hipe_x86:temp_reg(Temp),
      case size(TempMap) > Reg of 
	true ->
	  case hipe_temp_map:is_spilled(Reg, TempMap) of
	    true ->
	      ?count_temp(Reg),
	      true;
	    false ->
	      false
	  end;
	false ->
	  false
      end;
    false -> true
  end.


%%% Make Reg a clone of Dst (attach Dst's type to Reg).

clone(Dst) ->
    Type =
	case Dst of
	    #x86_mem{} -> hipe_x86:mem_type(Dst);
	    #x86_temp{} -> hipe_x86:temp_type(Dst)
	end,
    hipe_x86:mk_new_temp(Type).