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
%% Purpose: Profile a system in order to figure out where the 
%% time goes.
%%

-module(eprof).
-behaviour(gen_server).

-export([start/0, stop/0, dump/0, total_analyse/0,
	 start_profiling/1, profile/2, profile/4, profile/1,
	 stop_profiling/0, analyse/0, log/1]).

%% Internal exports 
-export([init/1,
	 call/4,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2]).

-import(lists, [flatten/1,reverse/1,keysort/2]).


-record(state, {table = notable,
		proc = noproc,
		profiling = false, 
		pfunc = undefined,
		pop = running,
		ptime = 0,
		overhead = 0,
		rootset = []}).

%%%%%%%%%%%%%%

start() -> gen_server:start({local, eprof}, eprof, [], []).
stop()  -> gen_server:call(eprof, stop, infinity).


profile(Pids, Fun) ->
    start(),
    gen_server:call(eprof, {profile,Pids,erlang,apply,[Fun,[]]},infinity).

profile(Pids, M, F, A) ->
    start(),
    gen_server:call(eprof, {profile,Pids,M,F,A},infinity).

dump() -> 
    gen_server:call(eprof, dump, infinity).

analyse() ->
    gen_server:call(eprof, analyse, infinity).

log(File) ->
    gen_server:call(eprof, {logfile, File}, infinity).

total_analyse() ->
    gen_server:call(eprof, total_analyse, infinity).

start_profiling(Rootset) ->
    start(),
    gen_server:call(eprof, {profile, Rootset}, infinity).

stop_profiling() ->
    gen_server:call(eprof, stop_profiling, infinity).

profile(Rs) ->
    start_profiling(Rs).

%%%%%%%%%%%%%%%%

init(_) ->
    process_flag(trap_exit, true),
    process_flag(priority, max), 
    {ok, #state{}}.

subtr({X1,Y1,Z1}, {X1,Y1,Z2}) ->
    Z1 - Z2;
subtr({X1,Y1,Z1}, {X2,Y2,Z2}) ->
    (((X1 * 1000000) + Y1) * 1000000 + Z1) -
	(((X2 * 1000000) + Y2) * 1000000 + Z2).


into_tab(Tab, Key, call, Time) ->
    case catch ets:update_counter(Tab, Key, Time) of
	{'EXIT',{badarg,_}} ->
	    ets:insert(Tab, {Key,Time,1});
	NewTime when integer(NewTime) ->
	    ets:update_counter(Tab, Key, {3,1})
    end;
into_tab(Tab, Key, Op, Time) ->
    case catch ets:update_counter(Tab, Key, Time) of
	{'EXIT',{badarg,_}} ->
	    ets:insert(Tab, {Key,Time,0});
	NewTime when integer(NewTime) ->
	    ok
    end.

do_messages({trace_ts,From,Op,Mfa,Time}, Tab, undefined, PrevOp0, PrevTime0) ->
    PrevFunc = {From,Mfa},
    receive
	{trace_ts,_,_,_,_}=Ts -> do_messages(Ts, Tab, PrevFunc, Op, Time)
    after 0 ->
	    {PrevFunc,Op,Time}
    end;
do_messages({trace_ts,From,Op,Mfa,Time}, Tab, PrevFunc0, PrevOp0, PrevTime0) ->
    into_tab(Tab, PrevFunc0, PrevOp0, subtr(Time, PrevTime0)),
    PrevFunc = case Op of
		   exit -> undefined;
		   out -> undefined;
		   Other -> {From,Mfa}
	       end,
    receive
	{trace_ts,_,_,_,_}=Ts -> do_messages(Ts, Tab, PrevFunc, Op, Time)
    after 0 ->
	    {PrevFunc,Op,Time}
    end.

%%%%%%%%%%%%%%%%%%

handle_cast(Req, S) -> {noreply, S}.

terminate(Reason, S) ->
    call_trace_for_all(false),
    normal.

%%%%%%%%%%%%%%%%%%

handle_call({logfile, F}, _FromTag, Status) ->
    case file:open(F, write) of
	{ok, Fd} ->
	    case get(fd) of
		undefined -> ok;
		FdOld -> file:close(FdOld)
	    end,
	    put(fd, Fd),
	    {reply, ok, Status};
	{error, _} ->
	    {reply, error, Status}
    end;

handle_call({profile, Rootset}, {From, _Tag}, S) ->
    link(From),
    maybe_delete(S#state.table),
    io:format("eprof: Starting profiling ..... ~n",[]),
    ptrac(S#state.rootset, false, all()),
    flush_receive(),
    Tab = ets:new(eprof, [set, public]),
    case ptrac(Rootset, true, all()) of
	false ->
	    {reply, error,  #state{}};
	true ->
	    call_trace_for_all(true),
	    erase(replyto),
	    {reply, profiling, #state{table = Tab,
				      proc = From,
				      profiling = true,
				      rootset = Rootset}}
    end;

handle_call(stop_profiling, _FromTag, S) when S#state.profiling == true ->
    ptrac(S#state.rootset, false, all()),
    call_trace_for_all(false),
    io:format("eprof: Stop profiling~n",[]),
    ets:delete(S#state.table, nofunc),
    {reply, profiling_stopped, S#state{profiling = false}};

handle_call(stop_profiling, _FromTag, S) ->
    {reply, profiling_already_stopped, S};

handle_call({profile, Rootset, M, F, A}, FromTag, S) ->
    io:format("eprof: Starting profiling..... ~n", []),
    maybe_delete(S#state.table),
    ptrac(S#state.rootset, false, all()),
    flush_receive(),
    put(replyto, FromTag),
    Tab = ets:new(eprof, [set, public]),
    P = spawn_link(eprof, call, [self(), M, F, A]),
    case ptrac([P|Rootset], true, all()) of
	true ->
	    call_trace_for_all(true),
	    {noreply, #state{table     = Tab, 
			     profiling = true,
			     rootset   = [P|Rootset]}};
	false ->
	    erase(replyto),
	    {reply, error, #state{}}
    end;

handle_call(dump, _FromTag, S) ->
    {reply, dump(S#state.table), S};

handle_call(analyse, _FromTag, S) ->
    {reply, analyse(S), S};

handle_call(total_analyse, _FromTag, S) ->
    {reply, total_analyse(S), S};

handle_call(stop, _FromTag, S) ->
    {stop, normal, stopped, S}.

%%%%%%%%%%%%%%%%%%%

handle_info({trace_ts, From, Op, Func, Time}=M, S0) when S0#state.profiling == true ->
    Start = erlang:now(),
    #state{table=Tab,pop=PrevOp0,ptime=PrevTime0,pfunc=PrevFunc0,
	   overhead=Overhead0} = S0,
    {PrevFunc,PrevOp,PrevTime} = do_messages(M, Tab, PrevFunc0, PrevOp0, PrevTime0),
    Overhead = Overhead0 + subtr(erlang:now(), Start),
    S = S0#state{overhead=Overhead,pfunc=PrevFunc,pop=PrevOp,ptime=PrevTime},
    {noreply,S};

handle_info({trace_ts, From, _, _, _}, S) when S#state.profiling == false ->
    ptrac([From], false, all()),
    {noreply, S};

handle_info({P, {answer, A}}, S) ->
    ptrac(S#state.rootset, false, all()),
    io:format("eprof: Stop profiling~n",[]),
    {From, Tag} = get(replyto),
    catch unlink(From),
    ets:delete(S#state.table, nofunc),
    gen_server:reply(erase(replyto), {ok, A}),
    {noreply, S#state{profiling = false,
		      rootset = []}};

handle_info({'EXIT', P, Reason}, S) when S#state.profiling == true,
                                         S#state.proc == P  ->
    maybe_delete(S#state.table),
    ptrac(S#state.rootset, false, all()),
    io:format("eprof: Fail profiling~n",[]),
    case erase(replyto) of
	undefined ->
	    {noreply, #state{}};
	FromTag ->
	    gen_server:reply(FromTag, {error, Reason}),
	    {noreply, #state{}}
    end;

handle_info({'EXIT', P, Reason}, S) ->
    {noreply, S}.

%%%%%%%%%%%%%%%%%%

call(Top, M, F, A) ->
    Top ! {self(), {answer, apply(M,F,A)}}.

call_trace_for_all(Flag) ->
    erlang:trace_pattern(on_load, Flag, [local]),
    erlang:trace_pattern({'_','_','_'}, Flag, [local]).

ptrac([P|T], How, Flags) when pid(P) ->
    case dotrace(P, How, Flags) of
	true ->
	    ptrac(T, How, Flags);
	false when How == true ->
	    false;
	false ->
	    ptrac(T, How, Flags)
    end;

ptrac([P|T], How, Flags) when atom(P) ->
    case whereis(P) of
	undefined when How == true ->
	    false;
	undefined when How == false ->
	    ptrac(T, How, Flags);
	Pid ->
	    ptrac([Pid|T], How, Flags)
    end;

ptrac([H|T], How, Flags) ->
    io:format("** eprof bad process ~w~n",[H]),
    false;

ptrac([],_,_) -> true.

dotrace(P, How, What) ->
    case (catch erlang:trace(P, How, What)) of
	1 ->
	    true;
	Other when How == false ->
	    true;
	Other ->
	    io:format("** eprof: bad process: ~p,~p,~p~n", [P,How,What]),
	    false
    end.

all() -> [call,arity,return_to,running,timestamp,set_on_spawn].

total_analyse(#state{table=notable}) ->
    nothing_to_analyse;
total_analyse(S) ->
    #state{table = T, overhead = Overhead} = S,
    Pcalls = reverse(keysort(2, replicas(ets:tab2list(T)))),
    Time = collect_times(Pcalls),
    format("FUNCTION~44s      TIME ~n", ["CALLS"]),   
    printit(Pcalls, Time),
    format("\nTotal time: ~.2f\n", [Time / 1000000]),
    format("Measurement overhead: ~.2f\n", [Overhead / 1000000]).

analyse(#state{table=notable}) ->
    nothing_to_analyse;
analyse(S) ->
    #state{table = T, overhead = Overhead} = S,
    Pids = ordsets:list_to_set(flatten(ets:match(T, {{'$1','_'},'_', '_'}))),
    Times = sum(ets:match(T, {'_','$1', '_'})),
    format("FUNCTION~44s      TIME ~n", ["CALLS"]),     
    do_pids(Pids, T, 0, Times),
    format("\nTotal time: ~.2f\n", [Times / 1000000]),
    format("Measurement overhead: ~.2f\n", [Overhead / 1000000]).

do_pids([Pid|Tail], T, AckTime, Total) ->
    Pcalls = 
     reverse(keysort(2, to_tups(ets:match(T, {{Pid,'$1'}, '$2','$3'})))),
    Time = collect_times(Pcalls),
    PercentTotal = 100 * (divide(Time, Total)),
    format("~n****** Process ~w    -- ~s % of profiled time *** ~n", 
	   [Pid, fpf(PercentTotal)]),
    printit(Pcalls, Time),
    do_pids(Tail, T, AckTime + Time, Total);
do_pids([], _, _, _) -> 
    ok.

printit([],_) -> ok;
printit([{{Mod,Fun,Arity}, Time, Calls} |Tail], ProcTime)  ->
    format("~s  ~s ~s % ~n", [ff(Mod,Fun,Arity), fint(Calls),
			      fpf(100*(divide(Time,ProcTime)))]),
    printit(Tail, ProcTime);
printit([{{_,{Mod,Fun,Arity}}, Time, Calls} |Tail], ProcTime)  ->
    format("~s  ~s ~s % ~n", [ff(Mod,Fun,Arity), fint(Calls),
			      fpf(100*(divide(Time,ProcTime)))]),
    printit(Tail, ProcTime); 
printit([_|T], Time) ->
    printit(T, Time).

ff(Mod,Fun,Arity) ->
    pad(flatten(io_lib:format("~w:~w/~w", [Mod,Fun, Arity])),45).

pad(Str, Len) -> 
    Strlen = length(Str),
    if
	Strlen > Len -> strip_tail(Str, 45);
	true -> lists:append(Str, mklist(Len-Strlen))
    end.

strip_tail([H|T], 0) ->[];
strip_tail([H|T], I) -> [H|strip_tail(T, I-1)];
strip_tail([], I) -> [].

fpf(F) -> strip_tail(flatten(io_lib:format("~w", [round(F)])), 5).
fint(Int) -> pad(flatten(io_lib:format("~w",[Int])), 10).

mklist(0) -> [];
mklist(I) -> [$ |mklist(I-1)].

to_tups(L) -> lists:map(fun(List) -> erlang:list_to_tuple(List) end, L).

divide(X,Y) -> X / Y.

collect_times([]) -> 0;
collect_times([Tup|Tail]) -> element(2, Tup) + collect_times(Tail).

dump(T) ->
    L = ets:tab2list(T),
    format(L).

format([H|T]) -> 
    format("~p~n", [H]), format(T);
format([]) -> ok.

format(F, A) ->
    io:format(F,A),
    case get(fd) of
	undefined -> ok;
	Fd -> io:format(Fd, F,A)
    end.

maybe_delete({T,Ref}) when reference(Ref) ->
    ets:delete({T, Ref});
maybe_delete(_) -> ok.

sum([[H]|T]) -> H + sum(T);
sum([]) -> 0.

replicas(L) ->
    replicas(L, []).

replicas([{{Pid, {Mod,Fun,Arity}}, Ack,Calls} |Tail], Result) ->
    case search({Mod,Fun,Arity},Result) of
	false ->
	    replicas(Tail, [{{Pid, {Mod,Fun,Arity}}, Ack,Calls} |Result]);
	{Ack2, Calls2} ->
	    Result2 = del({Mod,Fun,Arity}, Result),
	    replicas(Tail, [{{Pid, {Mod,Fun,Arity}}, 
			     Ack+Ack2,Calls+Calls2} |Result2])
    end;

replicas([_|T], Ack) ->  %% Whimpy
    replicas(T, Ack);

replicas([], Res) -> Res.

search(Key, [{{_,Key}, Ack, Calls}|_]) -> 
    {Ack, Calls};
search(Key, [_|T]) -> 
    search(Key, T);
search(Key, []) -> false.

del(Key, [{{_,Key}, Ack, Calls}|T]) ->
    T;
del(Key, [H | Tail]) ->
    [H|del(Key, Tail)];
del(Key, []) -> [].

flush_receive() ->
    receive 
	{trace_ts, From, _, _, _} when pid(From) ->
	    ptrac([From], false, all()),
	    flush_receive();
	_ ->
	    flush_receive()
    after 0 ->
	    ok
    end.
