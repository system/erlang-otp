%%<copyright>
%% <year>2004-2007</year>
%% <holder>Ericsson AB, All Rights Reserved</holder>
%%</copyright>
%%<legalnotice>
%% ``The contents of this file are subject to the Erlang Public License,
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

%%% @doc Common Test specific layer on top of the OTPs snmp
%%%
%%% Application to make snmp configuration easier for the test case
%%% writer. Many test cases can use default values for everything and
%%% then no snmp-configuration files needs to be supplied at all. When
%%% it is necessary to change some configuration it can be done for
%%% the subset of snmp-configuration files that are relevant, and
%%% still all this can be put in to the common-test configuration file
%%% or for the more specialized configuration parameters a "simple
%%% snmp-configuration file" can be placed in the test suites data
%%% directory. ct_snmp will also perform a type check on all supplied
%%% configuration. In the manager case the common_test application
%%% also will keep track of some manager information so that the
%%% test case write does not have to keep track of as much input
%%% parameters as if using the OTPs snmp manager directly.
%%%   
%%% 
%%% <p> The following parameters are configurable </p>
%%%
%%% <pre>
%%% {snmp,
%%%        %%% Manager config
%%%        [{start_manager, boolean()}    % Optional - default is true
%%%        {users, [{user_name(), [call_back_module(), user_data()]}]}, %% Optional 
%%%        {usm_users, [{usm_user_name(), usm_config()}]},%% Optional - snmp v3 only
%%%        % managed_agents is optional 
%%%        {managed_agents,[{agent_name(), [user_name(), agent_ip(), agent_port(), [agent_config()]]}]},   
%%%        {max_msg_size, integer()},     % Optional - default is 484
%%%        {mgr_port, integer()},         % Optional - default is 5000
%%%        {engine _id, string()},        % Optional - default is "mgrEngine"
%%%
%%%        %%% Agent config 
%%%        {start_agent, boolean()},      % Optional - default is false
%%%        {agent_sysname, string()},     % Optional - default is "ct_test"
%%%        {agent_manager_ip, manager_ip()}, % Optional - default is localhost
%%%        {agent_vsns, list()},          % Optional - default is [v2]
%%%        {agent_trap_udp, integer()},   % Optional - default is 5000
%%%        {agent_udp, integer()},        % Optional - default is 4000
%%%        {agent_notify_type, atom()},   % Optional - default is trap
%%%        {agent_sec_type, sec_type()},  % Optional - default is none
%%%        {agent_passwd, string()},      % Optional - default is ""
%%%        {agent_engine_id, string()},   % Optional - default is "agentEngine"
%%%        {agent_max_msg_size, string()},% Optional - default is 484
%%%
%%%        %% The following parameters represents the snmp configuration files
%%%        %% context.conf, standard.conf, community.conf, vacm.conf,  
%%%        %% usm.conf, notify.conf, target_addr.conf and target_params.conf.
%%%        %% Note all values in agent.conf can be altered by the parametes 
%%%        %% above. All these configuration files have default values set   
%%%        %% up by the snmp application. These values can be overridden by
%%%        %% suppling a list of valid configuration values or a file located
%%%        %% in the test suites data dir that can produce a list 
%%%        %% of valid configuration values if you apply file:consult/1 to the 
%%%        %% file. 
%%%        {agent_contexts, [term()] | {data_dir_file, rel_path()}}, % Optional
%%%        {agent_community, [term()] | {data_dir_file, rel_path()}},% Optional
%%%        {agent_sysinfo,  [term()] | {data_dir_file, rel_path()}}, % Optional
%%%        {agent_vacm, [term()] | {data_dir_file, rel_path()}},     % Optional
%%%        {agent_usm, [term()] | {data_dir_file, rel_path()}},      % Optional 
%%%        {agent_notify_def, [term()] | {data_dir_file, rel_path()}},% Optional
%%%        {agent_target_address_def, [term()] | {data_dir_file, rel_path()}},% Optional
%%%        {agent_target_param_def, [term()] | {data_dir_file, rel_path()}},% Optional
%%%       ]}.
%%% </pre>
%%%
%%% <p>The <code>ConfName</code> parameter in the functions 
%%%    should be the name you allocated in your test suite using
%%%  <code>require</code> statement. Example:</p>
%%% <pre> suite() -> [{require, ConfName,{snmp,[users, managed_agents]}}].</pre>
%%% <p>or</p>
%%% <pre>  ct:require(ConfName,{snmp,[users, managed_agents]}).</pre>
%%%
%%% <p> Note that Usm users are needed for snmp v3 configuration and are
%%% not to be confused with users.</p>
%%%
%%% <p> Snmp traps, inform and report messages are handled by the
%%% user callback module. For more information about this see
%%% the snmp application. </p> 
%%% <p> Note: It is recommended to use the .hrl-files created by the 
%%% Erlang/OTP mib-compiler to define the oids.  
%%% Ex for the getting the erlang node name from the erlNodeTable 
%%% in the OTP-MIB </p> 
%%% <pre>Oid = ?erlNodeEntry ++ [?erlNodeName, 1] </pre>

-module(ct_snmp).

%%% Common Types
%%% @type agent_ip() = ip()
%%% @type manager_ip() = ip()
%%% @type agent_name() = atom()
%%% @type ip() = string() | {integer(), integer(), 
%%% integer(), integer()}
%%% @type agent_port() = integer()
%%% @type agent_config() = {Item, Value} 
%%% @type user_name() = atom() 
%%% @type usm_user_name() = string() 
%%% @type usm_config() = string()  
%%% @type call_back_module() = atom()
%%% @type user_data() = term() 
%%% @type oids() = [oid()]
%%% @type oid() = [byte()]
%%% @type snmpreply() = {error_status(), error_index(), varbinds()} 
%%% @type error_status() = noError | atom() 
%%% @type error_index() = integer() 
%%% @type varbinds() = [varbind()] 
%%% @type varbind() =  term() 
%%% @type value_type() = o ('OBJECT IDENTIFIER') | i ('INTEGER') | 
%%% u ('Unsigned32') | g ('Unsigned32') | s ('OCTET STRING') 
%%% @type varsandvals() = [var_and_val()]
%%% @type var_and_val() = {oid(), value_type(), value()}
%%% @type sec_type() = none | minimum | semi
%%% @type rel_path() = string() 


-include("snmp_types.hrl").
-include("inet.hrl").
-include("ct.hrl").

%%% API
-export([start/2, stop/1, get_values/3, get_next_values/3, set_values/4, 
	 set_info/1, register_users/2, register_agents/2, register_usm_users/2,
	 unregister_users/1, unregister_agents/1, update_usm_users/2, 
	 load_mibs/1]).

%% Manager values
-define(CT_SNMP_LOG_FILE, "ct_snmp_set.log").
-define(MGR_PORT, 5000).
-define(MAX_MSG_SIZE, 484).
-define(ENGINE_ID, "mgrEngine").

%% Agent values
-define(AGENT_ENGINE_ID, "agentEngine").
-define(TRAP_UDP, 5000). 
-define(AGENT_UDP, 4000).
-define(CONF_FILE_VER, [v2]).
-define(AGENT_MAX_MSG_SIZE, 484).
-define(AGENT_NOTIFY_TYPE, trap).
-define(AGENT_SEC_TYPE, none).
-define(AGENT_PASSWD, "").
%%%=========================================================================
%%%  API
%%%=========================================================================

%%% @spec start(Config, ConfName) -> ok
%%%      Config = [{Key, Value}] 
%%%      Key = atom()
%%%      Value = term()
%%%      ConfName = atom()
%%%
%%% @doc Starts an snmp manager and/or agent. In the manager case also
%%% registrations of users and agents as specified by the
%%% configuration &lt;ConfName&gt; will be performed. When using snmp
%%% v3 also so called usm users will be registered. Note that users,
%%% usm_users and managed agents may also be registerd at a later time
%%% using ct_snmp:register_users/2, ct_snmp:register_agents/2, and
%%% ct_snmp:register_usm_users/2. The agent started will be
%%% called snmp_master_agent. Use ct_snmp:load_mibs to load mibs into the
%%% agent.
start(Config, ConfName) ->
    
    StartManager= ct:get_config({ConfName, start_manager}, true),
    StartAgent = ct:get_config({ConfName, start_agent}, false),
   
    SysName = ct:get_config({ConfName, agent_sysname}, "ct_test"),
    {ok, HostName} = inet:gethostname(),
    {ok, Addr} = inet:getaddr(HostName, inet),
    IP = tuple_to_list(Addr),
    AgentManagerIP = ct:get_config({ConfName, agent_manager_ip},
				   IP),
    
    prepare_snmp_env(),
    setup_agent(StartAgent, ConfName, Config, SysName, AgentManagerIP, IP),
    setup_manager(StartManager, ConfName, Config, IP),
    application:start(snmp),

    manager_register(StartManager, ConfName).
 
%%% @spec stop(Config) -> ok
%%%      Config = [{Key, Value}]
%%%      Key = atom()
%%%      Value = term()
%%%      ConfName = atom()
%%%
%%% @doc Stops the snmp manager and/or agent removes all files created.
stop(Config) ->
    PrivDir = ?config(priv_dir, Config),
    application:stop(snmp),
    application:stop(mnesia),
    MgrDir =  filename:join(PrivDir,"mgr"),
    ConfDir = filename:join(PrivDir, "conf"),
    DbDir = filename:join(PrivDir,"db"),
    catch del_dir(MgrDir),
    catch del_dir(ConfDir),
    catch del_dir(DbDir).
    
    
%%% @spec get_values(Agent, Oids, ConfName) -> SnmpReply
%%%
%%%	 Agent = agent_name()
%%%      Oids = oids()
%%%      ConfName = atom()
%%%      SnmpReply = snmpreply()  
%%%
%%% @doc Issues a synchronous snmp get request. 
get_values(Agent, Oids, ConfName) ->
    [Uid, AgentIp, AgentUdpPort | _] = 
	agent_conf(Agent, ConfName),
    {ok, SnmpReply, _} =
	snmpm:g(Uid, AgentIp, AgentUdpPort, Oids),
    SnmpReply.

%%% @spec get_next_values(Agent, Oids, ConfName) -> SnmpReply 
%%%
%%%	 Agent = agent_name()
%%%      Oids = oids()
%%%      ConfName = atom()
%%%      SnmpReply = snmpreply()  
%%%
%%% @doc Issues a synchronous snmp get next request. 
get_next_values(Agent, Oids, ConfName) ->
    [Uid, AgentIp, AgentUdpPort | _] = 
	agent_conf(Agent, ConfName),
    {ok, SnmpReply, _} =
	snmpm:gn(Uid, AgentIp, AgentUdpPort, Oids),
    SnmpReply.

%%% @spec set_values(Agent, VarsAndVals, ConfName, Config) -> SnmpReply
%%%
%%%	 Agent = agent_name()
%%%      Oids = oids()
%%%      ConfName = atom()
%%%      Config = [{Key, Value}] 
%%%      SnmpReply = snmpreply()  
%%%
%%% @doc Issues a synchronous snmp set request. 
set_values(Agent, VarsAndVals, ConfName, Config) ->
    PrivDir = ?config(priv_dir, Config),
    [Uid, AgentIp, AgentUdpPort | _] = 
	agent_conf(Agent, ConfName),
    Oids = lists:map(fun({Oid, _, _}) -> Oid end, VarsAndVals),
    {ok, SnmpGetReply, _} =
	snmpm:g(Uid, AgentIp, AgentUdpPort, Oids),
    {ok, SnmpSetReply, _} =
	snmpm:s(Uid, AgentIp, AgentUdpPort, VarsAndVals),
    case SnmpSetReply of
	{noError, 0, _} when PrivDir /= false ->
	    log(PrivDir, Agent, SnmpGetReply, VarsAndVals);
	_ ->
	    set_failed_or_user_did_not_want_to_log
    end,
    SnmpSetReply.

%%% @spec set_info(Config) -> [{Agent, OldVarsAndVals, NewVarsAndVals}] 
%%%
%%%      Config = [{Key, Value}] 
%%%	 Agent = agent_name()
%%%      OldVarsAndVals = varsandvals()
%%%      NewVarsAndVals = varsandvals()
%%%
%%% @doc Returns a list of all successful set requests performed in
%%% the test case in reverse order. The list contains the involved
%%% user and agent, the value prior to the set and the new value. This
%%% is intended to facilitate the clean up in the end_per_testcase
%%% function i.e. the undoing of the set requests and its possible
%%% side-effects.
set_info(Config) ->
    PrivDir = ?config(priv_dir, Config),
    SetLogFile = filename:join(PrivDir, ?CT_SNMP_LOG_FILE),
    case file:consult(SetLogFile) of
	{ok, SetInfo} ->
	    file:delete(SetLogFile),
	    lists:reverse(SetInfo);
	_ ->
	    []
    end.

%%% @spec register_users(ConfName, Users) -> ok | {error, Reason}
%%%
%%%      ConfName = atom()
%%%      Users =  [user()]
%%%      Reason = term()    
%%%
%%% @doc Register the manager entity (=user) responsible for specific agent(s).
%%% Corresponds to making an entry in users.conf
register_users(ConfName, Users) ->
    {snmp, SnmpVals} = ct:get_config(ConfName),
    NewSnmpVals = lists:keyreplace(users, 1, SnmpVals, {users, Users}),
    ct_util:update_config(ConfName, {snmp, NewSnmpVals}),
    setup_users(Users).

%%% @spec register_agents(ConfName, ManagedAgents) -> ok | {error, Reason}
%%%
%%%      ConfName = atom()
%%%      ManagedAgents = [agent()]
%%%      Reason = term()    
%%%
%%% @doc Explicitly instruct the manager to handle this agent.
%%% Corresponds to making an entry in agents.conf 
register_agents(ConfName, ManagedAgents) ->
    {snmp, SnmpVals} = ct:get_config(ConfName),
    NewSnmpVals = lists:keyreplace(managed_agents, 1, SnmpVals,
				   {managed_agents, ManagedAgents}),
    ct_util:update_config(ConfName, {snmp, NewSnmpVals}),
    setup_managed_agents(ManagedAgents).

%%% @spec register_usm_users(ConfName, UsmUsers) ->  ok | {error, Reason}
%%%
%%%      ConfName = atom()
%%%      UsmUsers = [usm_user()]
%%%      Reason = term()    
%%%
%%% @doc Explicitly instruct the manager to handle this USM user.
%%% Corresponds to making an entry in usm.conf 
register_usm_users(ConfName, UsmUsers) ->
    {snmp, SnmpVals} = ct:get_config(ConfName),
    NewSnmpVals = lists:keyreplace(users, 1, SnmpVals, {usm_users, UsmUsers}),
    ct_util:update_config(ConfName, {snmp, NewSnmpVals}),
    EngineID = ct:get_config({ConfName, engine_id}, ?ENGINE_ID),
    setup_usm_users(UsmUsers, EngineID).

%%% @spec unregister_users(ConfName) ->  ok | {error, Reason}
%%%
%%%      ConfName = atom()
%%%      Reason = term()
%%%
%%% @doc Removes information added when calling register_users/2. 
unregister_users(ConfName) ->
    Users = lists:map(fun({UserName, _}) -> UserName end,
		      ct:get_config({ConfName, users})),
    {snmp, SnmpVals} = ct:get_config(ConfName),
    NewSnmpVals = lists:keyreplace(users, 1, SnmpVals, {users, []}),
    ct_util:update_config(ConfName, {snmp, NewSnmpVals}),
    takedown_users(Users).

%%% @spec unregister_agents(ConfName) ->  ok | {error, Reason}
%%%
%%%      ConfName = atom()
%%%      Reason = term()
%%%
%%% @doc  Removes information added when calling register_agents/2. 
unregister_agents(ConfName) ->    
    ManagedAgents = lists:map(fun({_, [Uid, AgentIP, AgentPort, _]}) -> 
				      {Uid, AgentIP, AgentPort} 
			      end,
			      ct:get_config({ConfName, managed_agents})),
    {snmp, SnmpVals} = ct:get_config(ConfName),
    NewSnmpVals = lists:keyreplace(managed_agents, 1, SnmpVals, 
				   {managed_agents, []}),
    ct_util:update_config(ConfName, {snmp, NewSnmpVals}),
    takedown_managed_agents(ManagedAgents).


%%% @spec update_usm_users(ConfName, UsmUsers) -> ok | {error, Reason}
%%%
%%%      ConfName = atom()
%%%      UsmUsers = usm_users()
%%%      Reason = term()
%%%
%%% @doc  Alters information added when calling register_usm_users/2. 
update_usm_users(ConfName, UsmUsers) ->    
   
    {snmp, SnmpVals} = ct:get_config(ConfName),
    NewSnmpVals = lists:keyreplace(usm_users, 1, SnmpVals, 
				   {usm_users, UsmUsers}),
    ct_util:update_config(ConfName, {snmp, NewSnmpVals}),
    EngineID = ct:get_config({ConfName, engine_id}, ?ENGINE_ID),
    do_update_usm_users(UsmUsers, EngineID). 

%%% @spec load_mibs(Mibs) -> ok | {error, Reason}
%%%
%%%      Mibs = [MibName]
%%%      MibName = string()
%%%      Reason = term()
%%%
%%% @doc Load the mibs into the agent 'snmp_master_agent'.
load_mibs(Mibs) ->       
    snmpa:load_mibs(snmp_master_agent, Mibs).
 

%%%========================================================================
%%% Internal functions
%%%========================================================================
prepare_snmp_env() ->
    %% To make sure application:set_env is not overwritten by any
    %% app-file settings.
    application:load(snmp),
    
    %% Fix for older versions of snmp where there are some
    %% inappropriate default values for alway starting an 
    %% agent.
    application:unset_env(snmp, agent).
%%%---------------------------------------------------------------------------
setup_manager(false, _, _, _) ->
    ok;
setup_manager(true, ConfName, Config, IP) ->
    
    PrivDir = ?config(priv_dir, Config),
    MaxMsgSize = ct:get_config({ConfName, max_msg_size}, ?MAX_MSG_SIZE),
    Port = ct:get_config({ConfName, mgr_port}, ?MGR_PORT),
    EngineID = ct:get_config({ConfName, engine_id}, ?ENGINE_ID),
    MgrDir =  filename:join(PrivDir,"mgr"),
    %%% Users, Agents and Usms are in test suites register after the
    %%% snmp application is started.
    Users = [],
    Agents = [],
    Usms = [],
    file:make_dir(MgrDir),
   
    snmp_config:write_manager_snmp_files(MgrDir, IP, Port, MaxMsgSize, 
					 EngineID, Users, Agents, Usms),
    application:set_env(snmp, manager, [{config, [{dir, MgrDir},
						  {db_dir, MgrDir},
						  {verbosity, trace}]},
					{server, [{verbosity, trace}]},
					{net_if, [{verbosity, trace}]},
					{versions, [v1, v2, v3]}]).
%%%---------------------------------------------------------------------------
setup_agent(false,_, _, _, _, _) ->
    ok;
setup_agent(true, ConfName, Config, SysName, ManagerIP, AgentIP) ->
    application:start(mnesia),
    PrivDir = ?config(priv_dir, Config),
    Vsns = ct:get_config({ConfName, agent_vsns}, ?CONF_FILE_VER),
    TrapUdp = ct:get_config({ConfName, agent_trap_udp}, ?TRAP_UDP),
    AgentUdp = ct:get_config({ConfName, agent_udp}, ?AGENT_UDP),
    NotifType = ct:get_config({ConfName, agent_notify_type},
			      ?AGENT_NOTIFY_TYPE),
    SecType = ct:get_config({ConfName, agent_sec_type}, ?AGENT_SEC_TYPE),
    Passwd  = ct:get_config({ConfName, agent_passwd}, ?AGENT_PASSWD),
    AgentEngineID = ct:get_config({ConfName, agent_engine_id}, 
				  ?AGENT_ENGINE_ID),
    AgentMaxMsgSize = ct:get_config({ConfName, agent_max_msg_size},
				    ?MAX_MSG_SIZE),
    
    ConfDir = filename:join(PrivDir, "conf"),
    DbDir = filename:join(PrivDir,"db"),
    file:make_dir(ConfDir),
    file:make_dir(DbDir),    
    snmp_config:write_agent_snmp_files(ConfDir, Vsns, ManagerIP, TrapUdp, 
				       AgentIP, AgentUdp, SysName, 
				       atom_to_list(NotifType), 
				       SecType, Passwd, AgentEngineID, 
				       AgentMaxMsgSize),

    override_default_configuration(Config, ConfName),
   
    application:set_env(snmp, agent, [{db_dir, DbDir},
				      {config, [{dir, ConfDir},
						{verbosity, trace}]},
				      {agent_type, master},
				      {agent_verbosity, trace},
				      {net_if, [{verbosity, trace}]}]).
%%%---------------------------------------------------------------------------
manager_register(false, _) ->
    ok;
manager_register(true, ConfName) ->
    Agents = ct:get_config({ConfName, managed_agents}, []),
    Users = ct:get_config({ConfName, users}, []),
    UsmUsers = ct:get_config({ConfName, usm_users}, []),
    EngineID = ct:get_config({ConfName, engine_id}, ?ENGINE_ID),

    setup_usm_users(UsmUsers, EngineID),
    setup_users(Users),
    setup_managed_agents(Agents).

%%%---------------------------------------------------------------------------
setup_users(Users) ->
    lists:foreach(fun({Id, [Module, Data]}) ->
			  snmpm:register_user(Id, Module, Data)
		  end, Users).
%%%---------------------------------------------------------------------------   
setup_managed_agents([]) ->
    ok;

setup_managed_agents([{_, [Uid, AgentIp, AgentUdpPort, AgentConf]} |
		      Rest]) ->
    NewAgentIp = case AgentIp of
		     IpTuple when is_tuple(IpTuple) ->
			 IpTuple;
		     HostName when is_list(HostName) ->
			 {ok,Hostent} = inet:gethostbyname(HostName),
			 [IpTuple|_] = Hostent#hostent.h_addr_list,
			 IpTuple
		 end,
    ok = snmpm:register_agent(Uid, NewAgentIp, AgentUdpPort),   
    lists:foreach(fun({Item, Val}) ->
			  snmpm:update_agent_info(Uid, NewAgentIp, 
						  AgentUdpPort, Item, Val)
		  end, AgentConf),
    setup_managed_agents(Rest).
%%%---------------------------------------------------------------------------
setup_usm_users(UsmUsers, EngineID)->
    lists:foreach(fun({UsmUser, Conf}) ->
			  snmpm:register_usm_user(EngineID, UsmUser, Conf)
		  end, UsmUsers).
%%%---------------------------------------------------------------------------
takedown_users(Users) ->
     lists:foreach(fun({Id}) ->
			  snmpm:unregister_user(Id)
		   end, Users).
%%%---------------------------------------------------------------------------
takedown_managed_agents([{Uid, AgentIp, AgentUdpPort} |
			 Rest]) ->
    NewAgentIp = case AgentIp of
		     IpTuple when is_tuple(IpTuple) ->
			 IpTuple;
		     HostName when is_list(HostName) ->
			 {ok,Hostent} = inet:gethostbyname(HostName),
			 [IpTuple|_] = Hostent#hostent.h_addr_list,
			 IpTuple
		 end,
    ok = snmpm:unregister_agent(Uid, NewAgentIp, AgentUdpPort),   
    takedown_managed_agents(Rest);

takedown_managed_agents([]) ->
    ok.
%%%---------------------------------------------------------------------------
do_update_usm_users(UsmUsers, EngineID) ->
    lists:foreach(fun({UsmUser, {Item, Val}}) ->
			  snmpm:update_usm_user_info(EngineID, UsmUser, 
						     Item, Val)
		  end, UsmUsers).
%%%---------------------------------------------------------------------------  
log(PrivDir, Agent, {_, _, Varbinds}, NewVarsAndVals) ->

    Fun = fun(#varbind{oid = Oid, variabletype = Type, value = Value}) ->
		  {Oid, Type, Value} 
	  end,
    OldVarsAndVals = lists:map(Fun, Varbinds),
    
    File = filename:join(PrivDir, ?CT_SNMP_LOG_FILE),
    {ok, Fd} = file:open(File, [write, append]),
    io:format(Fd, "~p.~n", [{Agent, OldVarsAndVals, NewVarsAndVals}]),
    file:close(Fd),
    ok.
%%%---------------------------------------------------------------------------
del_dir(Dir) ->
    {ok, Files} = file:list_dir(Dir),
    FullPathFiles = lists:map(fun(File) -> filename:join(Dir, File) end,
			      Files),
    lists:foreach(fun file:delete/1, FullPathFiles), 
    file:del_dir(Dir),
    ok.
%%%---------------------------------------------------------------------------
agent_conf(Agent, ConfName) ->
    Agents = ct:get_config({ConfName, managed_agents}),
    case lists:keysearch(Agent, 1, Agents) of
	{value, {Agent, AgentConf}} ->
	    AgentConf;
	_ ->
	    exit({error, {unknown_agent, Agent, Agents}})
    end.
%%%---------------------------------------------------------------------------
override_default_configuration(Config, ConfName) ->
    override_contexts(Config,
		      ct:get_config({ConfName, agent_contexts}, undefined)),
    override_community(Config,
		       ct:get_config({ConfName, agent_community}, undefined)),
    override_sysinfo(Config,
		     ct:get_config({ConfName, agent_sysinfo}, undefined)),
    override_vacm(Config,
		  ct:get_config({ConfName, agent_vacm}, undefined)),
    override_usm(Config,
		 ct:get_config({ConfName, agent_usm}, undefined)),
    override_notify(Config,
		    ct:get_config({ConfName, agent_notify_def}, undefined)),
    override_target_address(Config,
			    ct:get_config({ConfName, 
					   agent_target_address_def}, 
					  undefined)),
    override_target_params(Config, 
			   ct:get_config({ConfName, agent_target_param_def},
					 undefined)).

%%%---------------------------------------------------------------------------
override_contexts(_, undefined) ->
    ok;

override_contexts(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, ContextInfo} = file:consult(FullPathFile),
    override_contexts(Config, ContextInfo);

override_contexts(Config, Contexts) ->
    Dir = ?config(priv_dir, Config),    
    File = filename:join(Dir,"context.conf"),
    file:delete(File),
    snmp_config:write_agent_context_config(Dir, "", Contexts).
		
%%%---------------------------------------------------------------------------
override_sysinfo(_, undefined) ->
    ok;

override_sysinfo(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, SysInfo} = file:consult(FullPathFile),
    override_sysinfo(Config, SysInfo);

override_sysinfo(Config, SysInfo) ->   
    Dir = ?config(priv_dir, Config),  
    File = filename:join(Dir,"standard.conf"),
    file:delete(File),
    snmp_config:write_agent_standard_config(Dir, "", SysInfo).

%%%---------------------------------------------------------------------------
override_target_address(_, undefined) ->
    ok;
override_target_address(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, TargetAddressConf} = file:consult(FullPathFile),
    override_target_address(Config, TargetAddressConf);

override_target_address(Config, TargetAddressConf) ->
    Dir = ?config(priv_dir, Config),  
    File = filename:join(Dir,"target_addr.conf"),
    file:delete(File),
    snmp_config:write_agent_target_addr_config(Dir, "", TargetAddressConf).


%%%---------------------------------------------------------------------------
override_target_params(_, undefined) ->
    ok;
override_target_params(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, TargetParamsConf} = file:consult(FullPathFile),
    override_target_params(Config, TargetParamsConf);

override_target_params(Config, TargetParamsConf) ->
    Dir = ?config(priv_dir, Config),  
    File = filename:join(Dir,"target_params.conf"),
    file:delete(File),
    snmp_config:write_agent_target_params_config(Dir, "", TargetParamsConf). 

%%%---------------------------------------------------------------------------
override_notify(_, undefined) ->
    ok;
override_notify(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, NotifyConf} = file:consult(FullPathFile),
    override_notify(Config, NotifyConf);

override_notify(Config, NotifyConf) ->
    Dir = ?config(priv_dir, Config),  
    File = filename:join(Dir,"notify.conf"),
    file:delete(File),
    snmp_config:write_agent_notify_config(Dir, "", NotifyConf).

%%%---------------------------------------------------------------------------
override_usm(_, undefined) ->
    ok;
override_usm(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, UsmConf} = file:consult(FullPathFile),
    override_usm(Config, UsmConf);

override_usm(Config, UsmConf) ->
    Dir = ?config(priv_dir, Config),  
    File = filename:join(Dir,"usm.conf"),
    file:delete(File),
    snmp_config:write_agent_usm_config(Dir, "", UsmConf).

%%%--------------------------------------------------------------------------
override_community(_, undefined) ->
    ok;
override_community(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, CommunityConf} = file:consult(FullPathFile),
    override_community(Config, CommunityConf);

override_community(Config, CommunityConf) ->
    Dir = ?config(priv_dir, Config),  
    File = filename:join(Dir,"community.conf"),
    file:delete(File),
    snmp_config:write_agent_community_config(Dir, "", CommunityConf).
   
%%%---------------------------------------------------------------------------

override_vacm(_, undefined) ->
    ok;
override_vacm(Config, {data_dir_file, File}) ->
    Dir = ?config(data_dir, Config),
    FullPathFile = filename:join(Dir, File),
    {ok, VacmConf} = file:consult(FullPathFile),
    override_vacm(Config, VacmConf);

override_vacm(Config, VacmConf) ->
    Dir = ?config(priv_dir, Config),  
       File = filename:join(Dir,"vacm.conf"),
    file:delete(File),
    snmp_config:write_agent_vacm_config(Dir, "", VacmConf).
