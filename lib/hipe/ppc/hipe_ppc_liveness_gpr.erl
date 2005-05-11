%%% -*- erlang-indent-level: 2 -*-
%%% $Id: hipe_ppc_liveness_gpr.erl,v 1.1 2004/12/06 03:09:39 mikpe Exp $

-module(hipe_ppc_liveness_gpr).
-export([analyse/1]).
-export([liveout/2]).
-include("../flow/liveness.inc").

analyse(CFG) -> analyze(CFG).
cfg_bb(CFG, L) -> hipe_ppc_cfg:bb(CFG, L).
cfg_postorder(CFG) -> hipe_ppc_cfg:postorder(CFG).
cfg_succ_map(CFG) -> hipe_ppc_cfg:succ_map(CFG).
cfg_succ(CFG, L) -> hipe_ppc_cfg:succ(CFG, L).
uses(Insn) -> hipe_ppc_defuse:insn_use_gpr(Insn).
defines(Insn) -> hipe_ppc_defuse:insn_def_gpr(Insn).
liveout_no_succ() ->
  ordsets:from_list(lists:map(fun({Reg,Type}) ->
				  hipe_ppc:mk_temp(Reg, Type)
			      end,
			      hipe_ppc_registers:live_at_return())).
