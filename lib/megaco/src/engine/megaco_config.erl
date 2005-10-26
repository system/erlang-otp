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
%% Purpose: Handle configuration of Megaco/H.248
%%----------------------------------------------------------------------

-module(megaco_config).

-behaviour(gen_server).

%% Application internal exports
-export([
         start_link/0,

         start_user/2,
         stop_user/1,

         user_info/2,
         update_user_info/3,
         conn_info/2,
         update_conn_info/3,
         system_info/1,

         %% incr_counter/2,
         incr_trans_id_counter/1,
         incr_trans_id_counter/2,
         verify_val/2,

	 %% Pending limit counter
	 cre_pending_counter/3,
	 get_pending_counter/2,
	 incr_pending_counter/2,
	 del_pending_counter/2,
	 %% Backward compatibillity functions (to be removed in later versions)
	 cre_pending_counter/1,  
	 get_pending_counter/1,  
	 incr_pending_counter/1, 
	 del_pending_counter/1,  

         lookup_local_conn/1,
         connect/4,
         disconnect/1,
	 connect_remote/3,
	 disconnect_remote/2,
	 init_conn_data/4,

	 trans_sender_exit/2

        ]).


%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-record(state, {parent_pid}).

-include_lib("megaco/include/megaco.hrl").
-include("megaco_internal.hrl").


-ifdef(MEGACO_TEST_CODE).
-define(megaco_test_init(),
	(catch ets:new(megaco_test_data, [set, public, named_table]))).
-else.
-define(megaco_test_init(),
	ok).
-endif.


%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------

start_link() ->
    ?d("start_link -> entry", []),
    gen_server:start_link({local, ?SERVER}, ?MODULE, [self()], []).

start_user(UserMid, Config) ->
    call({start_user, UserMid, Config}).

stop_user(UserMid) ->
    call({stop_user, UserMid}).

user_info(UserMid, all) ->
    All = ets:match_object(megaco_config, {{UserMid, '_'}, '_'}),
    [{Item, Val} || {{_, Item}, Val} <- All, Item /= trans_sender];
user_info(UserMid, receive_handle) ->
    case call({receive_handle, UserMid}) of
	{ok, RH} ->
	    RH;
	{error, Reason} ->
	    exit(Reason)
    end;
user_info(UserMid, conn_data) ->
    HandlePat = #megaco_conn_handle{local_mid = UserMid, remote_mid = '_'},
    Pat = #conn_data{conn_handle      	= HandlePat,
                     serial           	= '_',
                     max_serial       	= '_',
                     request_timer    	= '_',
                     long_request_timer = '_',

                     auto_ack         	= '_',

                     trans_ack   	= '_',
                     trans_ack_maxcount	= '_',

                     trans_req   	= '_',
                     trans_req_maxcount	= '_',
                     trans_req_maxsize	= '_',

                     trans_timer   	= '_',
                     trans_sender       = '_',

                     pending_timer     	= '_',
                     sent_pending_limit = '_',
                     recv_pending_limit = '_',
                     reply_timer      	= '_',
                     control_pid      	= '_',
                     monitor_ref      	= '_',
                     send_mod         	= '_',
                     send_handle      	= '_',
                     encoding_mod     	= '_',
                     encoding_config  	= '_',
                     protocol_version  	= '_',
                     auth_data         	= '_',
                     user_mod         	= '_',
                     user_args         	= '_',
                     reply_action     	= '_',
                     reply_data       	= '_',
		     threaded       	= '_'},
    %% ok = io:format("PATTERN: ~p~n", [Pat]),
    ets:match_object(megaco_local_conn, Pat);
user_info(UserMid, connections) ->
    [C#conn_data.conn_handle || C <- user_info(UserMid, conn_data)];
user_info(UserMid, mid) ->
    ets:lookup_element(megaco_config, {UserMid, mid}, 2);
user_info(UserMid, orig_pending_limit) ->
    user_info(UserMid, sent_pending_limit);
user_info(UserMid, Item) ->
    ets:lookup_element(megaco_config, {UserMid, Item}, 2).

update_user_info(UserMid, orig_pending_limit, Val) ->
    update_user_info(UserMid, sent_pending_limit, Val);
update_user_info(UserMid, Item, Val) ->
    call({update_user_info, UserMid, Item, Val}).

conn_info(CH, Item) when record(CH, megaco_conn_handle) ->
    case Item of
        conn_handle ->
            CH;
        mid ->
            CH#megaco_conn_handle.local_mid;
        local_mid ->
            CH#megaco_conn_handle.local_mid;
        remote_mid ->
            CH#megaco_conn_handle.remote_mid;
        conn_data ->
            case lookup_local_conn(CH) of
                [] ->
                    exit({no_such_connection, CH});
                [ConnData] ->
                    ConnData
            end;
        _ ->
            case lookup_local_conn(CH) of
                [] ->
                    exit({no_such_connection, CH});
                [ConnData] ->
                    conn_info(ConnData, Item)
            end
    end;
conn_info(CD, Item) when record(CD, conn_data) ->
    case Item of
	all ->
	    Tags0 = record_info(fields, conn_data),
	    Tags1 = replace(serial, trans_id, Tags0),
	    Tags  = [mid, local_mid, remote_mid] ++ 
		replace(max_serial, max_trans_id, Tags1),
	    [{Tag, conn_info(CD,Tag)} || Tag <- Tags, 
					 Tag /= conn_data, 
					 Tag /= trans_sender];
        conn_data          -> CD;
        conn_handle        -> CD#conn_data.conn_handle;
        mid                -> (CD#conn_data.conn_handle)#megaco_conn_handle.local_mid;
        local_mid          -> (CD#conn_data.conn_handle)#megaco_conn_handle.local_mid;
        remote_mid         -> (CD#conn_data.conn_handle)#megaco_conn_handle.remote_mid;
        trans_id           -> CD#conn_data.serial;
        max_trans_id       -> CD#conn_data.max_serial;
        request_timer      -> CD#conn_data.request_timer;
        long_request_timer -> CD#conn_data.long_request_timer;

        auto_ack           -> CD#conn_data.auto_ack;

        trans_ack          -> CD#conn_data.trans_ack;
        trans_ack_maxcount -> CD#conn_data.trans_ack_maxcount;

        trans_req          -> CD#conn_data.trans_req;
        trans_req_maxcount -> CD#conn_data.trans_req_maxcount;
        trans_req_maxsize  -> CD#conn_data.trans_req_maxsize;

        trans_timer        -> CD#conn_data.trans_timer;

        pending_timer      -> CD#conn_data.pending_timer;
        orig_pending_limit -> CD#conn_data.sent_pending_limit;
        sent_pending_limit -> CD#conn_data.sent_pending_limit;
        recv_pending_limit -> CD#conn_data.recv_pending_limit;
        reply_timer        -> CD#conn_data.reply_timer;
        control_pid        -> CD#conn_data.control_pid;
        monitor_ref        -> CD#conn_data.monitor_ref;
        send_mod           -> CD#conn_data.send_mod;
        send_handle        -> CD#conn_data.send_handle;
        encoding_mod       -> CD#conn_data.encoding_mod;
        encoding_config    -> CD#conn_data.encoding_config;
        protocol_version   -> CD#conn_data.protocol_version;
        auth_data          -> CD#conn_data.auth_data;
        user_mod           -> CD#conn_data.user_mod;
        user_args          -> CD#conn_data.user_args;
        reply_action       -> CD#conn_data.reply_action;
        reply_data         -> CD#conn_data.reply_data;
        threaded           -> CD#conn_data.threaded;
        receive_handle     ->
            LocalMid = (CD#conn_data.conn_handle)#megaco_conn_handle.local_mid,
            #megaco_receive_handle{local_mid       = LocalMid,
                                   encoding_mod    = CD#conn_data.encoding_mod,
                                   encoding_config = CD#conn_data.encoding_config,
                                   send_mod        = CD#conn_data.send_mod};
        _ ->
            exit({no_such_item, Item})
    end;
conn_info(BadHandle, _Item) ->
    {error, {no_such_connection, BadHandle}}.

replace(_, _, []) ->
    [];
replace(Item, WithItem, [Item|List]) ->
    [WithItem|List];
replace(Item, WithItem, [OtherItem|List]) ->
    [OtherItem | replace(Item, WithItem, List)].


update_conn_info(#conn_data{conn_handle = CH}, Item, Val) ->
    do_update_conn_info(CH, Item, Val);
update_conn_info(CH, Item, Val) when record(CH, megaco_conn_handle) ->
    do_update_conn_info(CH, Item, Val);
update_conn_info(BadHandle, _Item, _Val) ->
    {error, {no_such_connection, BadHandle}}.

do_update_conn_info(CH, orig_pending_limit, Val) ->
    do_update_conn_info(CH, sent_pending_limit, Val);
do_update_conn_info(CH, Item, Val) ->
    call({update_conn_data, CH, Item, Val}).


system_info(Item) ->
    case Item of
        n_active_requests ->
            ets:info(megaco_requests, size);
        n_active_replies  ->
            ets:info(megaco_replies, size);
        n_active_connections  ->
            ets:info(megaco_local_conn, size);
        users ->
            Pat = {{'_', mid}, '_'},
            [Mid || {_, Mid} <- ets:match_object(megaco_config, Pat)];
        connections ->
            [C#conn_data.conn_handle || C <- ets:tab2list(megaco_local_conn)];
	text_config ->
	    case ets:lookup(megaco_config, text_config) of
		[] ->
		    [];
		[{text_config, Conf}] ->
		    [Conf]
	    end;
		    
	BadItem ->
	    exit({no_such_item, BadItem})

    end.


get_env(Env, Default) ->
    case application:get_env(megaco, Env) of
        {ok, Val} -> Val;
        undefined -> Default
    end.

lookup_local_conn(Handle) ->
    ets:lookup(megaco_local_conn, Handle).


connect(RH, RemoteMid, SendHandle, ControlPid) ->
    ?d("connect -> entry with "
	"~n   RH:         ~p"
	"~n   RemoteMid:  ~p"
	"~n   SendHandle: ~p"
	"~n   ControlPid: ~p", [RH, RemoteMid, SendHandle, ControlPid]),
    case RemoteMid of
	{MidType, _MidValue} when atom(MidType) ->
	    call({connect, RH, RemoteMid, SendHandle, ControlPid});
	preliminary_mid ->
	    call({connect, RH, RemoteMid, SendHandle, ControlPid});
	BadMid ->
	    {error, {bad_remote_mid, BadMid}}
    end.

connect_remote(ConnHandle, UserNode, Ref) ->
    call({connect_remote, ConnHandle, UserNode, Ref}).

disconnect(ConnHandle) ->
    call({disconnect, ConnHandle}).

disconnect_remote(ConnHandle, UserNode) ->
    call({disconnect_remote, ConnHandle, UserNode}).


incr_counter(Item, Incr) ->
    case (catch ets:update_counter(megaco_config, Item, Incr)) of
        {'EXIT', _} ->
	    cre_counter(Item, Incr);
        NewVal ->
            NewVal
    end.

cre_counter(Item, Initial) ->
    case whereis(?SERVER) == self() of
	false ->
	    call({cre_counter, Item, Initial});
	true ->
	    ets:insert(megaco_config, {Item, Initial}),
	    Initial
    end.
    

cre_pending_counter(TransId) ->
    cre_pending_counter(sent, TransId, 0).

cre_pending_counter(Direction, TransId, Initial) ->
%     ?report_trace(ignore, "create pending counter", 
% 		  [Direction, TransId, Initial]),
    Counter = {pending_counter, Direction, TransId},
    cre_counter(Counter, Initial).

incr_pending_counter(TransId) ->
    incr_pending_counter(sent, TransId).

incr_pending_counter(Direction, TransId) ->
%     ?report_trace(ignore, "increment pending counter", [Direction, TransId]),
    Counter = {pending_counter, Direction, TransId},
    incr_counter(Counter, 1).

get_pending_counter(TransId) ->
    get_pending_counter(sent, TransId).

get_pending_counter(Direction, TransId) ->
%     ?report_trace(ignore, "get pending counter", [Direction, TransId]),
    Counter = {pending_counter, Direction, TransId},
    [{Counter, Val}] = ets:lookup(megaco_config, Counter),
    Val.

del_pending_counter(TransId) ->
    del_pending_counter(sent, TransId).

del_pending_counter(Direction, TransId) ->
%     ?report_trace(ignore, "delete pending counter", [Direction, TransId]),
    Counter = {pending_counter, Direction, TransId},
    ets:delete(megaco_config, Counter).


%% A wrapping transaction id counter
incr_trans_id_counter(ConnHandle) ->
    incr_trans_id_counter(ConnHandle, 1).
incr_trans_id_counter(ConnHandle, Incr) when integer(Incr), Incr > 0 ->
    case megaco_config:lookup_local_conn(ConnHandle) of
        [] ->
            {error, {no_such_connection, ConnHandle}};
        [ConnData] ->
            LocalMid  = ConnHandle#megaco_conn_handle.local_mid,
            Item      = {LocalMid, trans_id_counter},
            case (catch ets:update_counter(megaco_config, Item, Incr)) of
                {'EXIT', _} ->
                    %% The transaction counter needs to be initiated
                    reset_trans_id_counter(ConnData, ConnHandle, LocalMid, 
					   Item, Incr);
                Serial ->
                    ConnData2 = ConnData#conn_data{serial = Serial},
                    Max       = ConnData#conn_data.max_serial,
                    if
                        Max == infinity, Serial =< 4294967295 ->
                            {ok, ConnData2};
                        Serial =< Max ->
                            {ok, ConnData2};
                        true ->
                            %% The transaction id range is exhausted
                            %% Let's wrap the counter
                            reset_trans_id_counter(ConnData2, ConnHandle, 
						   LocalMid, Item, Incr)
                    end
            end
    end.

% reset_trans_id_counter(ConnData, ConnHandle, LocalMid, Item) ->
%     reset_trans_id_counter(ConnData, ConnHandle, LocalMid, Item, 1).
reset_trans_id_counter(ConnData, ConnHandle, LocalMid, Item, Incr) ->
    case whereis(?SERVER) == self() of
        false ->
            call({incr_trans_id_counter, ConnHandle});
        true ->
            Serial    = user_info(LocalMid, min_trans_id),
            ConnData2 = ConnData#conn_data{serial = Serial + (Incr-1)},
            Max       = ConnData#conn_data.max_serial,
            if
                Max == infinity,
                integer(Serial), Serial > 0, Serial =< 4294967295 ->
                    ets:insert(megaco_config, {Item, Serial}),
                    {ok, ConnData2};
                integer(Max), Max > 0,
                integer(Serial), Serial > 0, Serial =< 4294967295 ->
                    ets:insert(megaco_config, {Item, Serial}),
                    {ok, ConnData2};
                true -> 
                    {error, {bad_trans_id, Serial, Max}}
            end
    end.


trans_sender_exit(Reason, CH) ->
    ?d("trans_sender_exit -> entry with"
	"~n   Reason: ~p"
	"~n   CH: ~p", [Reason, CH]),
    cast({trans_sender_exit, Reason, CH}).


call(Request) ->
    case (catch gen_server:call(?SERVER, Request, infinity)) of
	{'EXIT', _} ->
	    {error, megaco_not_started};
	Res ->
	    Res
    end.


cast(Msg) ->
    case (catch gen_server:cast(?SERVER, Msg)) of
	{'EXIT', _} ->
	    {error, megaco_not_started};
	Res ->
	    Res
    end.


%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%----------------------------------------------------------------------

init([Parent]) ->
    ?d("init -> entry with "
	"~n   Parent: ~p", [Parent]),
    process_flag(trap_exit, true),
    case (catch do_init()) of
	ok ->
	    ?d("init -> init ok", []),
	    {ok, #state{parent_pid = Parent}};
	Else ->
	    ?d("init -> init error: ~p", [Else]),
	    {stop, Else}
    end.

do_init() ->
    ?megaco_test_init(),
    ets:new(megaco_config,      [public, named_table, {keypos, 1}]),
    ets:new(megaco_local_conn,  [public, named_table, {keypos, 2}]),
    ets:new(megaco_remote_conn, [public, named_table, {keypos, 2}, bag]),
    megaco_stats:init(megaco_stats, global_snmp_counters()),
    init_scanner(),
    init_user_defaults(),
    init_users().
    


init_scanner() ->
    case get_env(scanner, undefined) of
	undefined ->
	    Key  = text_config,
	    Data = [],
	    ets:insert(megaco_config, {Key, Data});
	flex ->
	    start_scanner(megaco_flex_scanner_handler, 
			  start_link, [], [gen_server]);
	{M, F, A, Mods} when atom(M), atom(F), list(A), list(Mods) ->
	    start_scanner(M, F, A, Mods)
    end.

start_scanner(M, F, A, Mods) ->
    case megaco_misc_sup:start_permanent_worker(M, F, A, Mods) of
	{ok, Pid, Conf} when  pid(Pid) ->
	    Key  = text_config,
	    Data = [Conf],
	    ets:insert(megaco_config, {Key, Data});
	Else ->
	    throw({scanner_start_failed, Else})
    end.

init_user_defaults() ->
    init_user_default(min_trans_id,       1),
    init_user_default(max_trans_id,       infinity), 
    init_user_default(request_timer,      #megaco_incr_timer{}),
    init_user_default(long_request_timer, infinity),

    init_user_default(auto_ack,           false),

    init_user_default(trans_ack,          false),
    init_user_default(trans_ack_maxcount, 10),

    init_user_default(trans_req,          false),
    init_user_default(trans_req_maxcount, 10),
    init_user_default(trans_req_maxsize,  2048),

    init_user_default(trans_timer,        0),
    init_user_default(trans_sender,       undefined),

    init_user_default(pending_timer,      timer:seconds(30)),
    init_user_default(sent_pending_limit, infinity),
    init_user_default(recv_pending_limit, infinity),
    init_user_default(reply_timer,        timer:seconds(30)),
    init_user_default(send_mod,           megaco_tcp),
    init_user_default(encoding_mod,       megaco_pretty_text_encoder),
    init_user_default(protocol_version,   1),
    init_user_default(auth_data,          asn1_NOVALUE),
    init_user_default(encoding_config,    []),
    init_user_default(user_mod,           megaco_user_default),
    init_user_default(user_args,          []),
    init_user_default(reply_data,         undefined),
    init_user_default(threaded,           false).

init_user_default(Item, Default) when Item /= mid ->
    Val = get_env(Item, Default),
    case do_update_user(default, Item, Val) of
	ok ->
	    ok;
	{error, Reason} ->
	    throw(Reason)
    end.

init_users() ->
    Users = get_env(users, []),
    init_users(Users).

init_users([]) ->
    ok;
init_users([{UserMid, Config} | Rest]) ->
    case handle_start_user(UserMid, Config) of
        ok ->
            init_users(Rest);
        Else ->
            throw({bad_user, UserMid, Else})
    end;
init_users(BadConfig) ->
    throw({bad_config, users, BadConfig}).

%%----------------------------------------------------------------------
%% Func: handle_call/3
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------

handle_call({cre_counter, Item, Incr}, _From, S) ->
    Reply = cre_counter(Item, Incr),
    {reply, Reply, S};

handle_call({del_counter, Item, Incr}, _From, S) ->
    Reply = cre_counter(Item, Incr),
    {reply, Reply, S};

handle_call({incr_trans_id_counter, ConnHandle}, _From, S) ->
    Reply = incr_trans_id_counter(ConnHandle),
    {reply, Reply, S};

handle_call({receive_handle, UserMid}, _From, S) ->
    case catch make_receive_handle(UserMid) of
	{'EXIT', _} ->
	    {reply, {error, {no_receive_handle, UserMid}}, S};
	RH ->
	    {reply, {ok, RH}, S}
    end;
handle_call({connect, RH, RemoteMid, SendHandle, ControlPid}, _From, S) ->
    Reply = handle_connect(RH, RemoteMid, SendHandle, ControlPid),
    {reply, Reply, S};
handle_call({connect_remote, CH, UserNode, Ref}, _From, S) ->
    Reply = handle_connect_remote(CH, UserNode, Ref),
    {reply, Reply, S};

handle_call({disconnect, ConnHandle}, _From, S) ->
    Reply = handle_disconnect(ConnHandle),
    {reply, Reply, S};
handle_call({disconnect_remote, CH, UserNode}, _From, S) ->
    Reply = handle_disconnect_remote(CH, UserNode),
    {reply, Reply, S};

handle_call({start_user, UserMid, Config}, _From, S) ->
    Reply = handle_start_user(UserMid, Config),
    {reply, Reply, S};
handle_call({stop_user, UserMid}, _From, S) ->
    Reply = handle_stop_user(UserMid),
    {reply, Reply, S};
handle_call({update_conn_data, CH, Item, Val}, _From, S) ->
    case lookup_local_conn(CH) of
        [] ->
            {reply, {error, {no_such_connection, CH}}, S};
        [CD] ->
            Reply = handle_update_conn_data(CD, Item, Val),
            {reply, Reply, S}
    end;
handle_call({update_user_info, UserMid, Item, Val}, _From, S) ->
    case catch user_info(UserMid, mid) of
        {'EXIT', _} ->
            {reply, {error, {no_such_user, UserMid}}, S};
        _ ->
            Reply = do_update_user(UserMid, Item, Val),
            {reply, Reply, S}
    end;

handle_call(Request, From, S) ->
    error_msg("unknown request from ~p~n~p",[From, Request]),
    {reply, {error, {bad_request, Request}}, S}.

%%----------------------------------------------------------------------
%% Func: handle_cast/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------

handle_cast({trans_sender_exit, Reason, CH}, S) ->
    error_msg("transaction sender (~p) restarting: ~n~p", [CH, Reason]),
    case lookup_local_conn(CH) of
	[] ->
	    error_msg("connection data not found for ~p~n"
		      "when restarting transaction sender", [CH]);
	[CD] ->
	    CD2 = trans_sender_start(CD#conn_data{trans_sender = undefined}),
	    ets:insert(megaco_local_conn, CD2)
    end,
    {noreply, S};


handle_cast(Msg, S) ->
    error_msg("received unknown message~n~p~n~p", [Msg, S]),
    {noreply, S}.

%%----------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------

handle_info({'EXIT', Pid, Reason}, S) when Pid == S#state.parent_pid ->
    {stop, Reason, S};

handle_info(Info, S) ->
    error_msg("received unknown info~n~p", [Info]),
    {noreply, S}.

%%----------------------------------------------------------------------
%% Func: terminate/2
%% Purpose: Shutdown the server
%% Returns: any (ignored by gen_server)
%%----------------------------------------------------------------------

terminate(_Reason, _State) ->
    ok.

%%----------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%%----------------------------------------------------------------------

code_change(_Vsn, S, _Extra) ->
    {ok, S}.



%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

handle_start_user(default, _Config) ->
    {error, bad_user_mid};
handle_start_user(Mid, Config) ->
    case catch user_info(Mid, mid) of
        {'EXIT', _} ->
	    DefaultConfig = user_info(default, all),
            do_handle_start_user(Mid, DefaultConfig),
            do_handle_start_user(Mid, Config);
        _LocalMid ->
            {error, {user_already_exists, Mid}}
    end.

do_handle_start_user(UserMid, [{Item, Val} | Rest]) ->
    case do_update_user(UserMid, Item, Val) of
        ok ->
            do_handle_start_user(UserMid, Rest);
        {error, Reason} ->
            ets:match_delete(megaco_config, {{UserMid, '_'}, '_'}),
            {error, Reason}
    end;
do_handle_start_user(UserMid, []) ->
    do_update_user(UserMid, mid, UserMid),
    ok;
do_handle_start_user(UserMid, BadConfig) ->
    ets:match_delete(megaco_config, {{UserMid, '_'}, '_'}),
    {error, {bad_user_config, UserMid, BadConfig}}.

do_update_user(UserMid, Item, Val) ->
    case verify_val(Item, Val) of
        true  ->
            ets:insert(megaco_config, {{UserMid, Item}, Val}),
            ok;
        false ->
            {error, {bad_user_val, UserMid, Item, Val}}
    end.

verify_val(Item, Val) ->
    case Item of
        mid                    -> true;
        local_mid              -> true;
        remote_mid             -> true;
        min_trans_id           -> verify_strict_int(Val, 4294967295); % uint32
        max_trans_id           -> verify_int(Val, 4294967295);        % uint32
        request_timer          -> verify_timer(Val);
        long_request_timer     -> verify_timer(Val);

        auto_ack               -> verify_bool(Val);

	trans_ack              -> verify_bool(Val);
        trans_ack_maxcount     -> verify_int(Val);

	trans_req              -> verify_bool(Val);
        trans_req_maxcount     -> verify_int(Val);
        trans_req_maxsize      -> verify_int(Val);

        trans_timer            -> verify_timer(Val) and (Val >= 0);
	trans_sender when Val == undefined -> true;

        pending_timer                   -> verify_timer(Val);
        sent_pending_limit              -> verify_int(Val) and (Val > 0);
        recv_pending_limit              -> verify_int(Val) and (Val > 0);
        reply_timer                     -> verify_timer(Val);
        control_pid      when pid(Val)  -> true;
        monitor_ref                     -> true; % Internal usage only
        send_mod         when atom(Val) -> true;
        send_handle                     -> true;
        encoding_mod     when atom(Val) -> true;
        encoding_config  when list(Val) -> true;
        protocol_version                -> verify_strict_int(Val);
        auth_data                       -> true;
        user_mod         when atom(Val) -> true;
        user_args        when list(Val) -> true;
        reply_data                      -> true;
        threaded                        -> verify_bool(Val);
        _                               -> false
    end.

verify_bool(true)  -> true;
verify_bool(false) -> true;
verify_bool(_)     -> false.

verify_strict_int(Int) when integer(Int), Int >= 0 -> true;
verify_strict_int(_)                               -> false.

verify_strict_int(Int, infinity) ->
    verify_strict_int(Int);
verify_strict_int(Int, Max) ->
    verify_strict_int(Int) and verify_strict_int(Max) and (Int =< Max).

verify_int(infinity) -> true;
verify_int(Val)      -> verify_strict_int(Val).

verify_int(Int, infinity) ->
    verify_int(Int);
verify_int(infinity, _Max) ->
    true;
verify_int(Int, Max) ->
    verify_strict_int(Int) and verify_strict_int(Max) and (Int =< Max).

verify_timer(Timer) when record(Timer, megaco_incr_timer) ->
    (verify_strict_int(Timer#megaco_incr_timer.wait_for) and
     verify_strict_int(Timer#megaco_incr_timer.factor)   and
     verify_strict_int(Timer#megaco_incr_timer.incr)     and
     verify_max_retries(Timer#megaco_incr_timer.max_retries));
verify_timer(Timer) ->
    verify_int(Timer).

verify_max_retries(infinity_restartable) ->
    true;
verify_max_retries(Int) ->
    verify_int(Int).

handle_stop_user(UserMid) ->
    case catch user_info(UserMid, mid) of
        {'EXIT', _} ->
	    {error, {no_such_user, UserMid}};
	_ ->
	    case catch user_info(UserMid, connections) of
		[] ->
		    ets:match_delete(megaco_config, {{UserMid, '_'}, '_'}),
		    ok;
		{'EXIT', _} ->
		    {error, {no_such_user, UserMid}};
		_Else ->
		    {error, {active_connections, UserMid}}
	    end
    end.

handle_update_conn_data(CD, Item = receive_handle, RH) ->
    UserMid = (CD#conn_data.conn_handle)#megaco_conn_handle.local_mid,
    if
        record(RH, megaco_receive_handle),
        atom(RH#megaco_receive_handle.encoding_mod),
        list(RH#megaco_receive_handle.encoding_config),
        atom(RH#megaco_receive_handle.send_mod),
        RH#megaco_receive_handle.local_mid /= UserMid ->
            CD2 = CD#conn_data{encoding_mod    = RH#megaco_receive_handle.encoding_mod,
                               encoding_config = RH#megaco_receive_handle.encoding_config,
                               send_mod        = RH#megaco_receive_handle.send_mod},
            ets:insert(megaco_local_conn, CD2),
            ok;
        true ->
            {error, {bad_user_val, UserMid, Item, RH}}
    end;
handle_update_conn_data(CD, Item, Val) ->
    case verify_val(Item, Val) of
        true ->
            CD2 = replace_conn_data(CD, Item, Val),
            ets:insert(megaco_local_conn, CD2),
            ok;
        false ->
            UserMid = (CD#conn_data.conn_handle)#megaco_conn_handle.local_mid,
            {error, {bad_user_val, UserMid, Item, Val}}
    end.

replace_conn_data(CD, Item, Val) ->
    case Item of
        trans_id           -> CD#conn_data{serial             = Val};
        max_trans_id       -> CD#conn_data{max_serial         = Val};
        request_timer      -> CD#conn_data{request_timer      = Val};
        long_request_timer -> CD#conn_data{long_request_timer = Val};

	auto_ack           -> update_auto_ack(CD, Val);

	%% Accumulate trans ack before sending
	trans_ack          -> update_trans_ack(CD, Val); 
	trans_ack_maxcount -> update_trans_ack_maxcount(CD, Val);

	%% Accumulate trans req before sending
	trans_req          -> update_trans_req(CD, Val); 
	trans_req_maxcount -> update_trans_req_maxcount(CD, Val);
	trans_req_maxsize  -> update_trans_req_maxsize(CD, Val);

	trans_timer        -> update_trans_timer(CD, Val); 
	%% trans_sender      - Automagically updated by 
	%%                     update_auto_ack & update_trans_timer & 
	%%                     update_trans_ack & update_trans_req

        pending_timer      -> CD#conn_data{pending_timer      = Val};
        sent_pending_limit -> CD#conn_data{sent_pending_limit = Val};
        recv_pending_limit -> CD#conn_data{recv_pending_limit = Val};
        reply_timer        -> CD#conn_data{reply_timer        = Val};
        control_pid        -> CD#conn_data{control_pid        = Val};
        monitor_ref        -> CD#conn_data{monitor_ref        = Val};
        send_mod           -> CD#conn_data{send_mod           = Val};
        send_handle        -> CD#conn_data{send_handle        = Val};
        encoding_mod       -> CD#conn_data{encoding_mod       = Val};
        encoding_config    -> CD#conn_data{encoding_config    = Val};
        protocol_version   -> CD#conn_data{protocol_version   = Val};
        auth_data          -> CD#conn_data{auth_data          = Val};
        user_mod           -> CD#conn_data{user_mod           = Val};
        user_args          -> CD#conn_data{user_args          = Val};
        reply_action       -> CD#conn_data{reply_action       = Val};
        reply_data         -> CD#conn_data{reply_data         = Val};
        threaded           -> CD#conn_data{threaded           = Val}
    end.

%% update auto_ack
update_auto_ack(#conn_data{trans_sender = Pid,
			   trans_req    = false} = CD, 
		false) when pid(Pid) ->
    megaco_trans_sender:stop(Pid),
    CD#conn_data{auto_ack = false, trans_sender = undefined};

update_auto_ack(#conn_data{trans_timer  = To, 
			   trans_ack    = true,
			   trans_sender = undefined} = CD, 
		true) when To > 0 ->
    #conn_data{conn_handle        = CH, 
	       trans_ack_maxcount = AcksMax, 
	       trans_req_maxcount = ReqsMax, 
	       trans_req_maxsize  = ReqsMaxSz} = CD,
    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{auto_ack = true, trans_sender = Pid};

update_auto_ack(CD, Val) ->
    ?d("update_auto_ack -> entry with ~p", [Val]),
    CD#conn_data{auto_ack = Val}.

%% update trans_ack
update_trans_ack(#conn_data{auto_ack     = true,
			    trans_req    = false,
			    trans_sender = Pid} = CD, 
		      false) when pid(Pid) ->
    megaco_trans_sender:stop(Pid),
    CD#conn_data{trans_ack = false, trans_sender = undefined};

update_trans_ack(#conn_data{trans_timer  = To,
			    auto_ack     = true, 
			    trans_sender = undefined} = CD, 
		      true) when To > 0 ->
    #conn_data{conn_handle        = CH, 
	       trans_ack_maxcount = AcksMax, 
	       trans_req_maxcount = ReqsMax, 
	       trans_req_maxsize  = ReqsMaxSz} = CD,
    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{trans_ack = true, trans_sender = Pid};

update_trans_ack(CD, Val) ->
    ?d("update_trans_ack -> entry with ~p", [Val]),
    CD#conn_data{trans_ack = Val}.

%% update trans_req
update_trans_req(#conn_data{trans_ack    = false,
			    trans_sender = Pid} = CD, 
		      false) when pid(Pid) ->
    megaco_trans_sender:stop(Pid),
    CD#conn_data{trans_req = false, trans_sender = undefined};

update_trans_req(#conn_data{trans_timer  = To, 
			    trans_sender = undefined} = CD, 
		      true) when To > 0 ->
    #conn_data{conn_handle        = CH, 
	       trans_ack_maxcount = AcksMax, 
	       trans_req_maxcount = ReqsMax, 
	       trans_req_maxsize  = ReqsMaxSz} = CD,
    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{trans_req = true, trans_sender = Pid};

update_trans_req(CD, Val) ->
    ?d("update_trans_req -> entry with ~p", [Val]),
    CD#conn_data{trans_req = Val}.

%% update trans_timer
update_trans_timer(#conn_data{auto_ack     = true, 
			      trans_ack    = true,
			      trans_sender = undefined} = CD, 
		   To) when To > 0 ->
    #conn_data{conn_handle        = CH, 
	       trans_ack_maxcount = AcksMax, 
	       trans_req_maxcount = ReqsMax, 
	       trans_req_maxsize  = ReqsMaxSz} = CD,
    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{trans_timer = To, trans_sender = Pid};

update_trans_timer(#conn_data{trans_req    = true, 
			      trans_sender = undefined} = CD, 
		   To) when To > 0 ->
    #conn_data{conn_handle        = CH, 
	       trans_ack_maxcount = AcksMax, 
	       trans_req_maxcount = ReqsMax, 
	       trans_req_maxsize  = ReqsMaxSz} = CD,
    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{trans_timer = To, trans_sender = Pid};

update_trans_timer(#conn_data{trans_sender = Pid} = CD, 0) when pid(Pid) ->
    megaco_trans_sender:stop(Pid),
    CD#conn_data{trans_timer = 0, trans_sender = undefined};

update_trans_timer(#conn_data{trans_sender = Pid} = CD, To) 
  when pid(Pid), To > 0 ->
    megaco_trans_sender:timeout(Pid, To),
    CD#conn_data{trans_timer = To};

update_trans_timer(CD, To) when To > 0 ->
    CD#conn_data{trans_timer = To}.

%% update trans_ack_maxcount
update_trans_ack_maxcount(#conn_data{trans_sender = Pid} = CD, Max) 
  when pid(Pid), Max > 0 ->
    megaco_trans_sender:ack_maxcount(Pid, Max),
    CD#conn_data{trans_ack_maxcount = Max};

update_trans_ack_maxcount(CD, Max) 
  when Max > 0 ->
    ?d("update_trans_ack_maxcount -> entry with ~p", [Max]),
    CD#conn_data{trans_ack_maxcount = Max}.

%% update trans_req_maxcount
update_trans_req_maxcount(#conn_data{trans_sender = Pid} = CD, Max) 
  when pid(Pid), Max > 0 ->
    megaco_trans_sender:req_maxcount(Pid, Max),
    CD#conn_data{trans_req_maxcount = Max};

update_trans_req_maxcount(CD, Max) 
  when Max > 0 ->
    ?d("update_trans_req_maxcount -> entry with ~p", [Max]),
    CD#conn_data{trans_req_maxcount = Max}.

%% update trans_req_maxsize
update_trans_req_maxsize(#conn_data{trans_sender = Pid} = CD, Max) 
  when pid(Pid), Max > 0 ->
    megaco_trans_sender:req_maxsize(Pid, Max),
    CD#conn_data{trans_req_maxsize = Max};

update_trans_req_maxsize(CD, Max) 
  when Max > 0 ->
    ?d("update_trans_req_maxsize -> entry with ~p", [Max]),
    CD#conn_data{trans_req_maxsize = Max}.

    

handle_connect(RH, RemoteMid, SendHandle, ControlPid) ->
    LocalMid   = RH#megaco_receive_handle.local_mid,
    ConnHandle = #megaco_conn_handle{local_mid  = LocalMid,
				     remote_mid = RemoteMid},
    ?d("handle_connect -> entry with"
	"~n   ConnHandle: ~p", [ConnHandle]),
    case ets:lookup(megaco_local_conn, ConnHandle) of
        [] ->
	    PrelMid = preliminary_mid,
	    PrelHandle = ConnHandle#megaco_conn_handle{remote_mid = PrelMid},
	    case ets:lookup(megaco_local_conn, PrelHandle) of
		[] ->
		    case catch init_conn_data(RH, RemoteMid, SendHandle, ControlPid) of
			{'EXIT', _Reason} ->
			    ?d("handle_connect -> init conn data failed: "
				"~n   ~p",[_Reason]),
			    {error, {no_such_user, LocalMid}};
			ConnData ->
			    ?d("handle_connect -> new connection"
				"~n   ConnData: ~p", [ConnData]),
			    %% Brand new connection, use 
			    %% When is the preliminary_mid used?
			    create_snmp_counters(ConnHandle),
			    %% Maybe start transaction sender
			    ConnData2 = trans_sender_start(ConnData),
			    ets:insert(megaco_local_conn, ConnData2),
			    {ok, ConnData2}
		    end;
		[PrelData] ->
		    ?d("handle_connect -> connection upgrade"
			"~n   PrelData: ~p", [PrelData]),
		    %% OK, we need to fix the snmp counters. Used 
		    %% with the temporary (preliminary_mid) conn_handle.
		    create_snmp_counters(ConnHandle),
		    ConnData = PrelData#conn_data{conn_handle = ConnHandle},
		    trans_sender_upgrade(ConnData),
		    ets:insert(megaco_local_conn, ConnData),
		    ets:delete(megaco_local_conn, PrelHandle),
		    update_snmp_counters(ConnHandle, PrelHandle),
		    TH = ConnHandle#megaco_conn_handle{local_mid  = PrelMid,
						       remote_mid = RemoteMid},
		    TD = ConnData#conn_data{conn_handle = TH},
 		    ?report_debug(TD, 
				  "Upgrade preliminary_mid to "
				  "actual remote_mid",
				  [{preliminary_mid, preliminary_mid},
				   {local_mid,       LocalMid},
				   {remote_mid,      RemoteMid}]),
		    {ok, ConnData}
	    end;
        [_ConnData] ->
            {error, {already_connected, ConnHandle}}
    end.


%% also trans_req == true
trans_sender_start(#conn_data{conn_handle        = CH,
			      auto_ack           = true, 
			      trans_ack          = true, 
			      trans_ack_maxcount = AcksMax, 
			      trans_req_maxcount = ReqsMax, 
			      trans_req_maxsize  = ReqsMaxSz,
			      trans_timer        = To,
			      trans_sender       = undefined} = CD)
  when To > 0 ->

    ?d("trans_sender_start(ack) -> entry when"
	"~n   CH:        ~p"
	"~n   To:        ~p"
	"~n   AcksMax:   ~p"
	"~n   ReqsMax:   ~p"
	"~n   ReqsMaxSz: ~p", [CH, To, ReqsMaxSz, ReqsMax, AcksMax]),

    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    ?d("trans_sender_start(ack) -> Pid: ~p", [Pid]),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{trans_sender = Pid};

trans_sender_start(#conn_data{conn_handle        = CH,
			      trans_req          = true, 
			      trans_ack_maxcount = AcksMax, 
			      trans_req_maxcount = ReqsMax, 
			      trans_req_maxsize  = ReqsMaxSz,
			      trans_timer        = To,
			      trans_sender       = undefined} = CD)
  when To > 0 ->

    ?d("trans_sender_start(req) -> entry when"
	"~n   CH:        ~p"
	"~n   To:        ~p"
	"~n   AcksMax:   ~p"
	"~n   ReqsMax:   ~p"
	"~n   ReqsMaxSz: ~p", [CH, To, ReqsMaxSz, ReqsMax, AcksMax]),

    {ok, Pid} = megaco_trans_sup:start_trans_sender(CH, To, ReqsMaxSz, 
						    ReqsMax, AcksMax),

    ?d("trans_sender_start(req) -> Pid: ~p", [Pid]),

    %% Make sure we are notified when/if the transaction 
    %% sender goes down. 
    %% Do we need to store the ref? Will we ever need to 
    %% cancel this (apply_at_exit)?
    megaco_monitor:apply_at_exit(?MODULE, trans_sender_exit, [CH], Pid),

    CD#conn_data{trans_sender = Pid};

trans_sender_start(CD) ->
    ?d("trans_sender_start -> undefined", []),
    CD#conn_data{trans_sender = undefined}.

trans_sender_upgrade(#conn_data{conn_handle  = CH,
				trans_sender = Pid})
  when pid(Pid) ->
    ?d("trans_sende_upgrade -> entry when"
	"~n   CH:  ~p"
	"~n   Pid: ~p", [CH, Pid]),
    megaco_trans_sender:upgrade(Pid, CH);
trans_sender_upgrade(_CD) ->
    ok.


handle_connect_remote(ConnHandle, UserNode, Ref) ->
    Pat = #remote_conn_data{conn_handle = ConnHandle,
			    user_node   = UserNode,
			    monitor_ref = '_'},
    case ets:match_object(megaco_remote_conn, Pat) of
        [] ->
	    RCD = #remote_conn_data{conn_handle = ConnHandle,
				    user_node   = UserNode,
				    monitor_ref = Ref},
            ets:insert(megaco_remote_conn, RCD),
            ok;
        _ ->
            {error, {already_connected, ConnHandle, UserNode}}
    end.

init_conn_data(RH, RemoteMid, SendHandle, ControlPid) ->
    Mid            = RH#megaco_receive_handle.local_mid,
    ConnHandle     = #megaco_conn_handle{local_mid  = Mid,
					 remote_mid = RemoteMid},
    EncodingMod    = RH#megaco_receive_handle.encoding_mod,
    EncodingConfig = RH#megaco_receive_handle.encoding_config,
    SendMod        = RH#megaco_receive_handle.send_mod,
    #conn_data{conn_handle        = ConnHandle,
               serial             = undefined_serial,
               max_serial         = user_info(Mid, max_trans_id),
               request_timer      = user_info(Mid, request_timer),
               long_request_timer = user_info(Mid, long_request_timer),

               auto_ack           = user_info(Mid, auto_ack),
               trans_ack          = user_info(Mid, trans_req),
               trans_req          = user_info(Mid, trans_req),

	       trans_timer        = user_info(Mid, trans_timer),
	       trans_req_maxsize  = user_info(Mid, trans_req_maxsize),
	       trans_req_maxcount = user_info(Mid, trans_req_maxcount),
	       trans_ack_maxcount = user_info(Mid, trans_ack_maxcount),

               pending_timer      = user_info(Mid, pending_timer),
               sent_pending_limit = user_info(Mid, sent_pending_limit),
               recv_pending_limit = user_info(Mid, recv_pending_limit),
               reply_timer        = user_info(Mid, reply_timer),
               control_pid        = ControlPid,
               monitor_ref        = undefined_monitor_ref,
               send_mod           = SendMod,
               send_handle        = SendHandle,
               encoding_mod       = EncodingMod,
               encoding_config    = EncodingConfig,
               protocol_version   = user_info(Mid, protocol_version),
               auth_data          = user_info(Mid, auth_data),
               user_mod           = user_info(Mid, user_mod),
               user_args          = user_info(Mid, user_args),
               reply_action       = undefined,
               reply_data         = user_info(Mid, reply_data),
	       threaded           = user_info(Mid, threaded)}.

handle_disconnect(ConnHandle) when record(ConnHandle, megaco_conn_handle) ->
    case ets:lookup(megaco_local_conn, ConnHandle) of
        [ConnData] ->
	    ets:delete(megaco_local_conn, ConnHandle),
	    RemoteConnData = handle_disconnect_remote(ConnHandle, '_'),
            {ok, ConnData, RemoteConnData};
        [] ->
            {error, {already_disconnected, ConnHandle}}
    end.

handle_disconnect_remote(ConnHandle, UserNode) ->
    Pat = #remote_conn_data{conn_handle = ConnHandle,
			    user_node   = UserNode,
			    monitor_ref = '_'},
    RemoteConnData = ets:match_object(megaco_remote_conn, Pat),
    ets:match_delete(megaco_remote_conn, Pat),
    RemoteConnData.

make_receive_handle(UserMid) ->
    #megaco_receive_handle{local_mid       = UserMid,
			   encoding_mod    = user_info(UserMid, encoding_mod),
			   encoding_config = user_info(UserMid, encoding_config),
			   send_mod        = user_info(UserMid, send_mod)}.


%%-----------------------------------------------------------------
%% Func: create_snmp_counters/1, update_snmp_counters/2
%% Description: create/update all the SNMP statistic counters
%%-----------------------------------------------------------------

create_snmp_counters(CH) ->
    create_snmp_counters(CH, snmp_counters()).

% create_snmp_counters(CH, []) ->
%     ok;
% create_snmp_counters(CH, [Counter|Counters]) ->
%     Key = {CH, Counter},
%     ets:insert(megaco_stats, {Key, 0}),
%     create_snmp_counters(CH, Counters).

create_snmp_counters(CH, Counters) ->
    F = fun(Counter) -> 
		Key = {CH, Counter},
		ets:insert(megaco_stats, {Key, 0}) 
	end,
    lists:foreach(F, Counters).


update_snmp_counters(CH, PrelCH) ->
    update_snmp_counters(CH, PrelCH, snmp_counters()).

update_snmp_counters(_CH, _PrelCH, []) ->
    ok;
update_snmp_counters(CH, PrelCH, [Counter|Counters]) ->
    PrelKey = {PrelCH, Counter},
    Key     = {CH, Counter},
    [{PrelKey,PrelVal}] = ets:lookup(megaco_stats, PrelKey),
    ets:update_counter(megaco_stats, Key, PrelVal),
    ets:delete(megaco_stats, PrelKey),
    update_snmp_counters(CH, PrelCH, Counters).


global_snmp_counters() ->
    [medGwyGatewayNumErrors].

snmp_counters() ->
    [medGwyGatewayNumTimerRecovery,
     medGwyGatewayNumErrors].



%%-----------------------------------------------------------------

error_msg(F, A) ->
    (catch error_logger:error_msg("[~p] " ++ F ++ "~n", [?MODULE|A])).

