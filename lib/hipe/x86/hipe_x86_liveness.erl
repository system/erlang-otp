%%% -*- erlang-indent-level: 2 -*-
%%% $Id$
%%% x86_liveness -- compute register liveness for x86 CFGs

-ifdef(HIPE_AMD64).
-define(HIPE_X86_LIVENESS,	hipe_amd64_liveness).
-define(HIPE_X86_DEFUSE,	hipe_amd64_defuse).
-define(HIPE_X86_REGISTERS,	hipe_amd64_registers).
-else.
-define(HIPE_X86_LIVENESS,	hipe_x86_liveness).
-define(HIPE_X86_DEFUSE,	hipe_x86_defuse).
-define(HIPE_X86_REGISTERS,	hipe_x86_registers).
-endif.

-module(?HIPE_X86_LIVENESS).

-export([analyse/1]).
-export([liveout/2]).

-include("../x86/hipe_x86.hrl").  % ../x86/ is needed when included in amd64
-include("../flow/liveness.inc").

analyse(CFG) -> analyze(CFG).
cfg_bb(CFG, L) -> hipe_x86_cfg:bb(CFG, L).
cfg_postorder(CFG) -> hipe_x86_cfg:postorder(CFG).
cfg_succ(CFG, L) -> hipe_x86_cfg:succ(CFG, L).
uses(Insn) -> ?HIPE_X86_DEFUSE:insn_use(Insn).
defines(Insn) -> ?HIPE_X86_DEFUSE:insn_def(Insn).
liveout_no_succ() ->
  ordsets:from_list(lists:map(fun({Reg,Type}) ->
				  hipe_x86:mk_temp(Reg, Type)
			      end,
			      ?HIPE_X86_REGISTERS:live_at_return())).

-ifdef(DEBUG_LIVENESS).
cfg_labels(CFG) -> hipe_x86_cfg:labels(CFG).
cfg_bb_add(CFG,L,NewBB) -> hipe_x86_cfg:bb_add(CFG,L,NewBB).
mk_comment(Text) -> hipe_x86:mk_comment(Text).
-endif.
