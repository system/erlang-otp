%% ``The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved via the world wide web at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% The Initial Developer of the Original Code is Ericsson Utvecklings AB.
%% Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
%% AB. All Rights Reserved.''
%% 
%%     $Id$
%%
%%----------------------------------------------------------------------
%% Purpose: The top supervisor for the Megaco/H.248 application
%%----------------------------------------------------------------------

-module(megaco_misc_sup).

-behaviour(supervisor).

%% public
-export([start/0, start/2, stop/1, init/1]).
-export([start_permanent_worker/4]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% application and supervisor callback functions

start(normal, Args) ->
    SupName = {local,?MODULE},
    case supervisor:start_link(SupName, ?MODULE, [Args]) of
	{ok, Pid} ->
	    {ok, Pid, {normal, Args}};
	Error -> 
	    Error
    end;
start(_, _) ->
    {error, badarg}.

start() ->
    SupName = {local,?MODULE},
    supervisor:start_link(SupName, ?MODULE, []).

stop(StartArgs) ->
    ok.

init([]) -> % Supervisor
    init();
init(BadArg) ->
    {error, {badarg, BadArg}}.

init() ->
    Flags     = {one_for_one, 0, 1},
    KillAfter = timer:seconds(1),
    Workers   = [],
    {ok, {Flags, Workers}}.


%%----------------------------------------------------------------------
%% Function: start_permanent_worker/3
%% Description: Starts a permanent worker (child) process
%%----------------------------------------------------------------------

start_permanent_worker(M, F, A, Modules) ->
    Spec = {M, {M,F,A}, permanent, timer:seconds(1), worker, [M] ++ Modules},
    supervisor:start_child(?MODULE, Spec).

    

