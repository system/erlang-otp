%%--------------------------------------------------------------------
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
%%-----------------------------------------------------------------
%% File: orber_iiop_inproxy.erl
%% 
%% Description:
%%    This file contains the IIOP "proxy" for incomming connections
%%
%% Creation date: 990425
%%
%%-----------------------------------------------------------------
-module(orber_iiop_inproxy).

-behaviour(gen_server).

-include_lib("orber/src/orber_iiop.hrl").
-include_lib("orber/include/corba.hrl").
-include_lib("orber/src/orber_debug.hrl").

%%-----------------------------------------------------------------
%% External exports
%%-----------------------------------------------------------------
-export([start/0, start/1]).

%%-----------------------------------------------------------------
%% Internal exports
%%-----------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 code_change/3, terminate/2, stop/0]).

%%-----------------------------------------------------------------
%% Macros
%%-----------------------------------------------------------------
-define(DEBUG_LEVEL, 7).

%%-----------------------------------------------------------------
%% External interface functions
%%-----------------------------------------------------------------
%%-----------------------------------------------------------------
%% Func: start/0
%%-----------------------------------------------------------------
start() ->
    ignore.

%%-----------------------------------------------------------------
%% Func: start/1
%%-----------------------------------------------------------------
start(Opts) ->
    gen_server:start_link(orber_iiop_inproxy, Opts, []).

%%-----------------------------------------------------------------
%% Internal interface functions
%%-----------------------------------------------------------------
%%-----------------------------------------------------------------
%% Func: stop/0 (Only used for test purpose !!!!!!)
%%-----------------------------------------------------------------
stop() ->
    gen_server:call(orber_iiop_inproxy, stop).

%%-----------------------------------------------------------------
%% Server functions
%%-----------------------------------------------------------------
%%-----------------------------------------------------------------
%% Func: init/1
%%-----------------------------------------------------------------
init({connect, Type, Socket}) ->
    ?PRINTDEBUG2("orber_iiop_inproxy init: ~p ", [self()]),
    process_flag(trap_exit, true),
    case orber:get_interceptors() of
	false ->
	    {ok, {Socket, Type, ets:new(orber_incoming_requests, [set]), false}};
	{native, PIs} ->
	    {ok, {{N1,N2,N3,N4}, Port}} = inet:peername(Socket),
	    Address = lists:concat([N1, ".", N2, ".", N3, ".", N4]),
	    ?PRINTDEBUG2("orber_iiop_inproxy init PIs: ~p ~p ~p", [PIs, Address, Port]),
	    {ok, {Socket, Type, ets:new(orber_incoming_requests, [set]),
		  {native, orber_pi:new_in_connection(PIs, Address, Port), PIs}}};
	{Type, PIs} ->
	    ?PRINTDEBUG2("orber_iiop_inproxy init PIs: ~p ", [PIs]),
	    {ok, {Socket, Type, ets:new(orber_incoming_requests, [set]), {Type, PIs}}}
    end.

%%-----------------------------------------------------------------
%% Func: terminate/2
%%-----------------------------------------------------------------
%% We may want to kill all proxies before terminating, but the best
%% option should be to let the requests complete (especially for one-way
%% functions it's a better alternative.
%% kill_all_proxies(IncRequests, ets:first(IncRequests)),
terminate(Reason, {Socket, Type, IncRequests, Interceptors}) ->
    ets:delete(IncRequests),
    if
	Reason == normal ->
	    ok;
	true ->
	    orber:debug_level_print("[~p] orber_iiop_inproxy:terminate(~p)", 
				    [?LINE, Reason], ?DEBUG_LEVEL)
    end,
    case Interceptors of 
	false ->
	    ok;
	{native, Ref, PIs} ->
	    orber_pi:closed_in_connection(PIs, Ref);
	{Type, PIs} ->
	    ok
    end.

kill_all_proxies(_, '$end_of_table') ->
    ok;
kill_all_proxies(IncRequests, Key) ->
    exit(Key, kill),
    kill_all_proxies(IncRequests, ets:next(IncRequests, Key)).

%%-----------------------------------------------------------------
%% Func: handle_call/3
%%-----------------------------------------------------------------
handle_call(stop, From, State) ->
    {stop, normal, ok, State};
handle_call(_, _, State) ->
    {noreply, State}.

%%-----------------------------------------------------------------
%% Func: handle_cast/2
%%-----------------------------------------------------------------
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_, State) ->
    {noreply, State}.

%%-----------------------------------------------------------------
%% Func: handle_info/2
%%-----------------------------------------------------------------
handle_info({tcp_closed, Socket}, State) ->
    {stop, normal, State};
handle_info({tcp_error, Socket}, State) ->
    {stop, normal, State};
handle_info({tcp, Socket, Bytes}, {Socket, normal, IncRequests, Interceptors}) ->
    Pid = orber_iiop_inrequest:start(Bytes, normal, Socket, Interceptors),
    ets:insert(IncRequests, {Pid, undefined}),
    {noreply, {Socket, normal, IncRequests, Interceptors}};
handle_info({ssl_closed, Socket}, State) ->
    {stop, normal, State};
handle_info({ssl_error, Socket}, State) ->
    {stop, normal, State};
handle_info({ssl, Socket, Bytes}, {Socket, ssl, IncRequests, Interceptors}) ->
    Pid = orber_iiop_inrequest:start(Bytes, ssl, Socket, Interceptors),
    ets:insert(IncRequests, {Pid, undefined}),
    {noreply, {Socket, ssl, IncRequests, Interceptors}};
handle_info({'EXIT', Pid, normal}, {Socket, Type, IncRequests, Interceptors}) ->
    ets:delete(IncRequests, Pid),
    {noreply, {Socket, Type, IncRequests, Interceptors}};
handle_info({'EXIT', Pid, Reason}, {Socket, Type, IncRequests, Interceptors}) ->
    ?PRINTDEBUG2("proxy ~p finished with reason ~p", [Pid, Reason]),
    ets:delete(IncRequests, Pid),
    {noreply, {Socket, Type, IncRequests, Interceptors}};
handle_info(X,State) ->
    {noreply, State}.


%%-----------------------------------------------------------------
%% Func: code_change/3
%%-----------------------------------------------------------------
code_change({down, OldVsn}, {Socket, Type, IncRequests, Interceptors},interceptors) ->
    {ok, {Socket, Type, IncRequests}};
code_change(OldVsn, {Socket, Type, IncRequests}, interceptors) ->
    case orber:get_interceptors() of
	false ->
	    {ok, {Socket, Type, IncRequests, false}};
	{native, PIs} ->
	    {ok, {{N1,N2,N3,N4}, Port}} = inet:peername(Socket),
	    Address = lists:concat([N1, ".", N2, ".", N3, ".", N4]),
	    {ok, {Socket, Type, IncRequests, 
		  {native, orber_pi:new_in_connection(PIs, Address, Port), PIs}}};
	{Type, PIs} ->
	    {ok, {Socket, Type, IncRequests, {Type, PIs}}}
    end;
code_change(OldVsn, State, Extra) ->
    {ok, State}.

