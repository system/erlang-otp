%%<copyright>
%% <year>2004-2008</year>
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
%%----------------------------------------------------------------------
%% Purpose: The top supervisor for the ftp hangs under inets_sup.
%%----------------------------------------------------------------------
-module(ftp_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_child/1]).

%% Supervisor callback
-export([init/1]).

%%%=========================================================================
%%%  API
%%%=========================================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Args) ->
    supervisor:start_child(?MODULE, Args).
    
%%%=========================================================================
%%%  Supervisor callback
%%%=========================================================================
init(_) ->
    RestartStrategy = simple_one_for_one,
    MaxR = 0,
    MaxT = 3600,
   
    Name = undefined, % As simple_one_for_one is used.
    StartFunc = {ftp, start_link, []},
    Restart = temporary, % E.g. should not be restarted
    Shutdown = 4000,
    Modules = [ftp],
    Type = worker,
    
    ChildSpec = {Name, StartFunc, Restart, Shutdown, Type, Modules},
    {ok, {{RestartStrategy, MaxR, MaxT}, [ChildSpec]}}.
