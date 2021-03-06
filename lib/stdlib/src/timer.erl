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
-module(timer).

-export([apply_after/4,
	 send_after/3, send_after/2,
	 exit_after/3, exit_after/2, kill_after/2, kill_after/1,
	 apply_interval/4, send_interval/3, send_interval/2,
	 cancel/1, sleep/1, tc/3, now_diff/2,
	 seconds/1, minutes/1, hours/1, hms/3]).

-export([start_link/0, start/0, 
	 handle_call/3,  handle_info/2,  
	 init/1,
	 code_change/3, handle_cast/2, terminate/2]).

%% internal exports for test purposes only
-export([get_status/0]).

%% Max
-define(MAX_TIMEOUT, 16#0800000).
-define(TIMER_TAB, timer_tab).
-define(INTERVAL_TAB, timer_interval_tab).

%%
%% Interface functions
%%
%% Time is in milliseconds.
%%
apply_after(Time, M, F, A) ->
    req(apply_after, {Time, {M, F, A}}).

send_after(Time, Pid, Message) ->
    req(apply_after, {Time, {?MODULE, send, [Pid, Message]}}).

send_after(Time, Message) ->
    send_after(Time, self(), Message).

exit_after(Time, Pid, Reason) ->
    req(apply_after, {Time, {erlang, exit, [Pid, Reason]}}).

exit_after(Time, Reason) ->
    exit_after(Time, self(), Reason).

kill_after(Time, Pid) ->
    exit_after(Time, Pid, kill).

kill_after(Time) ->
    exit_after(Time, self(), kill).

apply_interval(Time, M, F, A) ->
    req(apply_interval, {Time, self(), {M, F, A}}).

send_interval(Time, Pid, Message) ->
    req(apply_interval, {Time, Pid, {?MODULE, send, [Pid, Message]}}).

send_interval(Time, Message) ->
    send_interval(Time, self(), Message).

cancel(BRef) ->
    req(cancel, BRef).

sleep(T) ->
    receive
    after T -> ok
    end.

%%
%% Measure the execution time (in microseconds) for an MFA.
%%
tc(M, F, A) ->
    Before = erlang:now(),
    Val = (catch apply(M, F, A)),
    After = erlang:now(),
    {now_diff(After, Before), Val}.

%%
%% Calculate the time difference (in microseconds) of two
%% erlang:now() timestamps, T2-T1.
%%
now_diff({A2, B2, C2}, {A1, B1, C1}) ->
    ((A2-A1)*1000000 + B2-B1)*1000000 + C2-C1.

%%
%% Convert seconds, minutes etc. to milliseconds.    
%%
seconds(Seconds) ->
    1000*Seconds.
minutes(Minutes) ->
    1000*60*Minutes.
hours(Hours) ->
    1000*60*60*Hours.
hms(H, M, S) ->
    hours(H) + minutes(M) + seconds(S).

%%   
%%   Start/init functions
%%

%%   Start is only included because of backward compatibility!
start() ->
    ensure_started().

start_link() ->
    gen_server:start_link({local, timer_server}, ?MODULE, [], []).    

init([]) ->
    process_flag(trap_exit, true),
    ets:new(?TIMER_TAB,[named_table,ordered_set,protected]),
    ets:new(?INTERVAL_TAB,[named_table,protected]),
    {ok, [], infinity}.

ensure_started() ->
    case whereis(timer_server) of
	undefined -> 
	    C = {timer_server, {?MODULE, start_link, []}, permanent, 1000, 
		 worker, [?MODULE]},
	    supervisor:start_child(kernel_safe_sup, C),  % kernel_safe_sup
	    ok;
	_ -> ok
    end.

%% server calls

req(Req, Arg) ->
    SysTime = system_time(),
    ensure_started(),
    gen_server:call(timer_server, {Req, Arg, SysTime}, infinity).

%%
%% handle_call(Request, From, Timers) -> 
%%  {reply, Response, Timers, Timeout}
%%
%% Time and Timeout is in milliseconds. Started is in microseconds.
%%
handle_call({apply_after, {Time, Op}, Started}, _From, _Ts) 
  when is_integer(Time), Time >= 0 ->
    BRef = {Started + 1000*Time, make_ref()},
    Timer = {BRef, timeout, Op},
    ets:insert(?TIMER_TAB, Timer),
    Timeout = timer_timeout(system_time()),
    {reply, {ok, BRef}, [], Timeout};

handle_call({apply_interval, {Time, To, MFA}, Started}, _From, _Ts) 
  when is_integer(Time), Time >= 0 ->
    %% To must be a pid or a registered name
    case get_pid(To) of
	Pid when is_pid(Pid) ->
	    catch link(Pid),
	    SysTime = system_time(),
	    Ref = make_ref(),
	    BRef1 = {interval, Ref},
	    Interval = Time*1000,
	    BRef2 = {Started + Interval, Ref},
	    Timer = {BRef2, {repeat, Interval, Pid}, MFA},
	    ets:insert(?INTERVAL_TAB,{BRef1,BRef2,Pid}),
	    ets:insert(?TIMER_TAB, Timer),
	    Timeout = timer_timeout(SysTime),
	    {reply, {ok, BRef1}, [], Timeout};
	_ ->
	    {reply, {error, badarg}, [], next_timeout()}
    end;

handle_call({cancel, BRef = {_Time, Ref}, _}, _From, Ts) 
                                           when is_reference(Ref) ->
    delete_ref(BRef),
    {reply, {ok, cancel}, Ts, next_timeout()};
handle_call({cancel, _BRef, _}, _From, Ts) ->
    {reply, {error, badarg}, Ts, next_timeout()};
handle_call({apply_after, _, _}, _From, Ts) ->
    {reply, {error, badarg}, Ts, next_timeout()};
handle_call({apply_interval, _, _}, _From, Ts) ->
    {reply, {error, badarg}, Ts, next_timeout()};
handle_call(_Else, _From, Ts) ->			% Catch anything else
    {noreply, Ts, next_timeout()}.

handle_info(timeout, Ts) ->                     % Handle timeouts 
    Timeout = timer_timeout(system_time()),
    {noreply, Ts, Timeout};
handle_info({'EXIT',  Pid, _Reason}, Ts) ->      % Oops, someone died
    pid_delete(Pid),
    {noreply, Ts, next_timeout()};
handle_info(_OtherMsg, Ts) ->                         % Other Msg's
    {noreply, Ts, next_timeout()}.

handle_cast(_Req, Ts) ->                         % Not predicted but handled
    {noreply, Ts, next_timeout()}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    %% According to the man for gen server no timer can be set here.
    {ok, State}.				

%% 
%% timer_timeout(Timers, SysTime)
%%
%% Apply and remove already timed-out timers. A timer is a tuple
%% {Time, BRef, Op, MFA}, where Time is in microseconds.
%% Returns {Timeout, Timers}, where Timeout is in milliseconds.
%%
timer_timeout(SysTime) ->
    case ets:first(?TIMER_TAB) of
	'$end_of_table' -> 
	    infinity;
	{Time, _Ref} when Time > SysTime ->
	    Timeout = (Time - SysTime) div 1000,
	    %% Returned timeout must fit in a small int
	    min(Timeout, ?MAX_TIMEOUT);
	Key ->
	    case ets:lookup(?TIMER_TAB, Key) of
		[{Key, timeout, MFA}] ->
		    ets:delete(?TIMER_TAB,Key),
		    do_apply(MFA),
		    timer_timeout(SysTime);
		[{{Time, Ref}, Repeat = {repeat, Interv, To}, MFA}] ->
		    ets:delete(?TIMER_TAB,Key),
		    NewTime = Time + Interv,
		    %% Update the interval entry (last in table)
		    ets:insert(?INTERVAL_TAB,{{interval,Ref},{NewTime,Ref},To}),
		    do_apply(MFA),
		    ets:insert(?TIMER_TAB, {{NewTime, Ref}, Repeat, MFA}),
		    timer_timeout(SysTime)
	    end
    end.

%%
%% delete_ref 
%%

delete_ref(BRef = {interval, _}) ->
    case ets:lookup(?INTERVAL_TAB, BRef) of
	[{_, BRef2, _Pid}] ->
	    ets:delete(?INTERVAL_TAB, BRef),
	    ets:delete(?TIMER_TAB, BRef2);
	_ -> % TimerReference does not exist, do nothing
	    ok
    end;
delete_ref(BRef) ->
    ets:delete(?TIMER_TAB,BRef).

%%
%% pid_delete
%%

pid_delete(Pid) ->
    IntervalTimerList = 
	ets:select(?INTERVAL_TAB,
		   [{{'_', '_','$1'},
		     [{'==','$1',Pid}],
		     ['$_']}]),
    lists:foreach(fun({IntKey, TimerKey, _ }) ->
			  ets:delete(?INTERVAL_TAB,IntKey),
			  ets:delete(?TIMER_TAB,TimerKey) 
		  end, IntervalTimerList).

%% Calculate time to the next timeout. Returned timeout must fit in a 
%% small int.

next_timeout() ->
    case ets:first(?TIMER_TAB) of
	'$end_of_table' -> 
	    infinity;
	{Time, _ } ->
	    min(positive((Time - system_time()) div 1000), ?MAX_TIMEOUT)
    end.

%% Help functions
do_apply({M,F,A}) ->
    case {M, F, A} of
	{?MODULE, send, A} -> 
	    %% If send op. send directly, (faster than spawn)
	    catch send(A);
	{erlang, exit, [Name, Reason]} ->
	    catch exit(get_pid(Name), Reason);
	_ -> 
	    %% else spawn process with the operation
	    catch spawn(M,F,A)      
    end.

max(X, Y) when X > Y ->
    X;
max(_X, Y) ->
    Y.

min(X, Y) when X < Y ->
    X;
min(_X, Y) ->
    Y.

positive(X) ->
    max(X, 0).


%%
%%  system_time() -> time in microseconds
%%
system_time() ->    
    {M,S,U} = erlang:now(),
    1000000*(M*1000000 + S) + U.


send([Pid, Msg]) ->
    Pid ! Msg.

get_pid(Name) when is_pid(Name) ->
    Name;
get_pid(undefined) ->
    undefined;
get_pid(Name) when is_atom(Name) ->
    get_pid(whereis(Name));
get_pid(_) ->
    undefined.

%%
%% get_status() -> 
%%    {{TimerTabName,TotalNumTimers},{IntervalTabName,NumIntervalTimers}}
%%
%% This function is for test purposes only; it is used by the test suite.
%% There is a small possibility that there is a mismatch of one entry 
%% between the 2 tables if this call is made when the timer server is 
%% in the middle of a transaction
 
get_status() ->
    Info1 = ets:info(?TIMER_TAB),
    {value,{size,TotalNumTimers}} = lists:keysearch(size, 1, Info1),
    Info2 = ets:info(?INTERVAL_TAB),
    {value,{size,NumIntervalTimers}} = lists:keysearch(size, 1, Info2),
    {{?TIMER_TAB,TotalNumTimers},{?INTERVAL_TAB,NumIntervalTimers}}.
