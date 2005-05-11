%%% -*- erlang-indent-level: 2 -*-
%%% $Id: hipe_amd64_ra_ls.erl,v 1.5 2005/03/31 19:46:00 mikpe Exp $

-define(HIPE_X86_RA_LS,			hipe_amd64_ra_ls).
-define(HIPE_X86_LIVENESS,		hipe_amd64_liveness).
-define(HIPE_X86_PP,			hipe_amd64_pp).
-define(HIPE_X86_RA_LS_POSTCONDITIONS,	hipe_amd64_ra_ls_postconditions).
-define(HIPE_X86_REGISTERS,		hipe_amd64_registers).
-define(HIPE_X86_SPECIFIC,		hipe_amd64_specific).
-define(HIPE_X86_SPECIFIC_FP,		hipe_amd64_specific_fp).
-include("../x86/hipe_x86_ra_ls.erl").
