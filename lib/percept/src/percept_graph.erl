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

%% @doc Interface for CGI request on graphs used by percept. The module exports two functions that are implementations for ESI callbacks used by the httpd server. See http://www.erlang.org//doc/apps/inets/index.html.

-module(percept_graph).
-export([proc_lifetime/3, graph/3, scheduler_graph/3, activity/3, percentage/3]).

-include("percept.hrl").
-include_lib("kernel/include/file.hrl").

%% API

%% graph
%% @spec graph(SessionID, Env, Input) -> term()
%% @doc An ESI callback implementation used by the httpd server. 
%% 

graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    case graph(Env,Input) of
    	Binaries when is_list(Binaries) ->
	    lists:foreach(fun (B) ->
        	mod_esi:deliver(SessionID, binary_to_list(B))
	    end, Binaries);
	Binary ->
	    mod_esi:deliver(SessionID, binary_to_list(Binary))
    end.

%% activity
%% @spec activity(SessionID, Env, Input) -> term() 
%% @doc An ESI callback implementation used by the httpd server.

activity(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    case activity_bar(Env,Input) of
    	Binaries when is_list(Binaries) ->
	    lists:foreach(fun (B) ->
        	mod_esi:deliver(SessionID, binary_to_list(B))
	    end, Binaries);
	Binary ->
	    mod_esi:deliver(SessionID, binary_to_list(Binary))
    end.

proc_lifetime(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    case proc_lifetime(Env,Input) of
    	Binaries when is_list(Binaries) ->
	    lists:foreach(fun (B) ->
        	mod_esi:deliver(SessionID, binary_to_list(B))
	    end, Binaries);
	Binary ->
	    mod_esi:deliver(SessionID, binary_to_list(Binary))
    end.

percentage(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    case percentage(Env,Input) of
    	Binaries when is_list(Binaries) ->
	    lists:foreach(fun (B) ->
        	mod_esi:deliver(SessionID, binary_to_list(B))
	    end, Binaries);
	Binary ->
	    mod_esi:deliver(SessionID, binary_to_list(Binary))
    end.

scheduler_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    case scheduler_graph(Env,Input) of
    	Binaries when is_list(Binaries) ->
	    lists:foreach(fun (B) ->
        	mod_esi:deliver(SessionID, binary_to_list(B))
	    end, Binaries);
	Binary ->
	    mod_esi:deliver(SessionID, binary_to_list(Binary))
    end.

graph(_Env, Input) ->
    Query = httpd:parse_query(Input),
   
    RangeMin = percept_html:get_option_value("range_min", Query),
    RangeMax = percept_html:get_option_value("range_max", Query),
    Pids = percept_html:get_option_value("pids", Query),
    Width = percept_html:get_option_value("width", Query),
    Height = percept_html:get_option_value("height", Query),
    
    % Convert Pids to id option list
    IDs = [ {id, ID} || ID <- Pids],
   
    % seconds2ts
    StartTs = percept_db:select({system, start_ts}),
    TsMin = percept_analyzer:seconds2ts(RangeMin, StartTs),
    TsMax = percept_analyzer:seconds2ts(RangeMax, StartTs),
    
    Options = [{ts_exact, true},{ts_min, TsMin},{ts_max, TsMax} | IDs],
    
    Activities = percept_db:select({activity, Options}),
    
    Counts = percept_analyzer:activities2count(Activities, StartTs),
    
    percept_image:graph(Width, Height,Counts).

scheduler_graph(_Env, Input) -> 
    Query = httpd:parse_query(Input),
    RangeMin = percept_html:get_option_value("range_min", Query),
    RangeMax = percept_html:get_option_value("range_max", Query),
    Width = percept_html:get_option_value("width", Query),
    Height = percept_html:get_option_value("height", Query),
    
    StartTs = percept_db:select({system, start_ts}),
    TsMin = percept_analyzer:seconds2ts(RangeMin, StartTs),
    TsMax = percept_analyzer:seconds2ts(RangeMax, StartTs),
    
    Activities = percept_db:select({scheduler, [{ts_min, TsMin}, {ts_max,TsMax}]}),
    
    Counts = [{?seconds(Ts, StartTs), Scheds, 0} || 
    	#activity{where = Scheds, timestamp = Ts} <- Activities],

    percept_image:graph(Width, Height, Counts).

activity_bar(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Pid = percept_html:get_option_value("pid", Query),
    Min = percept_html:get_option_value("range_min", Query),
    Max = percept_html:get_option_value("range_max", Query),
    Width = percept_html:get_option_value("width", Query),
    Height = percept_html:get_option_value("height", Query),
    
    Data = percept_db:select({activity, [{id, Pid}]}),
    StartTs = percept_db:select({system, start_ts}),
    Activities = [{?seconds(Ts, StartTs), State} || 
    	#activity{timestamp = Ts, state = State} <- Data],
    
    percept_image:activities(Width, Height, {Min,Max},Activities).

proc_lifetime(_Env, Input) ->
    Query = httpd:parse_query(Input),
    ProfileTime = percept_html:get_option_value("profiletime", Query),
    Start = percept_html:get_option_value("start", Query),
    End = percept_html:get_option_value("end", Query),
    Width = percept_html:get_option_value("width", Query),
    Height = percept_html:get_option_value("height", Query),
    percept_image:proc_lifetime(round(Width), round(Height), float(Start), float(End), float(ProfileTime)).

percentage(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Width = percept_html:get_option_value("width", Query),
    Height = percept_html:get_option_value("height", Query),
    Percentage = percept_html:get_option_value("percentage", Query),
    percept_image:percentage(round(Width), round(Height), float(Percentage)).

header() ->
    "Content-Type: image/jpeg\r\n\r\n".
