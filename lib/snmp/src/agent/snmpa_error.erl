%%<copyright>
%% <year>2002-2007</year>
%% <holder>Ericsson AB, All Rights Reserved</holder>
%%</copyright>
%%<legalnotice>
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% The Initial Developer of the Original Code is Ericsson AB.
%%</legalnotice>
%%
-module(snmpa_error).

-behaviour(snmpa_error_report).


%%%-----------------------------------------------------------------
%%% Implements different error mechanisms.
%%%-----------------------------------------------------------------
-export([user_err/2, config_err/2]).


%%-----------------------------------------------------------------
%% This function is called when there is an error in a user
%% supplied item, e.g. instrumentation function.
%%-----------------------------------------------------------------
user_err(F, A) -> 
    report_err(user_err, F, A).


%%-----------------------------------------------------------------
%% This function is called when there is a configuration error,
%% either at startup (in a conf-file) or at run-time (e.g. when 
%% information in the configuration tables are inconsistent.)
%%-----------------------------------------------------------------
config_err(F, A) ->
    report_err(config_err, F, A).


%% -----------------------------------------------------------------


report_err(Func, Format, Args) ->
    case report_module() of
	{ok, Mod} ->
	    (catch Mod:Func(Format, Args));
	_ ->
	    ok
    end.
       

    
report_module() ->
    case (catch ets:lookup(snmp_agent_table, error_report_mod)) of
	[{error_report_mod, Mod}] ->
	    {ok, Mod};
	_ ->
	    error
    end.
