%%% -*- erlang-indent-level: 2 -*-
%%% $Id: hipe_amd64_ra_postconditions.erl,v 1.5 2005/04/01 08:40:17 mikpe Exp $

-define(HIPE_AMD64,			true).
-define(HIPE_X86_RA_POSTCONDITIONS,	hipe_amd64_ra_postconditions).
-define(HIPE_X86_REGISTERS,		hipe_amd64_registers).
-define(HIPE_X86_SPECIFIC,		hipe_amd64_specific).
-define(ECX,				rcx).
-include("../x86/hipe_x86_ra_postconditions.erl").
