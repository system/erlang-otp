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
-module(cpu_sup).

%%% Purpose : Obtain cpu statistics on Solaris 2

-export([nprocs/0,avg1/0,avg5/0,avg15/0,ping/0]).

%% External exports
-export([start_link/0, start/0, stop/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(APPLICATION,"os_mon").
-define(PORT_PROG,"/bin/cpu_sup"). %% This is relative priv_dir
-define(NAME,cpu_sup).

%% Internal protocol with the port program
-define(nprocs,"n").
-define(avg1,"1").
-define(avg5,"5").
-define(avg15,"f").
-define(quit,"q").
-define(ping,"p").

-record(state, {port}).

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------

start()  -> gen_server:start({local, cpu_sup}, cpu_sup, [], []).
start_link() -> gen_server:start_link({local, cpu_sup}, cpu_sup, [], []).
stop()   -> gen_server:call(?NAME,?quit).

nprocs() -> gen_server:call(?NAME,?nprocs).
avg1()   -> gen_server:call(?NAME,?avg1).
avg5()   -> gen_server:call(?NAME,?avg5).
avg15()  -> gen_server:call(?NAME,?avg15).
ping()   -> gen_server:call(?NAME,?ping).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          {stop, Reason}
%%----------------------------------------------------------------------
init([]) ->
    Prog = code:priv_dir(?APPLICATION) ++ ?PORT_PROG,
    Port = open_port({spawn,Prog},[stream]),
    if port(Port) ->
	    {ok, #state{port=Port}};
       true ->
	    {stop, {port_prog_not_available,Port}}
    end.

%%----------------------------------------------------------------------
%% Func: handle_call/3
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, Reply, State}     (terminate/2 is called)
%%----------------------------------------------------------------------
handle_call(?quit, From, State) ->
    State#state.port ! {self(), {command, ?quit}},
    State#state.port ! {self(), close},
    {stop, shutdown, ok, State};
handle_call(Request, From, State) ->
    Reply = get_measurement(Request,State#state.port),
    {reply, Reply, State}.

%%----------------------------------------------------------------------
%% Func: handle_cast/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_cast(Msg, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_info({Port,closed}, State) when Port == State#state.port ->
    {stop, port_closed, State#state{port=closed}};
handle_info(Info, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: terminate/2
%% Purpose: Shutdown the server
%% Returns: any (ignored by gen_server)
%%----------------------------------------------------------------------
terminate(Reason, State) ->
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

get_measurement(Request,Port) ->
    Port ! {self(), {command, Request}},
    receive
	{Port,{data,[D3,D2,D1,D0]}} ->
	    (D3 bsl 24) bor (D2 bsl 16) bor (D1 bsl 8) bor D0
    end.

%%%----------------------------------------------------------------------
