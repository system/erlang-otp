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
%%----------------------------------------------------------------------
%% File    : CosTimerEvent_TimerEventService_impl.erl
%% Purpose : 
%% Created : 10 Feb 2000
%%----------------------------------------------------------------------

-module('CosTimerEvent_TimerEventService_impl').

%%--------------- INCLUDES -----------------------------------
-include("cosTimeApp.hrl").


%%--------------- EXPORTS ------------------------------------
%%--------------- External -----------------------------------
%% Interface functions
-export([register/4, unregister/3, event_time/3]).

%%--------------- gen_server specific exports ----------------
-export([handle_info/2, code_change/3]).
-export([init/1, terminate/2]).


%% Data structures
-record(state, {timer}).
%% Data structures constructors
-define(get_InitState(T), 
	#state{timer=T}).

%% Data structures selectors
-define(get_TimerObj(S),    S#state.timer).

%% Data structures modifiers

%% MISC

%%-----------------------------------------------------------%
%% function : handle_info, code_change
%% Arguments: 
%% Returns  : 
%% Effect   : Functions demanded by the gen_server module. 
%%------------------------------------------------------------

code_change(OldVsn, State, Extra) ->
    {ok, State}.

handle_info(Info, State) ->
    ?debug_print("INFO: ~p~n", [Info]),
    {noreply, State}.

%%----------------------------------------------------------%
%% function : init, terminate
%% Arguments: 
%%-----------------------------------------------------------

init([Timer]) ->
    process_flag(trap_exit, true),
    timer:start(),
    {ok, ?get_InitState(Timer)}.

terminate(Reason, State) ->
    ok.

%%-----------------------------------------------------------
%%------- Exported external functions -----------------------
%%-----------------------------------------------------------
%%----------------------------------------------------------%
%% function : register
%% Arguments: EventInterface - CosEventComm::PushConsumer
%%            Data - #any
%% Returns  : TimerEventHandler - objref#
%%-----------------------------------------------------------
register(OE_THIS, State, EventInterface, Data) ->
    {reply, 
     cosTime:start_event_handler([OE_THIS, self(),EventInterface, Data, 
				  ?get_TimerObj(State)]), 
     State}.

%%----------------------------------------------------------%
%% function : unregister
%% Arguments: TimerEventHandler - objref#
%% Returns  : ok
%%-----------------------------------------------------------
unregister(OE_THIS, State, TimerEventHandler) ->
    catch corba:dispose(TimerEventHandler),
    {reply, ok, State}.

%%----------------------------------------------------------%
%% function : event_time
%% Arguments: TimerEvent - #'CosTimerEvent_TimerEventT'{utc, event_data}
%% Returns  : CosTime::UTO
%%-----------------------------------------------------------
event_time(OE_THIS, State, #'CosTimerEvent_TimerEventT'{utc=Utc}) ->
    {reply,  'CosTime_UTO':oe_create([Utc],[{pseudo,true}]), State}.


%%--------------- LOCAL FUNCTIONS ----------------------------

%%--------------- MISC FUNCTIONS, E.G. DEBUGGING -------------
%%--------------- END OF MODULE ------------------------------