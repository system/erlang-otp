%% -*- erlang-indent-level: 2 -*-
%% ====================================================================
%%  Filename : 	hipe_sparc_prop.erl
%%  Module   :	hipe_sparc_prop
%%  Purpose  :  
%%  Notes    : 
%%  History  :	* 2001-12-04 Erik Johansson (happi@csd.uu.se): 
%%               Created.
%%  CVS      :
%%              $Author: kostis $
%%              $Date: 2005/11/06 13:10:51 $
%%              $Revision: 1.12 $
%% ====================================================================
%%  Exports  :
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(hipe_sparc_prop).
-export([cfg/1]).

%%-define(DEBUG,true).
-include("../main/hipe.hrl").
-include("hipe_sparc.hrl").

-import(hipe_sparc_prop_env,
	[end_of_bb/1, find_hpos/2, find_spos/2,
	 kill/2, kill_all/2, kill_hp/1, kill_phys_regs/1, kill_sp/1,
	 kill_uses/2, lookup/2, new_genv/1, set_active_block/2, succ/1,
	 zap_heap/1, zap_stack/1, bind_spos/3]).

%% ____________________________________________________________________
%% 
cfg(CFG) ->
  %%  hipe_sparc_cfg:pp(CFG),
  Lbls = [hipe_sparc_cfg:start_label(CFG)],
  
  %% Forward prop to get rid of stores.
  {CFG0,GEnv0} = prop_bbs(Lbls, CFG, new_genv(CFG),[]),
  Max = hipe_gensym:get_label(sparc),
  CFG1 = 
    case Max > 1000 of
      true ->
	CFG0;
      false ->
	prop(Lbls, CFG0, GEnv0,100)
    end,
  %% hipe_sparc_cfg:pp(CFG0),
  %% Backward prop to get rid of loads.
  CFG2 = remove_dead(CFG1),
  CFG2.


%% ____________________________________________________________________
%% 
remove_dead(CFG) ->
  Liveness = hipe_sparc_liveness:analyze(CFG),
  Lbls = hipe_sparc_cfg:postorder(CFG),
  bwd_prop(Lbls, CFG, Liveness).

bwd_prop([L|Lbls], CFG, Liveness) ->
  ?debug_msg("Prop ~w\n",[L]),
  BB = hipe_sparc_cfg:bb(CFG, L),
  LiveOut = hipe_sparc_liveness:liveout(Liveness, L),
  ?debug_msg("LiveOut ~w\n",[LiveOut]),
  {NewCode,NewLiveIn} = bwd_prop_bb(hipe_bb:code(BB),LiveOut),
  ?debug_msg("LiveIn ~w\n",[NewLiveIn]),
  NewBB = hipe_bb:code_update(BB, NewCode),
  NewCFG = hipe_sparc_cfg:bb_add(CFG, L, NewBB),
  {NewLiveness, _ChangedP} = 
    hipe_sparc_liveness:update_livein(L, NewLiveIn, Liveness),
  bwd_prop(Lbls, NewCFG, NewLiveness);
bwd_prop([],CFG,_) ->
  CFG.

bwd_prop_bb([I|Is], LiveOut) ->
  {NewIs, NewLiveOut} = bwd_prop_bb(Is,LiveOut),
  {NewI,Out} = bwd_prop_i(I,NewLiveOut),
  ?debug_msg("LiveOut ~w\n",[NewLiveOut]),
  ?debug_msg("I: ",[]),
  ?IF_DEBUG(hipe_sparc_pp:pp_instr(I),no_debug),
  ?debug_msg("\nLiveIn ~w\n",[Out]),
  {[NewI|NewIs], Out};
bwd_prop_bb([], LiveOut) -> {[], LiveOut}.

bwd_prop_i(I,Live) ->
  Uses = ordsets:from_list(hipe_sparc:uses(I)),
  Defines = 
    ordsets:from_list(
      case I of
	#call_link{} -> 
	  [hipe_sparc:mk_reg(X) 
	   || X <- hipe_sparc_registers:allocatable()];
	_ -> hipe_sparc:defines(I)
      end),
  
  case ordsets:intersection(Defines,Live) of
    [] ->
      %% Nothing defined is live -- potentialy dead
      case can_kill(I) of
	true ->
	  {hipe_sparc:comment_create({"Post RA removed instr",I}),
	   Live};
	false ->
	  {I,
	   ordsets:union(ordsets:subtract(Live,Defines),Uses)}
      end;
    _ -> %% The result is needed.
       {I,ordsets:union(ordsets:subtract(Live,Defines),Uses)}
  end.

can_kill(I) ->
  %% TODO: Expand this function.
  case I of
    #move{} ->
      Dest = hipe_sparc:reg_nr(hipe_sparc:move_dest(I)),
      Global = hipe_sparc_registers:global(),
      not lists:member(Dest,Global);
    _ -> 
      false
  end.


%% ____________________________________________________________________
%% 
%% Fixpoint iteration.
prop(_Start,CFG,_Env,0) ->
  CFG;
prop(Start,CFG,Env,N) ->
  case hipe_sparc_prop_env:genv__changed(Env) of
    true ->
      {CFG0,GEnv0} = prop_bbs(Start, CFG,
			      hipe_sparc_prop_env:genv__changed_clear(Env), []),
      prop(Start,CFG0, GEnv0, N-1);
    false ->
      CFG
  end.


%% ____________________________________________________________________
%% 
%%
%% Iterate over the basic blocks of a cfg.
%%
prop_bbs([], CFG, GEnv,_) ->
  {CFG,GEnv};
prop_bbs([BB|BBs], CFG, GEnv,Vis) ->
  case prop_bb(BB, GEnv, CFG,Vis) of
    {[], CFG0, GEnv0, NewVis} ->
      prop_bbs(BBs, CFG0, GEnv0, NewVis);
    {[Succ],  CFG0,GEnv0, NewVis} ->
      prop_bbs([Succ|BBs], CFG0, GEnv0, NewVis);
    {[Succ1,Succ2],  CFG0, GEnv0, NewVis} ->
      prop_bbs([Succ2,Succ1|BBs], CFG0, GEnv0, NewVis);
    {Succs, CFG0,GEnv0, NewVis} ->
      prop_bbs(BBs++Succs, CFG0, GEnv0, NewVis)
  end.
  
  

%%
%% If Lbl is a member of the extended block Ebb. Then propagate info 
%% and continue with its successors.
%%

prop_bb(Lbl, GEnv, CFG, Vis) ->
  case lists:member(Lbl, Vis) of
    true -> {[],CFG, GEnv, Vis};
    false ->
      BB = hipe_sparc_cfg:bb(CFG, Lbl),
      %% io:format("\n~w:\n========\n~p\n",[Lbl,hipe_sparc_prop_env:genv__env(set_active_block(Lbl,GEnv))]),
      {NewCode, NewGEnv} = prop_instrs(hipe_bb:code(BB), 
				       set_active_block(Lbl,GEnv)),
      NewBB = hipe_bb:code_update(BB, NewCode),
      NewCFG = hipe_sparc_cfg:bb_add(CFG, Lbl, NewBB),
      Succ = succ(NewGEnv),
      %% io:format("Succs: ~w\n",[Succ]),
      {Succ, NewCFG, NewGEnv,[Lbl|Vis]}
  end.


prop_instrs([], GEnv) ->
  {[], end_of_bb(GEnv)};
prop_instrs([I|Is], GEnv) ->
  {NewI, Env0} = prop_instr(I, GEnv),
  ?IF_DEBUG(
     if I =/= NewI ->
	 io:format("REWRITE\n"),
	 hipe_sparc_pp:pp_instr(NewI),
	 ok;
	true -> ok
     end,
     no_debug),
  GEnv0 = hipe_sparc_prop_env:genv__env_update(Env0,GEnv),
  {NewIs, NewEnv} = prop_instrs(Is, GEnv0),
  case NewI of
    [_|_] -> {NewI++NewIs, NewEnv};	%% alub -> [move, goto]
    _ -> {[NewI|NewIs], NewEnv}
  end.


%%
%% Propagate copies and constants for one instruction.
%%

prop_instr(I, Env) ->
  ?IF_DEBUG({hipe_sparc_prop_env:pp_lenv(Env),hipe_sparc_pp:pp_instr(I)},no_debug),
  case I of
    #move{} ->
      Srcs = [hipe_sparc:move_src(I)],
      Dsts = [hipe_sparc:move_dest(I)],
      {I0,Env0} = bind_all(Srcs, Dsts, I, hipe_sparc_prop_env:genv__env(Env)),
      {I0, kill_uses(hipe_sparc:defines(I), Env0)};
    #multimove{} ->
      ?EXIT({"Pseudo ops should have been removed",I});
    _ ->
      eval(I, hipe_sparc_prop_env:genv__env(Env))
  end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% Evaluate an instruction. Returns {NewI, NewEnv}.
%%

eval(I, Env) ->
  case I of
    #store{} -> prop_store(I,Env);
    #load{} ->  prop_load(I,Env);
    #pseudo_spill{} -> ?EXIT({"Pseudo ops should have been removed",I});
    #pseudo_unspill{} -> ?EXIT({"Pseudo ops should have been removed",I});
    %%    #cmov_cc{} -> prop_cmov_cc(I,Env);
    %%    #cmov_r{} -> prop_cmov_r(I,Env);
    #alu{} -> prop_alu(I,Env);
    %%    #alu_cc{} -> prop_alu_cc(I,Env);
    %%    #sethi{} ->  prop_sethi(I,Env);

    %%    #load_atom{} ->  prop_load_atom(I,Env);
    %%    #load_word_index{} ->  prop_word_index(I,Env);
    %%    #load_address{} ->  prop_load_address(I,Env);

    %%    #b{} ->  prop_b(I,Env);
    %%    #br{} ->  prop_br(I,Env);
    %%    #goto{} ->  prop_got(I,Env);
    %%    #jmp{} ->  prop_jmp(I,Env);

    #call_link{} ->  prop_call_link(I,Env);

    #nop{} ->  {I,Env};
    #align{} ->  {I,Env};
    #comment{} -> {I,Env};

    _ -> 
      NewEnv = kill_all(hipe_sparc:defines(I), Env),
      {I,NewEnv}
end.    

%% ____________________________________________________________________
%% 
prop_store(I,Env) ->
  Base = hipe_sparc:store_dest(I),
  Offset = hipe_sparc:store_off(I),
  Src = lookup(hipe_sparc:store_src(I),Env),
  NewI = 
    case hipe_sparc:is_reg(Src) of
      true ->
	hipe_sparc:store_src_update(I,Src);
      false ->
	I
    end,
  SP = hipe_sparc:mk_reg(hipe_sparc_registers:stack_pointer()),
  HP = hipe_sparc:mk_reg(hipe_sparc_registers:heap_pointer()),
  if
    Base =:= SP ->
      prop_stack_store(NewI,Env,Offset,Src);
    Base =:= HP ->
      prop_heap_store(NewI,Env,Offset,Src);
    Offset =:= SP ->
      ?EXIT({dont_use_sp_as_offset,I});
    Offset =:= HP ->
      ?EXIT({dont_use_hp_as_offset,I});
    true ->
      %% A store off stack and heap (Probably PCB).
      %% XXX: We assume there is no interference here!!!
      {NewI,Env}
  end.


prop_stack_store(I,Env,Offset,Src) ->
  case hipe_sparc_prop_env:env__sp(Env) of
    unknown ->
       %% We are updating via unknown SP.
	{I, zap_stack(Env)};
    SOff ->
      case hipe_sparc:is_imm(Offset) of
	false ->
	  %% We are updating the stack via a reg...
	  %% TODO: Check wehter the the reg is bound to a const...
	  %% We have to zap the stack...
	  {I, zap_stack(Env)};
	true ->
	  Pos = hipe_sparc:imm_value(Offset) + SOff,
	  NewEnv = bind_spos(Pos, Src, Env),
	  %% TODO: Indicate that Src is copied on stack.
	  {I, NewEnv}
      end
  end.

prop_heap_store(I,Env,Offset,Src) ->
    case hipe_sparc_prop_env:env__hp(Env) of
      unknown ->
	%% We are updating via unknown HP.    
	{I, zap_heap(Env)};	
      HOff ->
	case hipe_sparc:is_imm(Offset) of
	  false ->
	    %% We are updating the heap via a reg...
	    %% TODO: Check wehter the the reg is bound to a const...
	    %% We have to zap the heap...
	    {I, zap_heap(Env)};
	  true ->
	    Pos = hipe_sparc:imm_value(Offset) + HOff,
	    NewEnv = hipe_sparc_prop_env:bind_hpos(Pos, Src, Env),
	    %% TODO: Indicate that Src is copied on heap.
	    {I, NewEnv}
	end
    end.

prop_load(I,Env) ->
  Base = hipe_sparc:load_src(I),
  Offset = lookup(hipe_sparc:load_off(I),Env),
  Dest = hipe_sparc:load_dest(I),
  NewI = hipe_sparc:load_off_update(I,Offset),
  SP = hipe_sparc:mk_reg(hipe_sparc_registers:stack_pointer()),
  HP = hipe_sparc:mk_reg(hipe_sparc_registers:heap_pointer()),
  if
    Base =:= SP ->
      prop_stack_load(NewI,Env,Offset,Dest);
    Base =:= HP ->
      prop_heap_load(NewI,Env,Offset,Dest);
    Offset =:= SP ->
      ?EXIT({dont_use_sp_as_offset,I});
    Offset =:= HP ->
      ?EXIT({dont_use_hp_as_offset,I});
    true ->
      %% A load off stack and heap (Probably PCB).
      %% We assume there is no interference here!!!
      NewEnv = kill(Dest,Env),
      {NewI,NewEnv}
  end.

prop_stack_load(I,Env,Offset,Dest) ->
  case hipe_sparc_prop_env:env__sp(Env) of
    unknown ->
      {I, kill(Dest,Env)};
    SOff ->
      case hipe_sparc:is_imm(Offset) of
	false ->
	  %% We are reading the stack via a reg...
	  %% TODO: Check wehter the the reg is bound to a const...
	  {I, kill(Dest,Env)};
	true ->
	  Pos = hipe_sparc:imm_value(Offset) + SOff,
	  
	  case find_spos(Pos, Env) of
	    undefined ->
	      {I, kill(Dest,Env)};
	    Val ->
	      case lookup(Dest, Env) of
		Val -> {hipe_sparc:comment_create("Removed load"),
			Env};
		_ ->
		  bind_all([Val],[Dest],I,kill_uses([Dest],Env))
	      end
	  end
      end
  end.
 
prop_heap_load(I,Env,Offset,Dest) ->
  case hipe_sparc_prop_env:env__hp(Env) of
    unknown ->
      {I, kill(Dest,Env)};
    HOff ->
      case hipe_sparc:is_imm(Offset) of
	false ->
	  %% We are reading the heap via a reg...
	  %% TODO: Check wehter the the reg is bound to a const...
	  {I, kill(Dest,Env)};
	true ->
	  Pos = hipe_sparc:imm_value(Offset) + HOff,
	  
	  case find_hpos(Pos, Env) of
	    undefined ->
	      {I, kill(Dest,Env)};
	    Val ->
	      bind_all([Val],[Dest],I,kill_uses([Dest],Env))
	  end
      end
  end.


%% ____________________________________________________________________
%% 
prop_alu(I,Env) ->
  OP = hipe_sparc:alu_operator(I),
  Src1 = hipe_sparc:alu_src1(I),
  Src2 = hipe_sparc:alu_src2(I),
  Dest = hipe_sparc:alu_dest(I),
  SP = hipe_sparc:mk_reg(hipe_sparc_registers:stack_pointer()),
  HP = hipe_sparc:mk_reg(hipe_sparc_registers:heap_pointer()),
  if
    Dest =:= SP ->
      case Src1 of
	SP ->
	  prop_sp_op(I,Env,OP,Src2);
	_ ->
	  %% TODO: handle SP = x op SP
	  %% unknown update of SP.
	  {I,kill_sp(zap_stack(Env))}
      end;
    Dest =:= HP ->
      case Src1 of
	HP ->
	  prop_hp_op(I,Env,OP,Src2);
	_ ->
	  %% TODO: handle HP = x op HP
	  %% unknown update of HP.
	  {I,kill_hp(zap_heap(Env))}
      end;
    true ->
      %% TODO: Fold consts ...
      {I, kill(Dest,Env)}
  end.

prop_sp_op(I,Env,'+',Src) ->
  case hipe_sparc:is_imm(Src) of
    true ->
      {I, hipe_sparc_prop_env:inc_sp(Env,hipe_sparc:imm_value(Src))};
    false ->
      {I,kill_sp(zap_stack(Env))}
  end;
prop_sp_op(I,Env,'-',Src) ->
  case hipe_sparc:is_imm(Src) of
    true ->
      {I, hipe_sparc_prop_env:inc_sp(Env, - hipe_sparc:imm_value(Src))};
    false ->
      {I,kill_sp(zap_stack(Env))}
  end;
prop_sp_op(I,Env,_Op,_Src) ->
  %% Dont know how to handle other ops...
  {I,kill_sp(zap_stack(Env))}.

prop_hp_op(I,Env,'+',Src) ->
  case hipe_sparc:is_imm(Src) of
    true ->
      {I, hipe_sparc_prop_env:inc_hp(Env,hipe_sparc:imm_value(Src))};
    false ->
      {I,kill_sp(zap_stack(Env))}
  end;
prop_hp_op(I,Env,'-',Src) ->
  case hipe_sparc:is_imm(Src) of
    true ->
      {I, hipe_sparc_prop_env:inc_hp(Env, - hipe_sparc:imm_value(Src))};
    false ->
      {I,kill_sp(zap_stack(Env))}
  end;
prop_hp_op(I,Env,_Op,_Src) ->
  %% Dont know how to handle other ops...
  {I,kill_hp(zap_heap(Env))}.

%% ____________________________________________________________________
%% 
prop_call_link(I,Env) ->
  Dests = hipe_sparc:call_link_dests(I),
  Env1 = kill_uses(Dests,kill_phys_regs(Env)),
  NoArgs = length(hipe_sparc:call_link_args(I)),
  ArgsInRegs = hipe_sparc_registers:register_args(),
  case NoArgs > ArgsInRegs of
    true ->
      StackAdjust = NoArgs - ArgsInRegs,
      Env2 = hipe_sparc_prop_env:inc_sp(Env1, - StackAdjust*4),
      {I,Env2};
    false ->
      {I,Env1}
  end.


%% ____________________________________________________________________
%% 

bind_all(Srcs, Dsts, I, Env) ->
  bind_all(Srcs, Dsts, I, Env, Env).

%%
%% We have two envs, Env where we do lookups and
%%                   NewEnv where the new bindings are entered.
bind_all([Src|Srcs], [Dst|Dsts], I, Env, NewEnv) ->
  case hipe_sparc:is_imm(Src) of
    true ->
      bind_all(Srcs, Dsts, I, Env,
	       hipe_sparc_prop_env:bind(NewEnv, Dst, Src));
    false ->  %% its a variable
      SrcVal = lookup(Src, Env),
      NewI = hipe_sparc:subst_uses(I,[{Src, SrcVal}]),
      bind_all(Srcs, Dsts, NewI, Env,
	       hipe_sparc_prop_env:bind(NewEnv, Dst, SrcVal))
  end;
bind_all([], [], I, _, Env) ->
  {I, Env}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

