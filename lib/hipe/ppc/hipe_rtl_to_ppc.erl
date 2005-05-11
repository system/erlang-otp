%%% -*- erlang-indent-level: 2 -*-
%%% $Id: hipe_rtl_to_ppc.erl,v 1.16 2004/12/06 03:09:39 mikpe Exp $
%%%
%%% The PowerPC instruction set is quite irregular.
%%% The following quirks must be handled by the translation:
%%%
%%% - The instruction names are different for reg/reg and reg/imm
%%%   source operands. For some operations, completely different
%%%   instructions handle the reg/reg and reg/imm cases.
%%% - The name of an arithmetic instruction depends on whether any
%%%   condition codes are to be set or not. Overflow is treated
%%%   separately from other conditions.
%%% - Some combinations or RTL ALU operations, source operand shapes,
%%%   and requested conditions have no direct correspondence in the
%%%   PowerPC instruction set.
%%% - The tagging of immediate operands as simm16 or uimm16 depends
%%%   on the actual instruction.
%%% - Conditional branches have no unsigned conditions. Instead there
%%%   are signed and unsigned versions of the compare instruction.
%%% - The arithmetic overflow flag XER[SO] is sticky: once set it
%%%   remains set until explicitly cleared.

-module(hipe_rtl_to_ppc).
-export([translate/1]).

translate(RTL) ->
  hipe_gensym:init(ppc),
  hipe_gensym:set_var(ppc, hipe_ppc_registers:first_virtual()),
  hipe_gensym:set_label(ppc, hipe_gensym:get_label(rtl)),
  Map0 = vmap_empty(),
  {Formals, Map1} = conv_formals(hipe_rtl:rtl_params(RTL), Map0),
  OldData = hipe_rtl:rtl_data(RTL),
  {Code0, NewData} = conv_insn_list(hipe_rtl:rtl_code(RTL), Map1, OldData),
  {RegFormals,_} = split_args(Formals),
  Code =
    case RegFormals of
      [] -> Code0;
      _ -> [hipe_ppc:mk_label(hipe_gensym:get_next_label(ppc)) |
	    move_formals(RegFormals, Code0)]
    end,
  IsClosure = hipe_rtl:rtl_is_closure(RTL),
  IsLeaf = hipe_rtl:rtl_is_leaf(RTL),
  hipe_ppc:mk_defun(conv_mfa(hipe_rtl:rtl_fun(RTL)),
		    Formals,
		    IsClosure,
		    IsLeaf,
		    Code,
		    NewData,
		    [], 
		    []).

conv_insn_list([H|T], Map, Data) ->
  {NewH, NewMap, NewData1} = conv_insn(H, Map, Data),
  %% io:format("~w \n  ==>\n ~w\n- - - - - - - - -\n",[H,NewH]),
  {NewT, NewData2} = conv_insn_list(T, NewMap, NewData1),
  {NewH ++ NewT, NewData2};
conv_insn_list([], _, Data) ->
  {[], Data}.

conv_insn(I, Map, Data) ->
  case hipe_rtl:type(I) of
    alu -> conv_alu(I, Map, Data);
    alub -> conv_alub(I, Map, Data);
    branch -> conv_branch(I, Map, Data);
    call -> conv_call(I, Map, Data);
    comment -> conv_comment(I, Map, Data);
    enter -> conv_enter(I, Map, Data);
    goto -> conv_goto(I, Map, Data);
    label -> conv_label(I, Map, Data);
    load -> conv_load(I, Map, Data);
    load_address -> conv_load_address(I, Map, Data);
    load_atom -> conv_load_atom(I, Map, Data);
    move -> conv_move(I, Map, Data);
    return -> conv_return(I, Map, Data);
    store -> conv_store(I, Map, Data);
    switch -> conv_switch(I, Map, Data);
    fconv -> conv_fconv(I, Map, Data);
    fmove -> conv_fmove(I, Map, Data);
    fload -> conv_fload(I, Map, Data);
    fstore -> conv_fstore(I, Map, Data);
    fp -> conv_fp_binary(I, Map, Data);
    fp_unop -> conv_fp_unary(I, Map, Data);
    _ -> exit({?MODULE,conv_insn,I})
  end.

conv_fconv(I, Map, Data) ->
  %% Dst := (double)Src, where Dst is FP reg and Src is int reg
  {Dst, Map0} = conv_fpreg(hipe_rtl:fconv_dst(I), Map),
  {Src, Map1} = conv_src(hipe_rtl:fconv_src(I), Map0), % exclude imm src
  I2 = mk_fconv(Dst, Src),
  {I2, Map1, Data}.

mk_fconv(Dst, Src) ->
  CSP = hipe_ppc:mk_temp(1, 'untagged'),
  R0 = hipe_ppc:mk_temp(0, 'untagged'),
  RTmp1 = hipe_ppc:mk_new_temp('untagged'),
  RTmp2 = hipe_ppc:mk_new_temp('untagged'),
  RTmp3 = hipe_ppc:mk_new_temp('untagged'),
  FTmp1 = hipe_ppc:mk_new_temp('double'),
  FTmp2 = hipe_ppc:mk_new_temp('double'),
  [hipe_ppc:mk_pseudo_li(RTmp1, {fconv_constant,c_const}),
   hipe_ppc:mk_lfd(FTmp1, 0, RTmp1),
   hipe_ppc:mk_alu('xoris', RTmp2, Src, hipe_ppc:mk_uimm16(16#8000)),
   hipe_ppc:mk_store('stw', RTmp2, 28, CSP),
   hipe_ppc:mk_alu('addis', RTmp3, R0, hipe_ppc:mk_simm16(16#4330)),
   hipe_ppc:mk_store('stw', RTmp3, 24, CSP),
   hipe_ppc:mk_lfd(FTmp2, 24, CSP),
   hipe_ppc:mk_fp_binary('fsub', Dst, FTmp2, FTmp1)].

conv_fmove(I, Map, Data) ->
  %% Dst := Src, where both Dst and Src are FP regs
  {Dst, Map0} = conv_fpreg(hipe_rtl:fmove_dst(I), Map),
  {Src, Map1} = conv_fpreg(hipe_rtl:fmove_src(I), Map0),
  I2 = mk_fmove(Dst, Src),
  {I2, Map1, Data}.

mk_fmove(Dst, Src) ->
  [hipe_ppc:mk_pseudo_fmove(Dst, Src)].

conv_fload(I, Map, Data) ->
  %% Dst := MEM[Base+Off], where Dst is FP reg
  {Dst, Map0} = conv_fpreg(hipe_rtl:fload_dst(I), Map),
  {Base1, Map1} = conv_src(hipe_rtl:fload_src(I), Map0),
  {Base2, Map2} = conv_src(hipe_rtl:fload_offset(I), Map1),
  I2 = mk_fload(Dst, Base1, Base2),
  {I2, Map2, Data}.

mk_fload(Dst, Base1, Base2) ->
  case hipe_ppc:is_temp(Base1) of
    true ->
      case hipe_ppc:is_temp(Base2) of
	true ->
	  mk_fload_rr(Dst, Base1, Base2);
	_ ->
	  mk_fload_ri(Dst, Base1, Base2)
      end;
    _ ->
      case hipe_ppc:is_temp(Base2) of
	true ->
	  mk_fload_ri(Dst, Base2, Base1);
	_ ->
	  mk_fload_ii(Dst, Base1, Base2)
      end
  end.

mk_fload_ii(Dst, Base1, Base2) ->
  io:format("~w: RTL fload with two immediates\n", [?MODULE]),
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Base1,
	mk_fload_ri(Dst, Tmp, Base2)).

mk_fload_ri(Dst, Base, Disp) ->
  if Disp >= -32768, Disp < 32768 ->
      [hipe_ppc:mk_lfd(Dst, Disp, Base)];
     true ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Disp,
	    mk_fload_rr(Dst, Base, Tmp))
  end.

mk_fload_rr(Dst, Base1, Base2) ->
  [hipe_ppc:mk_lfdx(Dst, Base1, Base2)].

conv_fstore(I, Map, Data) ->
  %% MEM[Base+Off] := Src, where Src is FP reg
  {Base1, Map0} = conv_dst(hipe_rtl:fstore_base(I), Map),
  {Src, Map1} = conv_fpreg(hipe_rtl:fstore_src(I), Map0),
  {Base2, Map2} = conv_src(hipe_rtl:fstore_offset(I), Map1),
  I2 = mk_fstore(Src, Base1, Base2),
  {I2, Map2, Data}.

mk_fstore(Src, Base1, Base2) ->
  case hipe_ppc:is_temp(Base2) of
    true ->
      mk_fstore_rr(Src, Base1, Base2);
    _ ->
      mk_fstore_ri(Src, Base1, Base2)
  end.

mk_fstore_ri(Src, Base, Disp) ->
  if Disp >= -32768, Disp < 32768 ->
      [hipe_ppc:mk_stfd(Src, Disp, Base)];
     true ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Disp,
	    mk_fstore_rr(Src, Base, Tmp))
  end.

mk_fstore_rr(Src, Base1, Base2) ->
  [hipe_ppc:mk_stfdx(Src, Base1, Base2)].

conv_fp_binary(I, Map, Data) ->
  {Dst, Map0} = conv_fpreg(hipe_rtl:fp_dst(I), Map),
  {Src1, Map1} = conv_fpreg(hipe_rtl:fp_src1(I), Map0),
  {Src2, Map2} = conv_fpreg(hipe_rtl:fp_src2(I), Map1),
  RtlFpOp = hipe_rtl:fp_op(I),
  I2 = mk_fp_binary(Dst, Src1, RtlFpOp, Src2),
  {I2, Map2, Data}.

mk_fp_binary(Dst, Src1, RtlFpOp, Src2) ->
  FpBinOp =
    case RtlFpOp of
      'fadd' -> 'fadd';
      'fdiv' -> 'fdiv';
      'fmul' -> 'fmul';
      'fsub' -> 'fsub'
    end,
  [hipe_ppc:mk_fp_binary(FpBinOp, Dst, Src1, Src2)].

conv_fp_unary(I, Map, Data) ->
  {Dst, Map0} = conv_fpreg(hipe_rtl:fp_unop_dst(I), Map),
  {Src, Map1} = conv_fpreg(hipe_rtl:fp_unop_src(I), Map0),
  RtlFpUnOp = hipe_rtl:fp_unop_op(I),
  I2 = mk_fp_unary(Dst, Src, RtlFpUnOp),
  {I2, Map1, Data}.

mk_fp_unary(Dst, Src, RtlFpUnOp) ->
  FpUnOp =
    case RtlFpUnOp of
      'fchs' -> 'fneg'
    end,
  [hipe_ppc:mk_fp_unary(FpUnOp, Dst, Src)].

conv_alu(I, Map, Data) ->
  %% dst = src1 aluop src2
  {Dst, Map0} = conv_dst(hipe_rtl:alu_dst(I), Map),
  {Src1, Map1} = conv_src(hipe_rtl:alu_src1(I), Map0),
  {Src2, Map2} = conv_src(hipe_rtl:alu_src2(I), Map1),
  RtlAluOp = hipe_rtl:alu_op(I),
  I2 = mk_alu(Dst, Src1, RtlAluOp, Src2),
  {I2, Map2, Data}.

mk_alu(Dst, Src1, RtlAluOp, Src2) ->
  case hipe_ppc:is_temp(Src1) of
    true ->
      case hipe_ppc:is_temp(Src2) of
	true ->
	  mk_alu_rr(Dst, Src1, RtlAluOp, Src2);
	_ ->
	  mk_alu_ri(Dst, Src1, RtlAluOp, Src2)
      end;
    _ ->
      case hipe_ppc:is_temp(Src2) of
	true ->
	  mk_alu_ir(Dst, Src1, RtlAluOp, Src2);
	_ ->
	  mk_alu_ii(Dst, Src1, RtlAluOp, Src2)
      end
  end.

mk_alu_ii(Dst, Src1, RtlAluOp, Src2) ->
  io:format("~w: RTL alu with two immediates\n", [?MODULE]),
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Src1,
	mk_alu_ri(Dst, Tmp, RtlAluOp, Src2)).

mk_alu_ir(Dst, Src1, RtlAluOp, Src2) ->
  case rtl_aluop_commutes(RtlAluOp) of
    true ->
      mk_alu_ri(Dst, Src2, RtlAluOp, Src1);
    _ ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Src1,
	    mk_alu_rr(Dst, Tmp, RtlAluOp, Src2))
  end.

mk_alu_ri(Dst, Src1, RtlAluOp, Src2) ->
  case RtlAluOp of
    'sub' ->	% there is no 'subi'
      mk_alu_ri_addi(Dst, Src1, -Src2);
    'add' ->	% 'addi' has a 16-bit simm operand
      mk_alu_ri_addi(Dst, Src1, Src2);
    'and' ->	% 'andi.' has a 16-bit uimm operand
      mk_alu_ri_bitop(Dst, Src1, RtlAluOp, 'andi.', Src2);
    'or' ->	% 'ori' has a 16-bit uimm operand
      mk_alu_ri_bitop(Dst, Src1, RtlAluOp, 'ori', Src2);
    'xor' ->	% 'xori' has a 16-bit uimm operand
      mk_alu_ri_bitop(Dst, Src1, RtlAluOp, 'xori', Src2);
    _ ->	% shift ops have 5-bit uimm operands
      mk_alu_ri_shift(Dst, Src1, RtlAluOp, Src2)
  end.

mk_alu_ri_addi(Dst, Src1, Src2) ->
  if Src2 < 32768, Src2 >= -32768 ->
      [hipe_ppc:mk_alu('addi', Dst, Src1,
		       hipe_ppc:mk_simm16(Src2))];
     true ->
      mk_alu_ri_rr(Dst, Src1, 'add', Src2)
  end.

mk_alu_ri_bitop(Dst, Src1, RtlAluOp, AluOp, Src2) ->
  if Src2 < 65536, Src2 >= 0 ->
      [hipe_ppc:mk_alu(AluOp, Dst, Src1,
		       hipe_ppc:mk_uimm16(Src2))];
     true ->
      mk_alu_ri_rr(Dst, Src1, RtlAluOp, Src2)
  end.

mk_alu_ri_shift(Dst, Src1, RtlAluOp, Src2) ->
  if Src2 < 32, Src2 >= 0 ->
      AluOp =
	case RtlAluOp of
	  'sll' -> 'slwi'; % alias for rlwinm
	  'srl' -> 'srwi'; % alias for rlwinm
	  'sra' -> 'srawi'
	end,
      [hipe_ppc:mk_alu(AluOp, Dst, Src1,
		       hipe_ppc:mk_uimm16(Src2))];
     true ->
      mk_alu_ri_rr(Dst, Src1, RtlAluOp, Src2)
  end.

mk_alu_ri_rr(Dst, Src1, RtlAluOp, Src2) ->
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Src2,
	mk_alu_rr(Dst, Src1, RtlAluOp, Tmp)).

mk_alu_rr(Dst, Src1, RtlAluOp, Src2) ->
  case RtlAluOp of
    'sub' -> % PPC weirdness
      [hipe_ppc:mk_alu('subf', Dst, Src2, Src1)];
    _ ->
      AluOp =
	case RtlAluOp of
	  'add' -> 'add';
	  'or'  -> 'or';
	  'and' -> 'and';
	  'xor' -> 'xor';
	  'sll' -> 'slw';
	  'srl' -> 'srw';
	  'sra' -> 'sraw'
	end,
      [hipe_ppc:mk_alu(AluOp, Dst, Src1, Src2)]
  end.

conv_alub(I, Map, Data) ->
  %% dst = src1 aluop src2; if COND goto label
  {Dst, Map0} = conv_dst(hipe_rtl:alub_dst(I), Map),
  {Src1, Map1} = conv_src(hipe_rtl:alub_src1(I), Map0),
  {Src2, Map2} = conv_src(hipe_rtl:alub_src2(I), Map1),
  BCond = conv_alub_cond(hipe_rtl:alub_cond(I)),
  I2 = mk_pseudo_bc(
	  BCond,
	  hipe_rtl:alub_true_label(I),
	  hipe_rtl:alub_false_label(I),
	  hipe_rtl:alub_pred(I)),
  RtlAluOp = hipe_rtl:alub_op(I),
  I1 = mk_alub(Dst, Src1, RtlAluOp, Src2, BCond),
  {I1 ++ I2, Map2, Data}.

conv_alub_cond(Cond) ->	% only signed
  case Cond of
    eq	-> 'eq';
    ne	-> 'ne';
    gt	-> 'gt';
    ge	-> 'ge';
    lt	-> 'lt';
    le	-> 'le';
    overflow -> 'so';
    not_overflow -> 'ns';
    _	-> exit({?MODULE,conv_alub_cond,Cond})
  end.

mk_alub(Dst, Src1, RtlAluOp, Src2, BCond) ->
  case hipe_ppc:is_temp(Src1) of
    true ->
      case hipe_ppc:is_temp(Src2) of
	true ->
	  mk_alub_rr(Dst, Src1, RtlAluOp, Src2, BCond);
	_ ->
	  mk_alub_ri(Dst, Src1, RtlAluOp, Src2, BCond)
      end;
    _ ->
      case hipe_ppc:is_temp(Src2) of
	true ->
	  mk_alub_ir(Dst, Src1, RtlAluOp, Src2, BCond);
	_ ->
	  mk_alub_ii(Dst, Src1, RtlAluOp, Src2, BCond)
      end
  end.

mk_alub_ii(Dst, Src1, RtlAluOp, Src2, BCond) ->
  io:format("~w: RTL alub with two immediates\n", [?MODULE]),
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Src1,
	mk_alub_ri(Dst, Tmp, RtlAluOp, Src2, BCond)).

mk_alub_ir(Dst, Src1, RtlAluOp, Src2, BCond) ->
  case rtl_aluop_commutes(RtlAluOp) of
    true ->
      mk_alub_ri(Dst, Src2, RtlAluOp, Src1, BCond);
    _ ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Src1,
	    mk_alub_rr(Dst, Tmp, RtlAluOp, Src2, BCond))
  end.

mk_alub_ri(Dst, Src1, RtlAluOp, Src2, BCond) ->
  true = is_integer(Src2),
  case BCond of
    'so' -> mk_alub_ri_OE(Dst, Src1, RtlAluOp, Src2);
    'ns' -> mk_alub_ri_OE(Dst, Src1, RtlAluOp, Src2);
    _ -> mk_alub_ri_Rc(Dst, Src1, RtlAluOp, Src2)
  end.

mk_alub_ri_OE(Dst, Src1, RtlAluOp, Src2) ->
  %% Only 'add' and 'sub' apply here, and 'sub' becomes 'add'.
  %% There doesn't seem to be anything like an 'addic.' with OE.
  %% Rewrite to reg/reg form. Sigh.
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Src2,
	mk_alub_rr_OE(Dst, Src1, RtlAluOp, Tmp)).

mk_alub_ri_Rc(Dst, Src1, RtlAluOp, Src2) ->
  case RtlAluOp of
    'sub' ->	% there is no 'subi.'
      mk_alub_ri_Rc_addi(Dst, Src1, -Src2);
    'add' ->	% 'addic.' has a 16-bit simm operand
      mk_alub_ri_Rc_addi(Dst, Src1, Src2);
    'or' ->	% there is no 'ori.'
      mk_alub_ri_Rc_rr(Dst, Src1, 'or.', Src2);
    'xor' ->	% there is no 'xori.'
      mk_alub_ri_Rc_rr(Dst, Src1, 'xor.', Src2);
    'and' ->	% 'andi.' has a 16-bit uimm operand
      mk_alub_ri_Rc_andi(Dst, Src1, Src2);
    _ ->	% shift ops have 5-bit uimm operands
      mk_alub_ri_Rc_shift(Dst, Src1, RtlAluOp, Src2)
  end.

mk_alub_ri_Rc_addi(Dst, Src1, Src2) ->
  if Src2 < 32768, Src2 >= -32768 ->
      [hipe_ppc:mk_alu('addic.', Dst, Src1,
		       hipe_ppc:mk_simm16(Src2))];
     true ->
      mk_alub_ri_Rc_rr(Dst, Src1, 'add', Src2)
  end.

mk_alub_ri_Rc_andi(Dst, Src1, Src2) ->
  if Src2 < 65536, Src2 >= 0 ->
      [hipe_ppc:mk_alu('andi.', Dst, Src1,
		       hipe_ppc:mk_uimm16(Src2))];
     true ->
      mk_alub_ri_Rc_rr(Dst, Src1, 'and.', Src2)
  end.

mk_alub_ri_Rc_shift(Dst, Src1, RtlAluOp, Src2) ->
  if Src2 < 32, Src2 >= 0 ->
      AluOp =
	case RtlAluOp of
	  'sll' -> 'slwi.'; % alias for rlwinm.
	  'srl' -> 'srwi.'; % alias for rlwinm.
	  'sra' -> 'srawi.'
	end,
      [hipe_ppc:mk_alu(AluOp, Dst, Src1,
		       hipe_ppc:mk_uimm16(Src2))];
     true ->
      AluOp =
	case RtlAluOp of
	  'sll' -> 'slw.';
	  'srl' -> 'srw.';
	  'sra' -> 'sraw.'
	end,
      mk_alub_ri_Rc_rr(Dst, Src1, AluOp, Src2)
  end.

mk_alub_ri_Rc_rr(Dst, Src1, AluOp, Src2) ->
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Src2,
	[hipe_ppc:mk_alu(AluOp, Dst, Src1, Tmp)]).

mk_alub_rr(Dst, Src1, RtlAluOp, Src2, BCond) ->
  case BCond of
    'so' -> mk_alub_rr_OE(Dst, Src1, RtlAluOp, Src2);
    'ns' -> mk_alub_rr_OE(Dst, Src1, RtlAluOp, Src2);
    _ -> mk_alub_rr_Rc(Dst, Src1, RtlAluOp, Src2)
  end.

mk_alub_rr_OE(Dst, Src1, RtlAluOp, Src2) ->
  case RtlAluOp of
    'sub' -> % PPC weirdness
      [hipe_ppc:mk_alu('subfo.', Dst, Src2, Src1)];
    'add' ->
      [hipe_ppc:mk_alu('addo.', Dst, Src1, Src2)]
      %% fail for or, and, xor, sll, srl, sra
  end.

mk_alub_rr_Rc(Dst, Src1, RtlAluOp, Src2) ->
  %% XXX: identical to mk_alu_rr/4, except for the '.' in the instruction names
  case RtlAluOp of
    'sub' -> % PPC weirdness
      [hipe_ppc:mk_alu('subf.', Dst, Src2, Src1)];
    _ ->
      AluOp =
	case RtlAluOp of
	  'add' -> 'add.';
	  'or'  -> 'or.';
	  'and' -> 'and.';
	  'xor' -> 'xor.';
	  'sll' -> 'slw.';
	  'srl' -> 'srw.';
	  'sra' -> 'sraw.'
	end,
      [hipe_ppc:mk_alu(AluOp, Dst, Src1, Src2)]
  end.

conv_branch(I, Map, Data) ->
  %% <unused> = src1 - src2; if COND goto label
  {Src1, Map0} = conv_src(hipe_rtl:branch_src1(I), Map),
  {Src2, Map1} = conv_src(hipe_rtl:branch_src2(I), Map0),
  {BCond,Sign} = conv_branch_cond(hipe_rtl:branch_cond(I)),
  I2 = mk_branch(Src1, BCond, Sign, Src2,
		 hipe_rtl:branch_true_label(I),
		 hipe_rtl:branch_false_label(I),
		 hipe_rtl:branch_pred(I)),
  {I2, Map1, Data}.

conv_branch_cond(Cond) -> % may be unsigned
  case Cond of
    gtu -> {'gt', 'unsigned'};
    geu -> {'ge', 'unsigned'};
    ltu -> {'lt', 'unsigned'};
    leu -> {'le', 'unsigned'};
    _   -> {conv_alub_cond(Cond), 'signed'}
  end.    

mk_branch(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred) ->
  case hipe_ppc:is_temp(Src1) of
    true ->
      case hipe_ppc:is_temp(Src2) of
	true ->
	  mk_branch_rr(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred);
	_ ->
	  mk_branch_ri(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred)
      end;
    _ ->
      case hipe_ppc:is_temp(Src2) of
	true ->
	  NewBCond = commute_bcond(BCond),
	  mk_branch_ri(Src2, NewBCond, Sign, Src1, TrueLab, FalseLab, Pred);
	_ ->
	  mk_branch_ii(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred)
      end
  end.

commute_bcond(BCond) ->	% if x BCond y, then y commute_bcond(BCond) x
  case BCond of
    'eq' -> 'eq';	% ==, ==
    'ne' -> 'ne';	% !=, !=
    'gt' -> 'lt';	% >, <
    'ge' -> 'le';	% >=, <=
    'lt' -> 'gt';	% <, >
    'le' -> 'ge';	% <=, >=
    %% so/ns: n/a
    _ -> exit({?MODULE,commute_bcond,BCond})
  end.

mk_branch_ii(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred) ->
  io:format("~w: RTL branch with two immediates\n", [?MODULE]),
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Src1,
	mk_branch_ri(Tmp, BCond, Sign, Src2,
		     TrueLab, FalseLab, Pred)).

mk_branch_ri(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred) ->
  {FixSrc2,NewSrc2,CmpOp} =
    case Sign of
      'signed' ->
	if Src2 < 32768, Src2 >= -32768 ->
	    {[], hipe_ppc:mk_simm16(Src2), 'cmpi'};
	   true ->
	    Tmp = new_untagged_temp(),
	    {mk_li(Tmp, Src2), Tmp, 'cmp'}
	end;
      'unsigned' ->
	if Src2 < 65536, Src2 >= 0 ->
	    {[], hipe_ppc:mk_uimm16(Src2), 'cmpli'};
	   true ->
	    Tmp = new_untagged_temp(),
	    {mk_li(Tmp, Src2), Tmp, 'cmpl'}
	end
    end,
  FixSrc2 ++
    mk_cmp_bc(CmpOp, Src1, NewSrc2, BCond, TrueLab, FalseLab, Pred).

mk_branch_rr(Src1, BCond, Sign, Src2, TrueLab, FalseLab, Pred) ->
  CmpOp =
    case Sign of
      'signed' -> 'cmp';
      'unsigned' -> 'cmpl'
    end,
  mk_cmp_bc(CmpOp, Src1, Src2, BCond, TrueLab, FalseLab, Pred).

mk_cmp_bc(CmpOp, Src1, Src2, BCond, TrueLab, FalseLab, Pred) ->
  [hipe_ppc:mk_cmp(CmpOp, Src1, Src2) |
   mk_pseudo_bc(BCond, TrueLab, FalseLab, Pred)].

conv_call(I, Map, Data) ->
  {Args, Map0} = conv_src_list(hipe_rtl:call_arglist(I), Map),
  {Dsts, Map1} = conv_dst_list(hipe_rtl:call_dstlist(I), Map0),
  {Fun, Map2} = conv_fun(hipe_rtl:call_fun(I), Map1),
  ContLab = hipe_rtl:call_continuation(I),
  ExnLab = hipe_rtl:call_fail(I),
  Linkage = hipe_rtl:call_type(I),
  I2 = mk_call(Dsts, Fun, Args, ContLab, ExnLab, Linkage),
  {I2, Map2, Data}.

mk_call(Dsts, Fun, Args, ContLab, ExnLab, Linkage) ->
  case hipe_ppc:is_prim(Fun) of
    true ->
      mk_primop_call(Dsts, Fun, Args, ContLab, ExnLab, Linkage);
    false ->
      mk_general_call(Dsts, Fun, Args, ContLab, ExnLab, Linkage)
  end.

mk_primop_call(Dsts, Prim, Args, ContLab, ExnLab, Linkage) ->
  case hipe_ppc:prim_prim(Prim) of
    'extsh' ->
      mk_extsh_call(Dsts, Args, ContLab, ExnLab, Linkage);
    'lhbrx' ->
      mk_lhbrx_call(Dsts, Args, ContLab, ExnLab, Linkage);
    'lwbrx' ->
      mk_lwbrx_call(Dsts, Args, ContLab, ExnLab, Linkage);
    _ ->
      mk_general_call(Dsts, Prim, Args, ContLab, ExnLab, Linkage)
  end.

mk_extsh_call([Dst], [Src], [], [], not_remote) ->
  true = hipe_ppc:is_temp(Src),
  [hipe_ppc:mk_unary('extsh', Dst, Src)].

mk_lhbrx_call(Dsts, [Base,Offset], [], [], not_remote) ->
  case Dsts of
    [Dst] -> mk_loadx('lhbrx', Dst, Base, Offset);
    [] -> [] % result unused, cancel the operation
  end.

mk_lwbrx_call([Dst], [Base,Offset], [], [], not_remote) ->
  mk_loadx('lwbrx', Dst, Base, Offset).

mk_loadx(LdxOp, Dst, Base, Offset) ->
  true = hipe_ppc:is_temp(Base),
  {FixOff,NewOff} =
    case hipe_ppc:is_temp(Offset) of
      true -> {[], Offset};
      false ->
	Tmp = new_untagged_temp(),
	{mk_li(Tmp, Offset), Tmp}
    end,
  FixOff ++ [hipe_ppc:mk_loadx(LdxOp, Dst, Base, NewOff)].

mk_general_call(Dsts, Fun, Args, ContLab, ExnLab, Linkage) ->
  %% The backend does not support pseudo_calls without a
  %% continuation label, so we make sure each call has one.
  {RealContLab, Tail} =
    case mk_call_results(Dsts) of
      [] ->
	%% Avoid consing up a dummy basic block if the moves list
	%% is empty, as is typical for calls to suspend/0.
	%% This should be subsumed by a general "optimise the CFG"
	%% module, and could probably be removed.
	case ContLab of
	  [] ->
	    NewContLab = hipe_gensym:get_next_label(ppc),
	    {NewContLab, [hipe_ppc:mk_label(NewContLab)]};
	  _ ->
	    {ContLab, []}
	end;
      Moves ->
	%% Change the call to continue at a new basic block.
	%% In this block move the result registers to the Dsts,
	%% then continue at the call's original continuation.
	NewContLab = hipe_gensym:get_next_label(ppc),
	case ContLab of
	  [] ->
	    %% This is just a fallthrough
	    %% No jump back after the moves.
	    {NewContLab,
	     [hipe_ppc:mk_label(NewContLab) |
	      Moves]};
	  _ ->
	    %% The call has a continuation. Jump to it.
	    {NewContLab,
	     [hipe_ppc:mk_label(NewContLab) |
	      Moves ++
	      [hipe_ppc:mk_b_label(ContLab)]]}
	end
    end,
  SDesc = hipe_ppc:mk_sdesc(ExnLab, 0, length(Args), {}),
  {FixFunC,FunC} = fix_func(Fun),
  CallInsn = hipe_ppc:mk_pseudo_call(FunC, SDesc, RealContLab, Linkage),
  {RegArgs,StkArgs} = split_args(Args),
  FixFunC ++
    mk_push_args(StkArgs, move_actuals(RegArgs, [CallInsn | Tail])).

mk_call_results([]) ->
  [];
mk_call_results([Dst]) ->
  RV = hipe_ppc:mk_temp(hipe_ppc_registers:return_value(), 'tagged'),
  [hipe_ppc:mk_pseudo_move(Dst, RV)];
mk_call_results(Dsts) ->
  exit({?MODULE,mk_call_results,Dsts}).

fix_func(Fun) ->
  case hipe_ppc:is_temp(Fun) of
    true -> {[hipe_ppc:mk_mtspr('ctr', Fun)], 'ctr'};
    _ -> {[], Fun}
  end.

mk_push_args(StkArgs, Tail) ->
  case length(StkArgs) of
    0 ->
      Tail;
    NrStkArgs ->
      [hipe_ppc:mk_pseudo_call_prepare(NrStkArgs) |
       mk_store_args(StkArgs, NrStkArgs * word_size(), Tail)]
  end.
  
mk_store_args([Arg|Args], PrevOffset, Tail) ->
  Offset = PrevOffset - word_size(),
  {Src,FixSrc} =
    case hipe_ppc:is_temp(Arg) of
      true ->
	{Arg, []};
      _ ->
	Tmp = new_tagged_temp(),
	{Tmp, mk_li(Tmp, Arg)}
    end,
  Store = hipe_ppc:mk_store('stw', Src, Offset, mk_sp()),
  mk_store_args(Args, Offset, FixSrc ++ [Store | Tail]);
mk_store_args([], _, Tail) ->
  Tail.

conv_comment(I, Map, Data) ->
  I2 = [hipe_ppc:mk_comment(hipe_rtl:comment_text(I))],
  {I2, Map, Data}.

conv_enter(I, Map, Data) ->
  {Args, Map0} = conv_src_list(hipe_rtl:enter_arglist(I), Map),
  {Fun, Map1} = conv_fun(hipe_rtl:enter_fun(I), Map0),
  I2 = mk_enter(Fun, Args, hipe_rtl:enter_type(I)),
  {I2, Map1, Data}.

mk_enter(Fun, Args, Linkage) ->
  {FixFunC,FunC} = fix_func(Fun),
  Arity = length(Args),
  {RegArgs,StkArgs} = split_args(Args),
  FixFunC ++
    move_actuals(RegArgs,
		 [hipe_ppc:mk_pseudo_tailcall_prepare(),
		  hipe_ppc:mk_pseudo_tailcall(FunC, Arity, StkArgs, Linkage)]).

conv_goto(I, Map, Data) ->
  I2 = [hipe_ppc:mk_b_label(hipe_rtl:goto_label(I))],
  {I2, Map, Data}.

conv_label(I, Map, Data) ->
  I2 = [hipe_ppc:mk_label(hipe_rtl:label_name(I))],
  {I2, Map, Data}.

conv_load(I, Map, Data) ->
  {Dst, Map0} = conv_dst(hipe_rtl:load_dst(I), Map),
  {Base1, Map1} = conv_src(hipe_rtl:load_src(I), Map0),
  {Base2, Map2} = conv_src(hipe_rtl:load_offset(I), Map1),
  LoadSize = hipe_rtl:load_size(I),
  LoadSign = hipe_rtl:load_sign(I),
  I2 = mk_load(Dst, Base1, Base2, LoadSize, LoadSign),
  {I2, Map2, Data}.

mk_load(Dst, Base1, Base2, LoadSize, LoadSign) ->
  case hipe_ppc:is_temp(Base1) of
    true ->
      case hipe_ppc:is_temp(Base2) of
	true ->
	  mk_load_rr(Dst, Base1, Base2, LoadSize, LoadSign);
	_ ->
	  mk_load_ri(Dst, Base1, Base2, LoadSize, LoadSign)
      end;
    _ ->
      case hipe_ppc:is_temp(Base2) of
	true ->
	  mk_load_ri(Dst, Base2, Base1, LoadSize, LoadSign);
	_ ->
	  mk_load_ii(Dst, Base1, Base2, LoadSize, LoadSign)
      end
  end.

mk_load_ii(Dst, Base1, Base2, LoadSize, LoadSign) ->
  io:format("~w: RTL load with two immediates\n", [?MODULE]),
  Tmp = new_untagged_temp(),
  mk_li(Tmp, Base1,
	mk_load_ri(Dst, Tmp, Base2, LoadSize, LoadSign)).
   
mk_load_ri(Dst, Base, Disp, LoadSize, LoadSign) ->
  if Disp >= -32768, Disp < 32768 ->
      LdOp =
	case LoadSize of
	  byte -> 'lbz';
	  int32 -> 'lwz';
	  word -> 'lwz';
	  int16 ->
	    case LoadSign of
	      signed -> 'lha';
	      unsigned -> 'lhz'
	    end
	end,
      I1 = hipe_ppc:mk_load(LdOp, Dst, Disp, Base),
      I2 =
	case LoadSize of
	  byte ->
	    case LoadSign of
	      signed -> [hipe_ppc:mk_unary('extsb', Dst, Dst)];
	      _ -> []
	    end;
	  _ -> []
	end,
      [I1 | I2];
     true ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Disp,
	    mk_load_rr(Dst, Base, Tmp, LoadSize, LoadSign))
  end.

mk_load_rr(Dst, Base1, Base2, LoadSize, LoadSign) ->
  LdxOp =
    case LoadSize of
      byte -> 'lbzx';
      int32 -> 'lwzx';
      word -> 'lwzx';
      int16 ->
	case LoadSign of
	  signed -> 'lhax';
	  unsigned -> 'lhzx'
	end
    end,
  I1 = hipe_ppc:mk_loadx(LdxOp, Dst, Base1, Base2),
  I2 =
    case LoadSize of
      byte ->
	case LoadSign of
	  signed -> [hipe_ppc:mk_unary('extsb', Dst, Dst)];
	  _ -> []
	end;
      _ -> []
    end,
  [I1 | I2].

conv_load_address(I, Map, Data) ->
  {Dst, Map0} = conv_dst(hipe_rtl:load_address_dst(I), Map),
  Addr = hipe_rtl:load_address_address(I),
  Type = hipe_rtl:load_address_type(I),
  Src = {Addr,Type},
  I2 = [hipe_ppc:mk_pseudo_li(Dst, Src)],
  {I2, Map0, Data}.

conv_load_atom(I, Map, Data) ->
  {Dst, Map0} = conv_dst(hipe_rtl:load_atom_dst(I), Map),
  Src = hipe_rtl:load_atom_atom(I),
  I2 = [hipe_ppc:mk_pseudo_li(Dst, Src)],
  {I2, Map0, Data}.

conv_move(I, Map, Data) ->
  {Dst, Map0} = conv_dst(hipe_rtl:move_dst(I), Map),
  {Src, Map1} = conv_src(hipe_rtl:move_src(I), Map0),
  I2 = mk_move(Dst, Src, []),
  {I2, Map1, Data}.

mk_move(Dst, Src, Tail) ->
  case hipe_ppc:is_temp(Src) of
    true -> [hipe_ppc:mk_pseudo_move(Dst, Src) | Tail];
    _ -> mk_li(Dst, Src, Tail)
  end.

conv_return(I, Map, Data) ->
  %% TODO: multiple-value returns
  {[Arg], Map0} = conv_src_list(hipe_rtl:return_varlist(I), Map),
  I2 = mk_move(mk_rv(), Arg,
	       [hipe_ppc:mk_pseudo_ret(-1)]), % frame fills in npop later
  {I2, Map0, Data}.

conv_store(I, Map, Data) ->
  {Base1, Map0} = conv_dst(hipe_rtl:store_base(I), Map),
  {Src, Map1} = conv_src(hipe_rtl:store_src(I), Map0),
  {Base2, Map2} = conv_src(hipe_rtl:store_offset(I), Map1),
  StoreSize = hipe_rtl:store_size(I),
  I2 = mk_store(Src, Base1, Base2, StoreSize),
  {I2, Map2, Data}.

mk_store(Src, Base1, Base2, StoreSize) ->
  case hipe_ppc:is_temp(Src) of
    true ->
      mk_store2(Src, Base1, Base2, StoreSize);
    _ ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Src,
	    mk_store2(Tmp, Base1, Base2, StoreSize))
  end.

mk_store2(Src, Base1, Base2, StoreSize) ->
  case hipe_ppc:is_temp(Base2) of
    true ->
      mk_store_rr(Src, Base1, Base2, StoreSize);
    _ ->
      mk_store_ri(Src, Base1, Base2, StoreSize)
  end.
  
mk_store_ri(Src, Base, Disp, StoreSize) ->
  if Disp >= -32768, Disp < 32768 ->
      StOp =
	case StoreSize of
	  byte -> 'stb';
	  int16 -> 'sth';
	  int32 -> 'stw';
	  word -> 'stw'
	end,
      [hipe_ppc:mk_store(StOp, Src, Disp, Base)];
     true ->
      Tmp = new_untagged_temp(),
      mk_li(Tmp, Disp,
	    mk_store_rr(Src, Base, Tmp, StoreSize))
  end.
   
mk_store_rr(Src, Base1, Base2, StoreSize) ->
  StxOp =
    case StoreSize of
      byte -> 'stbx';
      int16 -> 'sthx';
      int32 -> 'stwx';
      word -> 'stwx'
    end,
  [hipe_ppc:mk_storex(StxOp, Src, Base1, Base2)].

conv_switch(I, Map, Data) ->
  Labels = hipe_rtl:switch_labels(I),
  LMap = [{label,L} || L <- Labels],
  {NewData, JTabLab} =
    case hipe_rtl:switch_sort_order(I) of
      [] ->
	hipe_consttab:insert_block(Data, word, LMap);
      SortOrder ->
	hipe_consttab:insert_sorted_block(
	  Data, word, LMap, SortOrder)
    end,
  %% no immediates allowed here
  {IndexR, Map1} = conv_dst(hipe_rtl:switch_src(I), Map),
  JTabR = new_untagged_temp(),
  OffsetR = new_untagged_temp(),
  DestR = new_untagged_temp(),
  I2 =
    [hipe_ppc:mk_pseudo_li(JTabR, {JTabLab,constant}),
     hipe_ppc:mk_alu('slwi', OffsetR, IndexR, hipe_ppc:mk_uimm16(2)),
     hipe_ppc:mk_loadx('lwzx', DestR, JTabR, OffsetR),
     hipe_ppc:mk_mtspr('ctr', DestR),
     hipe_ppc:mk_bctr(Labels)],
  {I2, Map1, NewData}.

%%% Create a conditional branch.
%%% If the condition tests CR0[SO], rewrite the path
%%% corresponding to SO being set to clear XER[SO].

mk_pseudo_bc(BCond, TrueLabel, FalseLabel, Pred) ->
  case BCond of
    'so' ->
      NewTrueLabel = hipe_gensym:get_next_label(ppc),
      [hipe_ppc:mk_pseudo_bc(BCond, NewTrueLabel, FalseLabel, Pred),
       hipe_ppc:mk_label(NewTrueLabel),
       hipe_ppc:mk_mcrxr(),
       hipe_ppc:mk_b_label(TrueLabel)];
    'ns' ->
      NewFalseLabel = hipe_gensym:get_next_label(ppc),
      [hipe_ppc:mk_pseudo_bc(BCond, TrueLabel, NewFalseLabel, Pred),
       hipe_ppc:mk_label(NewFalseLabel),
       hipe_ppc:mk_mcrxr(),
       hipe_ppc:mk_b_label(FalseLabel)];
    _ ->
      [hipe_ppc:mk_pseudo_bc(BCond, TrueLabel, FalseLabel, Pred)]
  end.

%%% Load an integer constant into a register.

mk_li(Dst, Value) -> mk_li(Dst, Value, []).

mk_li(Dst, Value, Tail) ->
  hipe_ppc:mk_li(Dst, Value, Tail).

%%% Check if an RTL ALU or ALUB operator commutes.

rtl_aluop_commutes(RtlAluOp) ->
  case RtlAluOp of
    'add' -> true;
    'or'  -> true;
    'and' -> true;
    'xor' -> true;
    _	  -> false
  end.

%%% Split a list of formal or actual parameters into the
%%% part passed in registers and the part passed on the stack.
%%% The parameters passed in registers are also tagged with
%%% the corresponding registers.

split_args(Args) ->
  split_args(0, hipe_ppc_registers:nr_args(), Args, []).

split_args(I, N, [Arg|Args], RegArgs) when I < N ->
  Reg = hipe_ppc_registers:arg(I),
  Temp = hipe_ppc:mk_temp(Reg, 'tagged'),
  split_args(I+1, N, Args, [{Arg,Temp}|RegArgs]);
split_args(_, _, StkArgs, RegArgs) ->
  {RegArgs, StkArgs}.

%%% Convert a list of actual parameters passed in
%%% registers (from split_args/1) to a list of moves.

move_actuals([{Src,Dst}|Actuals], Rest) ->
  move_actuals(Actuals, mk_move(Dst, Src, Rest));
move_actuals([], Rest) ->
  Rest.

%%% Convert a list of formal parameters passed in
%%% registers (from split_args/1) to a list of moves.

move_formals([{Dst,Src}|Formals], Rest) ->
  move_formals(Formals, [hipe_ppc:mk_pseudo_move(Dst, Src) | Rest]);
move_formals([], Rest) ->
  Rest.

%%% Convert a 'fun' operand (MFA, prim, or temp)

conv_fun(Fun, Map) ->
  case hipe_rtl:is_var(Fun) of
    true ->
      conv_dst(Fun, Map);
    false ->
      case hipe_rtl:is_reg(Fun) of
	true ->
	  conv_dst(Fun, Map);
	false ->
	  if is_atom(Fun) ->
	      {hipe_ppc:mk_prim(Fun), Map};
	     true ->
	      {conv_mfa(Fun), Map}
	  end
      end
  end.

%%% Convert an MFA operand.

conv_mfa({M,F,A}) when is_atom(M), is_atom(F), is_integer(A) ->
  hipe_ppc:mk_mfa(M, F, A).

%%% Convert an RTL source operand (imm/var/reg).
%%% Returns a temp or a naked integer.

conv_src(Opnd, Map) ->
  case hipe_rtl:is_imm(Opnd) of
    true ->
      Value = hipe_rtl:imm_value(Opnd),
      if is_integer(Value) ->
	  {Value, Map}
      end;
    false ->
      conv_dst(Opnd, Map)
  end.

conv_src_list([O|Os], Map) ->
  {V, Map1} = conv_src(O, Map),
  {Vs, Map2} = conv_src_list(Os, Map1),
  {[V|Vs], Map2};
conv_src_list([], Map) ->
  {[], Map}.

%%% Convert an RTL destination operand (var/reg).

conv_fpreg(Opnd, Map) ->
  case hipe_rtl:is_fpreg(Opnd) of
    true -> conv_dst(Opnd, Map)
  end.

conv_dst(Opnd, Map) ->
  {Name, Type} =
    case hipe_rtl:is_var(Opnd) of
      true ->
	{hipe_rtl:var_index(Opnd), 'tagged'};
      false ->
	case hipe_rtl:is_fpreg(Opnd) of
	  true ->
	    {hipe_rtl:fpreg_index(Opnd), 'double'};
	  false ->
	    {hipe_rtl:reg_index(Opnd), 'untagged'}
	end
    end,
  IsPrecoloured =
    case Type of
      'double' -> hipe_ppc_registers:is_precoloured_fpr(Name);
      _ -> hipe_ppc_registers:is_precoloured_gpr(Name)
    end,
  case IsPrecoloured of
    true ->
      {hipe_ppc:mk_temp(Name, Type), Map};
    false ->
      case vmap_lookup(Map, Opnd) of
	{value, {_, NewTemp}} ->
	  {NewTemp, Map};
	false ->
	  NewTemp = hipe_ppc:mk_new_temp(Type),
	  {NewTemp, vmap_bind(Map, Opnd, NewTemp)}
      end
  end.

conv_dst_list([O|Os], Map) ->
  {Dst, Map1} = conv_dst(O, Map),
  {Dsts, Map2} = conv_dst_list(Os, Map1),
  {[Dst|Dsts], Map2};
conv_dst_list([], Map) ->
  {[], Map}.

conv_formals(Os, Map) ->
  conv_formals(hipe_ppc_registers:nr_args(), Os, Map, []).

conv_formals(N, [O|Os], Map, Res) ->
  Type =
    case hipe_rtl:is_var(O) of
      true -> 'tagged';
      _ -> 'untagged'
    end,
  Dst =
    if N > 0 -> hipe_ppc:mk_new_temp(Type);	% allocatable
       true -> hipe_ppc:mk_new_nonallocatable_temp(Type)
    end,
  Map1 = vmap_bind(Map, O, Dst),
  conv_formals(N-1, Os, Map1, [Dst|Res]);
conv_formals(_, [], Map, Res) ->
  {lists:reverse(Res), Map}.

%%% Create a temp representing the stack pointer register.

mk_sp() ->
  hipe_ppc:mk_temp(hipe_ppc_registers:stack_pointer(), 'untagged').

%%% Create a temp representing the return value register.

mk_rv() ->
  hipe_ppc:mk_temp(hipe_ppc_registers:return_value(), 'tagged').

%%% new_untagged_temp -- conjure up an untagged scratch reg

new_untagged_temp() ->
  hipe_ppc:mk_new_temp('untagged').

%%% new_tagged_temp -- conjure up a tagged scratch reg

new_tagged_temp() ->
  hipe_ppc:mk_new_temp('tagged').

%%% Map from RTL var/reg operands to temps.

vmap_empty() ->
    [].

vmap_lookup(VMap, Opnd) ->
    lists:keysearch(Opnd, 1, VMap).

vmap_bind(VMap, Opnd, Temp) ->
    [{Opnd, Temp} | VMap].

word_size() ->
  hipe_rtl_arch:word_size().
