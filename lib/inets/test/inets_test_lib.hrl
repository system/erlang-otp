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
%% Purpose: Define common macros for testing
%%----------------------------------------------------------------------

%% - Print macros - 

-ifdef(inets_debug).
-define(DEBUG(F,A), inets_test_lib:debug(F, A, ?MODULE, ?LINE)).
-else.
-define(DEBUG(F,A),ok).
-endif.

-ifdef(inets_log).
-define(LOG(F,A),   inets_test_lib:log(F, A, ?MODULE, ?LINE)).
-else.
-define(LOG(F,A),ok).
-endif.

-define(INFO(F,A),  inets_test_lib:info(F, A, ?MODULE, ?LINE)).
-define(PRINT(F,A), inets_test_lib:print(F, A, ?MODULE, ?LINE)).


%% - Macros stolen from the test server -

-define(line,put(test_server_loc,{?MODULE,?LINE}),).


%% - App macros -

-define(APP_TEST(), inets_test_lib:app_test()).


%% - Test case macros -

-define(EXPANDABLE(I, C, F), inets_test_lib:expandable(I, C, F)).


%% - Misc macros -

-define(CONFIG(K,C),    inets_test_lib:get_config(K,C)).
-define(HOSTNAME(),     inets_test_lib:hostname()).
-define(SZ(X),          inets_test_lib:sz(X)).


%% - Test case macros - 

-define(SKIP(Reason),   inets_test_lib:skip(Reason)).
-define(FAIL(Reason),   inets_test_lib:fail(Reason, ?MODULE, ?LINE)).


%% - Socket macros -

-define(CONNECT(M,H,P), inets_test_lib:connect(M,H,P)).
-define(SEND(M,S,D),    inets_test_lib:send(M,S,D)).
-define(CLOSE(M,S),     inets_test_lib:close(M,S)).


%% - Time macros -

-define(HOURS(N),       inets_test_lib:hours(N)).
-define(MINS(N),        inets_test_lib:minutes(N)).
-define(SECS(N),        inets_test_lib:seconds(N)).

-define(WD_START(T),    inets_test_lib:watchdog_start(T)).
-define(WD_STOP(P),     inets_test_lib:watchdog_stop(P)).

-define(SLEEP(MSEC),    inets_test_lib:sleep(MSEC)).
-define(M(),            inets_test_lib:millis()).
-define(MDIFF(A,B),     inets_test_lib:millis_diff(A,B)).


%% - Process utility macros - 

-define(FLUSH(),        inets_test_lib:flush_mqueue()).
-define(ETRAP_GET(),    inets_test_lib:trap_exit()).
-define(ETRAP_SET(O),   inets_test_lib:trap_exit(O)).



