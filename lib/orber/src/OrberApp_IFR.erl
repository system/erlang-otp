%%------------------------------------------------------------
%%
%% Implementation stub file
%% 
%% Target: OrberApp_IFR
%% Source: /ldisk/daily_build/otp_prebuild_r12b.2008-04-07_20/otp_src_R12B-1/lib/orber/src/OrberIFR.idl
%% IC vsn: 4.2.17
%% 
%% This file is automatically generated. DO NOT EDIT IT.
%%
%%------------------------------------------------------------

-module('OrberApp_IFR').
-ic_compiled("4_2_17").


%% Interface functions
-export([get_absolute_name/2, get_absolute_name/3, get_user_exception_type/2]).
-export([get_user_exception_type/3]).

%% Type identification function
-export([typeID/0]).

%% Used to start server
-export([oe_create/0, oe_create_link/0, oe_create/1]).
-export([oe_create_link/1, oe_create/2, oe_create_link/2]).

%% TypeCode Functions and inheritance
-export([oe_tc/1, oe_is_a/1, oe_get_interface/0]).

%% gen server export stuff
-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3]).
-export([handle_cast/2, handle_info/2, code_change/3]).

-include_lib("orber/include/corba.hrl").


%%------------------------------------------------------------
%%
%% Object interface functions.
%%
%%------------------------------------------------------------



%%%% Operation: get_absolute_name
%% 
%%   Returns: RetVal
%%
get_absolute_name(OE_THIS, TypeID) ->
    corba:call(OE_THIS, get_absolute_name, [TypeID], ?MODULE).

get_absolute_name(OE_THIS, OE_Options, TypeID) ->
    corba:call(OE_THIS, get_absolute_name, [TypeID], ?MODULE, OE_Options).

%%%% Operation: get_user_exception_type
%% 
%%   Returns: RetVal
%%
get_user_exception_type(OE_THIS, TypeID) ->
    corba:call(OE_THIS, get_user_exception_type, [TypeID], ?MODULE).

get_user_exception_type(OE_THIS, OE_Options, TypeID) ->
    corba:call(OE_THIS, get_user_exception_type, [TypeID], ?MODULE, OE_Options).

%%------------------------------------------------------------
%%
%% Inherited Interfaces
%%
%%------------------------------------------------------------
oe_is_a("IDL:OrberApp/IFR:1.0") -> true;
oe_is_a(_) -> false.

%%------------------------------------------------------------
%%
%% Interface TypeCode
%%
%%------------------------------------------------------------
oe_tc(get_absolute_name) -> 
	{{tk_string,0},[{tk_string,0}],[]};
oe_tc(get_user_exception_type) -> 
	{tk_TypeCode,[{tk_string,0}],[]};
oe_tc(_) -> undefined.

oe_get_interface() -> 
	[{"get_user_exception_type", oe_tc(get_user_exception_type)},
	{"get_absolute_name", oe_tc(get_absolute_name)}].




%%------------------------------------------------------------
%%
%% Object server implementation.
%%
%%------------------------------------------------------------


%%------------------------------------------------------------
%%
%% Function for fetching the interface type ID.
%%
%%------------------------------------------------------------

typeID() ->
    "IDL:OrberApp/IFR:1.0".


%%------------------------------------------------------------
%%
%% Object creation functions.
%%
%%------------------------------------------------------------

oe_create() ->
    corba:create(?MODULE, "IDL:OrberApp/IFR:1.0").

oe_create_link() ->
    corba:create_link(?MODULE, "IDL:OrberApp/IFR:1.0").

oe_create(Env) ->
    corba:create(?MODULE, "IDL:OrberApp/IFR:1.0", Env).

oe_create_link(Env) ->
    corba:create_link(?MODULE, "IDL:OrberApp/IFR:1.0", Env).

oe_create(Env, RegName) ->
    corba:create(?MODULE, "IDL:OrberApp/IFR:1.0", Env, RegName).

oe_create_link(Env, RegName) ->
    corba:create_link(?MODULE, "IDL:OrberApp/IFR:1.0", Env, RegName).

%%------------------------------------------------------------
%%
%% Init & terminate functions.
%%
%%------------------------------------------------------------

init(Env) ->
%% Call to implementation init
    corba:handle_init('OrberApp_IFR_impl', Env).

terminate(Reason, State) ->
    corba:handle_terminate('OrberApp_IFR_impl', Reason, State).


%%%% Operation: get_absolute_name
%% 
%%   Returns: RetVal
%%
handle_call({_, OE_Context, get_absolute_name, [TypeID]}, _, OE_State) ->
  corba:handle_call('OrberApp_IFR_impl', get_absolute_name, [TypeID], OE_State, OE_Context, false, false);

%%%% Operation: get_user_exception_type
%% 
%%   Returns: RetVal
%%
handle_call({_, OE_Context, get_user_exception_type, [TypeID]}, _, OE_State) ->
  corba:handle_call('OrberApp_IFR_impl', get_user_exception_type, [TypeID], OE_State, OE_Context, false, false);



%%%% Standard gen_server call handle
%%
handle_call(stop, _, State) ->
    {stop, normal, ok, State};

handle_call(_, _, State) ->
    {reply, catch corba:raise(#'BAD_OPERATION'{minor=1163001857, completion_status='COMPLETED_NO'}), State}.


%%%% Standard gen_server cast handle
%%
handle_cast(stop, State) ->
    {stop, normal, State};

handle_cast(_, State) ->
    {noreply, State}.


%%%% Standard gen_server handles
%%
handle_info(_, State) ->
    {noreply, State}.


code_change(OldVsn, State, Extra) ->
    corba:handle_code_change('OrberApp_IFR_impl', OldVsn, State, Extra).

