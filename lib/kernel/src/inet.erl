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
-module(inet).

-include("inet.hrl").
-include("inet_int.hrl").
-include("inet_sctp.hrl").

%% socket
-export([peername/1, sockname/1, port/1, send/2,
	 setopts/2, getopts/2, 
	 getif/1, getif/0, getiflist/0, getiflist/1,
	 ifget/3, ifget/2, ifset/3, ifset/2,
	 getstat/1, getstat/2,
	 ip/1, stats/0, options/0, 
	 pushf/3, popf/1, close/1, gethostname/0, gethostname/1]).

-export([connect_options/2, listen_options/2, udp_options/2, sctp_options/2]).

-export([i/0, i/1, i/2]).

-export([getll/1, getfd/1, open/7, fdopen/5]).

-export([tcp_controlling_process/2, udp_controlling_process/2,
	 tcp_close/1, udp_close/1]).
%% used by socks5
-export([setsockname/2, setpeername/2]).

%% resolve
-export([gethostbyname/1, gethostbyname/2, gethostbyname/3, 
	 gethostbyname_tm/3]).
-export([gethostbyaddr/1, gethostbyaddr/2, 
	 gethostbyaddr_tm/2]).

-export([getservbyname/2, getservbyport/2]).
-export([getaddrs/2, getaddrs/3, getaddrs_tm/3,
	 getaddr/2, getaddr/3, getaddr_tm/3]).
-export([translate_ip/2]).

-export([get_rc/0]).

%% format error
-export([format_error/1]).

%% timer interface
-export([start_timer/1, timeout/1, timeout/2, stop_timer/1]).

%% imports
-import(lists, [append/1, duplicate/2, member/2, filter/2,
		map/2, foldl/3, foreach/2]).

%% Record Signature
-define(RS(Record),
	{Record,record_info(size, Record)}).
%% Record Signature Check (guard)
-define(RSC(Record, RS),
	element(1, Record) =:= element(1, RS),
	size(Record) =:= element(2, RS)).

%%% ---------------------------------
%%% Contract type definitions

-type(socket() :: port()).
-type(posix() :: atom()).

-type(socket_setopt() ::
      {'raw', non_neg_integer(), non_neg_integer(), binary()} |
      %% TCP/UDP options
      {'reuseaddr',       bool()} |
      {'keepalive',       bool()} |
      {'dontroute',       bool()} |
      {'linger',          {bool(), non_neg_integer()}} |
      {'broadcast',       bool()} |
      {'sndbuf',          non_neg_integer()} |
      {'recbuf',          non_neg_integer()} |
      {'priority',        non_neg_integer()} |
      {'tos',             non_neg_integer()} |
      {'nodelay',         bool()} |
      {'multicast_ttl',   non_neg_integer()} |
      {'multicast_loop',  bool()} |
      {'multicast_if',    ip_address()} |
      {'add_membership',  {ip_address(), ip_address()}} |
      {'drop_membership', {ip_address(), ip_address()}} |
      {'header',          non_neg_integer()} |
      {'buffer',          non_neg_integer()} |
      {'active',          bool() | 'once'} |
      {'packet',        
       0 | 1 | 2 | 4 | 'raw' | 'sunrm' |  'asn1' |
       'cdr' | 'fcgi' | 'line' | 'tpkt' | 'http' | 'httph'} |
      {'mode',           list() | binary()} |
      {'port',           'port', 'term'} |
      {'exit_on_close',   bool()} |
      {'low_watermark',   non_neg_integer()} |
      {'high_watermark',  non_neg_integer()} |
      {'bit8',            'clear' | 'set' | 'on' | 'off'} |
      {'send_timeout',    non_neg_integer() | 'infinity'} |
      {'delay_send',      bool()} |
      {'packet_size',     non_neg_integer()} |
      {'read_packets',    non_neg_integer()} |
      %% SCTP options
      {'sctp_rtoinfo',               #sctp_rtoinfo{}} |
      {'sctp_associnfo',             #sctp_assocparams{}} |
      {'sctp_initmsg',               #sctp_initmsg{}} |
      {'sctp_nodelay',               bool()} |
      {'sctp_autoclose',             non_neg_integer()} |
      {'sctp_disable_fragments',     bool()} |
      {'sctp_i_want_mapped_v4_addr', bool()} |
      {'sctp_maxseg',                non_neg_integer()} |
      {'sctp_primary_addr',          #sctp_prim{}} |
      {'sctp_set_peer_primary_addr', #sctp_setpeerprim{}} |
      {'sctp_adaptation_layer',      #sctp_setadaptation{}} |
      {'sctp_peer_addr_params',      #sctp_paddrparams{}} |
      {'sctp_default_send_param',    #sctp_sndrcvinfo{}} |
      {'sctp_events',                #sctp_event_subscribe{}} |
      {'sctp_delayed_ack_time',      #sctp_assoc_value{}}).

-type(socket_getopt() ::
      {'raw',
       non_neg_integer(), non_neg_integer(), binary()|non_neg_integer()} |
      %% TCP/UDP options
      'reuseaddr' | 'keepalive' | 'dontroute' | 'linger' |
      'broadcast' | 'sndbuf' | 'recbuf' | 'priority' | 'tos' | 'nodelay' | 
      'multicast_ttl' | 'multicast_loop' | 'multicast_if' | 
      'add_membership' | 'drop_membership' | 
      'header' | 'buffer' | 'active' | 'packet' | 'mode' | 'port' | 
      'exit_on_close' | 'low_watermark' | 'high_watermark' | 'bit8' | 
      'send_timeout' | 'delay_send' | 'packet_size' | 'read_packets' | 
      %% SCTP options
      {'sctp_status',                #sctp_status{}} |
      'sctp_get_peer_addr_info' |
      {'sctp_get_peer_addr_info',    #sctp_status{}} |
      'sctp_rtoinfo' |
      {'sctp_rtoinfo',               #sctp_rtoinfo{}} |
      'sctp_associnfo' |
      {'sctp_associnfo',             #sctp_assocparams{}} |
      'sctp_initmsg' |
      {'sctp_initmsg',               #sctp_initmsg{}} |
      'sctp_nodelay' | 'sctp_autoclose' | 'sctp_disable_fragments' |
      'sctp_i_want_mapped_v4_addr' | 'sctp_maxseg' |
      {'sctp_primary_addr',          #sctp_prim{}} |
      {'sctp_set_peer_primary_addr', #sctp_setpeerprim{}} |
      'sctp_adaptation_layer' |
      {'sctp_adaptation_layer',      #sctp_setadaptation{}} |
      {'sctp_peer_addr_params',      #sctp_paddrparams{}} |
      'sctp_default_send_param' |
      {'sctp_default_send_param',    #sctp_sndrcvinfo{}} |
      'sctp_events' |
      {'sctp_events',                #sctp_event_subscribe{}} |
      'sctp_delayed_ack_time' |
      {'sctp_delayed_ack_time',      #sctp_assoc_value{}}).

-type(ether_address() :: [0..255]).

-type(if_setopt() ::
      {'addr', ip_address()} |
      {'broadaddr', ip_address()} |
      {'dstaddr', ip_address()} |
      {'mtu', non_neg_integer()} |
      {'netmask', ip_address()} |
      {'flags', ['up' | 'down' | 'broadcast' | 'no_broadcast' |
		 'pointtopoint' | 'no_pointtopoint' | 
		 'running' | 'multicast']} |
      {'hwaddr', ether_address()}).

-type(if_getopt() ::
      'addr' | 'broadaddr' | 'dstaddr' | 
      'mtu' | 'netmask' | 'flags' |'hwaddr'). 

-type(family_option() :: 'inet' | 'inet6').
-type(protocol_option() :: 'tcp' | 'udp' | 'sctp').
-type(stat_option() :: 
	'recv_cnt' | 'recv_max' | 'recv_avg' | 'recv_oct' | 'recv_dvi' |
	'send_cnt' | 'send_max' | 'send_avg' | 'send_oct' | 'send_pend').
%%% ---------------------------------

-spec(get_rc/0 :: () -> [{any(),any()}]).

get_rc() ->
    inet_db:get_rc().

-spec(close/1 :: (Socket :: socket()) -> 'ok').

close(Socket) ->
    prim_inet:close(Socket),
    receive
	{Closed, Socket} when Closed =:= tcp_closed; Closed =:= udp_closed ->
	    ok
    after 0 ->
	    ok
    end.

-spec(peername/1 :: (Socket :: socket()) -> 
	{'ok', {ip_address(), non_neg_integer()}} | {'error', posix()}).

peername(Socket) -> 
    prim_inet:peername(Socket).

-spec(setpeername/2 :: (
	Socket :: socket(), 
	Address :: {ip_address(), ip_port()}) ->
	'ok' | {'error', any()}).  

setpeername(Socket, {IP,Port}) ->
    prim_inet:setpeername(Socket, {IP,Port});
setpeername(Socket, undefined) ->
    prim_inet:setpeername(Socket, undefined).


-spec(sockname/1 :: (Socket :: socket()) -> 
	{'ok', {ip_address(), non_neg_integer()}} | {'error', posix()}).

sockname(Socket) -> 
    prim_inet:sockname(Socket).

-spec(setsockname/2 :: (
	Socket :: socket(),
	Address :: {ip_address(), ip_port()}) ->
	'ok' | {'error', any()}).	

setsockname(Socket, {IP,Port}) -> 
    prim_inet:setsockname(Socket, {IP,Port});
setsockname(Socket, undefined) ->
    prim_inet:setsockname(Socket, undefined).

-spec(port/1 :: (Socket :: socket()) -> 
	{'ok', ip_port()} | {'error', any()}). 

port(Socket) ->
    case prim_inet:sockname(Socket) of
	{ok, {_,Port}} -> {ok, Port};
	Error -> Error
    end.

-spec(send/2 :: (
	Socket :: socket(),
	Packet :: iolist()) -> % iolist()?
	'ok' | {'error', posix()}).

send(Socket, Packet) -> 
    prim_inet:send(Socket, Packet).
    
-spec(setopts/2 :: (
	Socket :: socket(),
	Opts :: [socket_setopt()]) -> 
	'ok' | {'error', posix()}).

setopts(Socket, Opts) -> 
    prim_inet:setopts(Socket, Opts).

-spec(getopts/2 :: (
	Socket :: socket(),
	Opts :: [socket_getopt()]) ->	
	{'ok', [socket_setopt()]} | {'error', posix()}).

getopts(Socket, Opts) ->
    prim_inet:getopts(Socket, Opts).

-spec(getiflist/1 :: (Socket :: socket()) ->
	{'ok', [string()]} | {'error', posix()}).	 

getiflist(Socket) -> 
    prim_inet:getiflist(Socket).

-spec(getiflist/0 :: () ->
	{'ok', [string()]} | {'error', posix()}).	 

getiflist() -> 
    withsocket(fun(S) -> prim_inet:getiflist(S) end).
    
-spec(ifget/3 :: (
	Socket :: socket(),
        Name :: string() | atom(),
	Opts :: [if_getopt()]) ->
	{'ok', [if_setopt()]} | 
	{'error', posix()}).	

ifget(Socket, Name, Opts) -> 
    prim_inet:ifget(Socket, Name, Opts).

-spec(ifget/2 :: (
	Name :: string() | atom(),
	Opts :: [if_getopt()]) ->
	{'ok', [if_setopt()]} | 
	{'error', posix()}).	

ifget(Name, Opts) -> 
    withsocket(fun(S) -> prim_inet:ifget(S, Name, Opts) end).

-spec(ifset/3 :: (
	Socket :: socket(),
	Name :: string() | atom(),
	Opts :: [if_setopt()]) ->
	'ok' | {'error', posix()}). 	

ifset(Socket, Name, Opts) -> 
    prim_inet:ifset(Socket, Name, Opts).

-spec(ifset/2 :: (
	Name :: string() | atom(),
	Opts :: [if_setopt()]) ->
	'ok' | {'error', posix()}). 	

ifset(Name, Opts) -> 
    withsocket(fun(S) -> prim_inet:ifset(S, Name, Opts) end).

-spec(getif/0 :: () ->
	{'ok', [{ip_address(), ip_address() | 'undefined', ip_address()}]} | 
	{'error', posix()}).	

getif() -> 
    withsocket(fun(S) -> getif(S) end).

%% backwards compatible getif
-spec(getif/1 :: (Socket :: socket()) ->
	{'ok', [{ip_address(), ip_address() | 'undefined', ip_address()}]} | 
	{'error', posix()}).	

getif(Socket) ->
    case prim_inet:getiflist(Socket) of
	{ok, IfList} ->
	    {ok, lists:foldl(
		   fun(Name,Acc) ->
			   case prim_inet:ifget(Socket,Name,
						[addr,broadaddr,netmask]) of
			       {ok,[{addr,A},{broadaddr,B},{netmask,M}]} ->
				   [{A,B,M}|Acc];
			       %% Some interfaces does not have a b-addr
			       {ok,[{addr,A},{netmask,M}]} ->
				   [{A,undefined,M}|Acc];
			       _ ->
				   Acc
			   end
		   end, [], IfList)};
	Error -> Error
    end.

withsocket(Fun) ->
    case inet_udp:open(0,[]) of
	{ok,Socket} ->
	    Res = Fun(Socket),
	    inet_udp:close(Socket),
	    Res;
	Error ->
	    Error
    end.

pushf(_Socket, Fun, _State) when is_function(Fun) ->
    {error, einval}.

popf(_Socket) ->
    {error, einval}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% the hostname is not cached any more because this
% could cause troubles on at least windows with plug-and-play
% and network-cards inserted and removed in conjunction with
% use of the DHCP-protocol
% should never fail

-spec(gethostname/0 :: () -> {'ok', string()}).

gethostname() ->
    case inet_udp:open(0,[]) of
	{ok,U} ->
	    {ok,Res} = gethostname(U),
	    inet_udp:close(U),
	    {Res2,_} = lists:splitwith(fun($.)->false;(_)->true end,Res),
	    {ok, Res2};
	_ ->
	    {ok, "nohost.nodomain"}
    end.

-spec(gethostname/1 :: (Socket :: socket()) ->
	{'ok', string()} | {'error', posix()}).

gethostname(Socket) ->
    prim_inet:gethostname(Socket).

-spec(getstat/1 :: (Socket :: socket()) ->
	{'ok', [{stat_option(), integer()}]} | {'error', posix()}). 		

getstat(Socket) ->
    prim_inet:getstat(Socket, stats()).

-spec(getstat/2 :: (
	Socket :: socket(),
	Statoptions :: [stat_option()]) ->
	{'ok', [{stat_option(), integer()}]} | {'error', posix()}). 		

getstat(Socket,What) ->
    prim_inet:getstat(Socket, What).

-spec(gethostbyname/1 :: (Name :: string() | atom()) ->
	{'ok', #hostent{}} | {'error', posix()}).

gethostbyname(Name) -> 
    gethostbyname_tm(Name, inet, false).

-spec(gethostbyname/2 :: (
	Name :: string() | atom(),
	Family :: family_option()) ->
	{'ok', #hostent{}} | {'error', posix()}).

gethostbyname(Name,Family) -> 
    gethostbyname_tm(Name, Family, false).

-spec(gethostbyname/3 :: (
	Name :: string() | atom(),
	Family :: family_option(),
	Timeout :: non_neg_integer() | 'infinity') ->
	{'ok', #hostent{}} | {'error', posix()}).
	
gethostbyname(Name,Family,Timeout) ->
    Timer = start_timer(Timeout),
    Res = gethostbyname_tm(Name,Family,Timer),
    stop_timer(Timer),
    Res.

gethostbyname_tm(Name,Family,Timer) ->
    gethostbyname_tm(Name,Family,Timer,inet_db:res_option(lookup)).


-spec(gethostbyaddr/1 :: (Address :: string() | ip_address()) ->
	{'ok', #hostent{}} | {'error', posix()}).

gethostbyaddr(Address) ->
    gethostbyaddr_tm(Address, false).

-spec(gethostbyaddr/2 :: (
	Address :: string() | ip_address(), 
	Timeout :: non_neg_integer() | 'infinity') ->
	{'ok', #hostent{}} | {'error', posix()}).

gethostbyaddr(Address,Timeout) ->
    Timer = start_timer(Timeout),    
    Res = gethostbyaddr_tm(Address, Timer),
    stop_timer(Timer),
    Res.

gethostbyaddr_tm(Address,Timer) ->
    gethostbyaddr_tm(Address, Timer, inet_db:res_option(lookup)).

-spec(ip/1 :: (Ip :: ip_address() | string() | atom()) ->
	{'ok', ip_address()} | {'error', posix()}).

ip({A,B,C,D}) when ?ip(A,B,C,D) ->
    {ok, {A,B,C,D}};
ip(Name) ->
    case gethostbyname(Name) of
	{ok, Ent} ->
	    {ok, hd(Ent#hostent.h_addr_list)};
	Error -> Error
    end.

%% This function returns the erlang port used (with inet_drv)
%% Return values: {ok,#Port} if ok
%%                {error, einval} if not applicable

-spec(getll/1 :: (Socket :: socket()) ->
	{'ok', socket()}).

getll(Socket) when is_port(Socket) ->
    {ok, Socket}.

%%
%% Return the internal file descriptor number
%%

-spec(getfd/1 :: (Socket :: socket()) ->
	{'ok', non_neg_integer()} | {'error', posix()}).

getfd(Socket) ->
    prim_inet:getfd(Socket).

%%
%% Lookup an ip address
%%

-spec(getaddr/2 :: (
	Host :: ip_address() | string() | atom(),
	Family :: family_option()) ->
	{'ok', ip_address()} | {'error', posix()}).	

getaddr(Address, Family) ->
    getaddr(Address, Family, infinity).

-spec(getaddr/3 :: (
	Host :: ip_address() | string() | atom(),
	Family :: family_option(),
	Timeout :: non_neg_integer() | 'infinity') ->
	{'ok', ip_address()} | {'error', posix()}).	

getaddr(Address, Family, Timeout) ->
    Timer = start_timer(Timeout),
    Res = getaddr_tm(Address, Family, Timer),
    stop_timer(Timer),
    Res.
    
getaddr_tm(Address, Family, Timer) ->
    case getaddrs_tm(Address, Family, Timer) of
	{ok, [IP|_]} -> {ok, IP};
	Error -> Error
    end.

-spec(getaddrs/2 :: (
	Host :: ip_address() | string() | atom(),
	Family :: family_option()) ->
	{'ok', [ip_address()]} | {'error', posix()}).	

getaddrs(Address, Family) -> 
    getaddrs(Address, Family, infinity).

-spec(getaddrs/3 :: (
	Host :: ip_address() | string() | atom(),
	Family :: family_option(),
	Timeout :: non_neg_integer() | 'infinity') ->
	{'ok', [ip_address()]} | {'error', posix()}).	

getaddrs(Address, Family,Timeout) -> 
    Timer = start_timer(Timeout),    
    Res = getaddrs_tm(Address, Family, Timer),
    stop_timer(Timer),
    Res.    

-spec(getservbyport/2 :: (
	Port :: ip_port(),
	Protocol :: atom() | string()) ->
	{'ok', string()} | {'error', posix()}). 

getservbyport(Port, Proto) ->
    case inet_udp:open(0, []) of
	{ok,U} ->
	    Res = prim_inet:getservbyport(U,Port, Proto),
	    inet_udp:close(U),
	    Res;
	Error -> Error
    end.

-spec(getservbyname/2 :: (
	Name :: atom() | string(),
	Protocol :: atom() | string()) ->
	{'ok', ip_port()} | {'error', posix()}). 

getservbyname(Name, Proto) when is_atom(Name) ->
    case inet_udp:open(0, []) of
	{ok,U} ->
	    Res = prim_inet:getservbyname(U,Name, Proto),
	    inet_udp:close(U),
	    Res;
	Error -> Error
    end.

%% Return a list of available options
options() ->
    [
     tos, priority, reuseaddr, keepalive, dontroute, linger,
     broadcast, sndbuf, recbuf, nodelay,
     buffer, header, active, packet, deliver, mode,
     multicast_if, multicast_ttl, multicast_loop,
     exit_on_close, high_watermark, low_watermark,
     bit8, send_timeout
    ].

%% Return a list of statistics options

-spec(stats/0 :: () -> [stat_option(),...]).

stats() ->
    [recv_oct, recv_cnt, recv_max, recv_avg, recv_dvi,
     send_oct, send_cnt, send_max, send_avg, send_pend].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Available options for tcp:connect
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
connect_options() ->
    [tos, priority, reuseaddr, keepalive, linger, sndbuf, recbuf, nodelay,
     header, active, packet, packet_size, buffer, mode, deliver,
     exit_on_close, high_watermark, low_watermark, bit8, send_timeout,
     delay_send,raw].
    
connect_options(Opts, Family) ->
    BaseOpts = 
	case application:get_env(kernel, inet_default_connect_options) of
	    {ok,List} when is_list(List) ->
		NList = [{active, true} | lists:keydelete(active,1,List)],     
		#connect_opts{ opts = NList};
	    {ok,{active,_Bool}} -> 
		#connect_opts{ opts = [{active,true}]};
	    {ok,Option} -> 
		#connect_opts{ opts = [{active,true}, Option]};
	    _ ->
		#connect_opts{ opts = [{active,true}]}
	end,
    case con_opt(Opts, BaseOpts, connect_options()) of
	{ok, R} ->
	    {ok, R#connect_opts {
		   ifaddr = translate_ip(R#connect_opts.ifaddr, Family)
		  }};
	Error -> Error	    
    end.

con_opt([{raw,A,B,C}|Opts],R,As) ->
    con_opt([{raw,{A,B,C}}|Opts],R,As);
con_opt([Opt | Opts], R, As) ->
    case Opt of
	{ip,IP}     -> con_opt(Opts, R#connect_opts { ifaddr = IP }, As);
	{ifaddr,IP} -> con_opt(Opts, R#connect_opts { ifaddr = IP }, As);
	{port,P}    -> con_opt(Opts, R#connect_opts { port = P }, As);
	{fd,Fd}     -> con_opt(Opts, R#connect_opts { fd = Fd }, As);
	binary      -> con_add(mode, binary, R, Opts, As);
	list        -> con_add(mode, list, R, Opts, As);
	{tcp_module,_}  -> con_opt(Opts, R, As);
	inet        -> con_opt(Opts, R, As);
	inet6       -> con_opt(Opts, R, As);
	{Name,Val} when is_atom(Name) -> con_add(Name, Val, R, Opts, As);
	_ -> {error, badarg}
    end;
con_opt([], R, _) ->
    {ok, R}.

con_add(Name, Val, R, Opts, AllOpts) ->
    case add_opt(Name, Val, R#connect_opts.opts, AllOpts) of
	{ok, SOpts} ->
	    con_opt(Opts, R#connect_opts { opts = SOpts }, AllOpts);
	Error -> Error
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Available options for tcp:listen
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
listen_options() ->
    [tos, priority, reuseaddr, keepalive, linger, sndbuf, recbuf, nodelay,
     header, active, packet, buffer, mode, deliver, backlog,
     exit_on_close, high_watermark, low_watermark, bit8, send_timeout,
     delay_send, packet_size,raw].

listen_options(Opts, Family) ->
    BaseOpts = 
	case application:get_env(kernel, inet_default_listen_options) of
	    {ok,List} when is_list(List) ->
		NList = [{active, true} | lists:keydelete(active,1,List)],		       
		#listen_opts{ opts = NList};
	    {ok,{active,_Bool}} -> 
		#listen_opts{ opts = [{active,true}]};
	    {ok,Option} -> 
		#listen_opts{ opts = [{active,true}, Option]};
	    _ ->
		#listen_opts{ opts = [{active,true}]}
	end,
    case list_opt(Opts, BaseOpts, listen_options()) of
	{ok, R} ->
	    {ok, R#listen_opts {
		   ifaddr = translate_ip(R#listen_opts.ifaddr, Family)
		  }};
	Error -> Error
    end.
	
list_opt([{raw,A,B,C}|Opts], R, As) ->
    list_opt([{raw,{A,B,C}}|Opts], R, As);
list_opt([Opt | Opts], R, As) ->
    case Opt of
	{ip,IP}      ->  list_opt(Opts, R#listen_opts { ifaddr = IP }, As);
	{ifaddr,IP}  ->  list_opt(Opts, R#listen_opts { ifaddr = IP }, As);
	{port,P}     ->  list_opt(Opts, R#listen_opts { port = P }, As);
	{fd,Fd}      ->  list_opt(Opts, R#listen_opts { fd = Fd }, As);
	{backlog,BL} ->  list_opt(Opts, R#listen_opts { backlog = BL }, As);
	binary       ->  list_add(mode, binary, R, Opts, As);
	list         ->  list_add(mode, list, R, Opts, As);
	{tcp_module,_}  -> list_opt(Opts, R, As);
	inet         -> list_opt(Opts, R, As);
	inet6        -> list_opt(Opts, R, As);
	{Name,Val} when is_atom(Name) -> list_add(Name, Val, R, Opts, As);
	_ -> {error, badarg}
    end;
list_opt([], R, _SockOpts) ->
    {ok, R}.

list_add(Name, Val, R, Opts, As) ->
    case add_opt(Name, Val, R#listen_opts.opts, As) of
	{ok, SOpts} ->
	    list_opt(Opts, R#listen_opts { opts = SOpts }, As);
	Error -> Error
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Available options for udp:open
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
udp_options() ->
    [tos, priority, reuseaddr, sndbuf, recbuf, header, active, buffer, mode, 
     deliver,
     broadcast, dontroute, multicast_if, multicast_ttl, multicast_loop,
     add_membership, drop_membership, read_packets,raw].


udp_options(Opts, Family) ->
    case udp_opt(Opts, #udp_opts { }, udp_options()) of
	{ok, R} ->
	    {ok, R#udp_opts {
		   ifaddr = translate_ip(R#udp_opts.ifaddr, Family)
		  }};
	Error -> Error
    end.

udp_opt([{raw,A,B,C}|Opts], R, As) ->
    udp_opt([{raw,{A,B,C}}|Opts], R, As);
udp_opt([Opt | Opts], R, As) ->
    case Opt of
	{ip,IP}     ->  udp_opt(Opts, R#udp_opts { ifaddr = IP }, As);
	{ifaddr,IP} ->  udp_opt(Opts, R#udp_opts { ifaddr = IP }, As);
	{port,P}    ->  udp_opt(Opts, R#udp_opts { port = P }, As);
	{fd,Fd}     ->  udp_opt(Opts, R#udp_opts { fd = Fd }, As);
	binary      ->  udp_add(mode, binary, R, Opts, As);
	list        ->  udp_add(mode, list, R, Opts, As);
	{udp_module,_} -> udp_opt(Opts, R, As);
	inet        -> udp_opt(Opts, R, As);
	inet6       -> udp_opt(Opts, R, As);
	{Name,Val} when is_atom(Name) -> udp_add(Name, Val, R, Opts, As);
	_ -> {error, badarg}
    end;
udp_opt([], R, _SockOpts) ->
    {ok, R}.

udp_add(Name, Val, R, Opts, As) ->
    case add_opt(Name, Val, R#udp_opts.opts, As) of
	{ok, SOpts} ->
	    udp_opt(Opts, R#udp_opts { opts = SOpts }, As);
	Error -> Error
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Available options for sctp:open
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  Currently supported options include:
%  (*) {mode,   list|binary}	 or just list|binary
%  (*) {active, true|false|once}
%  (*) {sctp_module, inet_sctp|inet6_sctp} or just inet|inet6
%  (*) options set via setsockopt.
%      The full list is below in sctp_options/0 .
%  All other options are currently NOT supported. In particular:
%  (*) multicast on SCTP is not (yet) supported, as it may be incompatible
%      with automatic associations;
%  (*) passing of open FDs ("fdopen") is not supported.
sctp_options() ->
[   % The following are generic inet options supported for SCTP sockets:
    mode, active, buffer, tos, priority, dontroute, reuseaddr, linger, sndbuf,
    recbuf,

    % Other options are SCTP-specific (though they may be similar to their
    % TCP and UDP counter-parts):
    sctp_rtoinfo,   		 sctp_associnfo,	sctp_initmsg,
    sctp_autoclose,		 sctp_nodelay,		sctp_disable_fragments,
    sctp_i_want_mapped_v4_addr,  sctp_maxseg,		sctp_primary_addr,
    sctp_set_peer_primary_addr,  sctp_adaptation_layer,	sctp_peer_addr_params,
    sctp_default_send_param,	 sctp_events,		sctp_delayed_ack_time,
    sctp_status,	   	 sctp_get_peer_addr_info
].

sctp_options(Opts, Mod)  ->
    case sctp_opt(Opts, Mod, #sctp_opts{}, sctp_options()) of
	{ok,#sctp_opts{ifaddr=undefined}=SO} -> 
	    {ok,SO#sctp_opts{ifaddr=Mod:translate_ip(?SCTP_DEF_IFADDR)}};
	{ok,_}=OK ->
	    OK;
	Error -> Error
    end.

sctp_opt([Opt|Opts], Mod, R, As) ->
    case Opt of
	{ip,IP} ->
	    sctp_opt_ifaddr(Opts, Mod, R, As, IP);
	{ifaddr,IP} ->
	    sctp_opt_ifaddr(Opts, Mod, R, As, IP);
	{port,Port} ->
	    case Mod:getserv(Port) of
		{ok,P} ->
		    sctp_opt(Opts, Mod, R#sctp_opts{port=P}, As);
		Error -> Error
	    end;
	binary		-> sctp_opt (Opts, Mod, R, As, mode, binary);
	list		-> sctp_opt (Opts, Mod, R, As, mode, list);
	{sctp_module,_}	-> sctp_opt (Opts, Mod, R, As); % Done with
	inet		-> sctp_opt (Opts, Mod, R, As); % Done with
	inet6		-> sctp_opt (Opts, Mod, R, As); % Done with
	{Name,Val}	-> sctp_opt (Opts, Mod, R, As, Name, Val);
	_ -> {error,badarg}
    end;
sctp_opt([], _Mod, R, _SockOpts) ->
    {ok, R}.

sctp_opt(Opts, Mod, R, As, Name, Val) ->
    case add_opt(Name, Val, R#sctp_opts.opts, As) of
	{ok,SocketOpts} ->
	    sctp_opt(Opts, Mod, R#sctp_opts{opts=SocketOpts}, As);
	Error -> Error
    end.

sctp_opt_ifaddr(Opts, Mod, #sctp_opts{ifaddr=IfAddr}=R, As, Addr) ->
    IP = Mod:translate_ip(Addr),
    sctp_opt(Opts, Mod, 
	     R#sctp_opts{
	       ifaddr=case IfAddr of
			  undefined              -> IP;
			  _ when is_list(IfAddr) -> [IP|IfAddr];
			  _                      -> [IP,IfAddr]
		      end}, As).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Util to check and insert option in option list
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

add_opt(Name, Val, Opts, As) ->
    case member(Name, As) of
	true ->
	    case prim_inet:is_sockopt_val(Name, Val) of
		true ->
		    Opts1 = lists:keydelete(Name, 1, Opts),
		    {ok, [{Name,Val} | Opts1]};
		false -> {error,badarg}
	    end;
	false -> {error,badarg}
    end.
	

translate_ip(any,      inet) -> {0,0,0,0};
translate_ip(loopback, inet) -> {127,0,0,1};
translate_ip(any,      inet6) -> {0,0,0,0,0,0,0,0};
translate_ip(loopback, inet6) -> {0,0,0,0,0,0,0,1};
translate_ip(IP, _) -> IP.


getaddrs_tm({A,B,C,D} = IP, Fam, _)  ->
    %% Only "syntactic" validation and check of family.
    if 
	?ip(A,B,C,D) ->
	    if
		Fam =:= inet -> {ok,[IP]};
		true -> {error,nxdomain}
	    end;
	true ->         {error,einval}
    end;
getaddrs_tm({A,B,C,D,E,F,G,H} = IP, Fam, _) ->
    %% Only "syntactic" validation; we assume that the address was
    %% "semantically" validated when it was converted to a tuple.
    if 
	?ip6(A,B,C,D,E,F,G,H) ->
	    if
		Fam =:= inet6 -> {ok,[IP]};
		true -> {error,nxdomain}
	    end;
	true -> {error,einval}
    end;
getaddrs_tm(Address, Family, Timer) when is_atom(Address) ->
    getaddrs_tm(atom_to_list(Address), Family, Timer);
getaddrs_tm(Address, Family, Timer) ->
    case inet_parse:visible_string(Address) of
	false ->
	    {error,einval};
	true ->
	    %% Address is a host name or a valid IP address,
	    %% either way check it with the resolver.
	    case gethostbyname_tm(Address, Family, Timer) of
		{ok,Ent} -> {ok,Ent#hostent.h_addr_list};
		Error -> Error
	    end
    end.

%%
%% gethostbyname with option search
%%
gethostbyname_tm(Name, Type, Timer, [dns | Opts]) ->
    Res = inet_res:gethostbyname_tm(Name, Type, Timer),
    case Res of
	{ok,_} -> Res;
	{error,timeout} -> Res;
	{error,formerr} -> {error,einval};
	{error,_} -> gethostbyname_tm(Name,Type,Timer,Opts)
    end;
gethostbyname_tm(Name, Type, Timer, [file | Opts]) ->
    case inet_hosts:gethostbyname(Name, Type) of
	{error,formerr} -> {error,einval};
	{error,_} -> gethostbyname_tm(Name,Type,Timer,Opts);
	Result -> Result
    end;
gethostbyname_tm(Name, Type, Timer, [yp | Opts]) ->
    gethostbyname_tm(Name, Type, Timer, [native|Opts]);
gethostbyname_tm(Name, Type, Timer, [nis | Opts]) ->
    gethostbyname_tm(Name, Type, Timer, [native|Opts]);
gethostbyname_tm(Name, Type, Timer, [nisplus | Opts]) ->
    gethostbyname_tm(Name, Type, Timer, [native|Opts]);
gethostbyname_tm(Name, Type, Timer, [wins | Opts]) ->
    gethostbyname_tm(Name, Type, Timer, [native|Opts]);
gethostbyname_tm(Name, Type, Timer, [native | Opts]) ->
    %% Fixme: add (global) timeout to gethost_native
    case inet_gethost_native:gethostbyname(Name, Type) of
	{error,formerr} -> {error,einval};
	{error,timeout} -> {error,timeout};
	{error,_} -> gethostbyname_tm(Name, Type, Timer, Opts++no_default);
	Result -> Result
    end;
gethostbyname_tm(Name, Type, Timer, [_ | Opts]) ->
    gethostbyname_tm(Name, Type, Timer, Opts);
gethostbyname_tm(Name, inet, _Timer, []) ->
    case inet_parse:ipv4_address(Name) of
	{ok,IP4} ->
	    {ok, 
	     #hostent{
	       h_name = Name,
	       h_aliases = [],
	       h_addrtype = inet,
	       h_length = 4,
	       h_addr_list = [IP4]}};
	_ ->
	    case inet_parse:ipv6_address(Name) of
		{ok,_} -> {error,einval};
		_ ->      {error,nxdomain}
	    end
    end;
gethostbyname_tm(Name, inet6, _Timer, []) ->
    case inet_parse:ipv6_address(Name) of
	{ok,IP6} ->
	    {ok, 
	     #hostent{
	       h_name = Name,
	       h_aliases = [],
	       h_addrtype = inet6,
	       h_length = 16,
	       h_addr_list = [IP6]}};
	_ ->
	    %% Even if Name is a valid IPv4 address, we can't
	    %% assume it's correct to return it on a IPv6
	    %% format ( {0,0,0,0,0,16#ffff,?u16(A,B),?u16(C,D)} ).
	    %% This host might not support IPv6.
	    {error,nxdomain}
    end;
gethostbyname_tm(Name, inet, _, no_default) ->
    %% If the native resolver has failed, we should not bother
    %% to try to be smarter and parse the IP address here.
    case inet_parse:ipv6_address(Name) of
	{ok,_} -> {error,einval};
	_ ->      {error,nxdomain}
    end;
gethostbyname_tm(_Name, inet6, _, no_default) ->
    %% If the native resolver has failed, we should not bother
    %% to try to be smarter and parse the IP address here.
    {error,nxdomain}.

%%
%% gethostbyaddr with option search
%%
gethostbyaddr_tm(Addr, Timer, [dns | Opts]) ->
    Res = inet_res:gethostbyaddr_tm(Addr,Timer),
    case Res of
	{ok,_} -> Res;
	{error,timeout} -> Res;
	{error,formerr} -> {error, einval};
	{error,_} -> gethostbyaddr_tm(Addr,Timer,Opts)
    end;    
gethostbyaddr_tm(Addr, Timer, [file | Opts]) ->
    case inet_hosts:gethostbyaddr(Addr) of
	{error,formerr} -> {error, einval};
	{error,_} -> gethostbyaddr_tm(Addr,Timer,Opts);
	Result -> Result
    end;    
gethostbyaddr_tm(Addr, Timer, [yp | Opts]) ->
    gethostbyaddr_tm(Addr, Timer, [native | Opts]);
gethostbyaddr_tm(Addr, Timer, [nis | Opts]) ->
    gethostbyaddr_tm(Addr, Timer, [native | Opts]);
gethostbyaddr_tm(Addr, Timer,  [nisplus | Opts]) ->
    gethostbyaddr_tm(Addr, Timer, [native | Opts]);
gethostbyaddr_tm(Addr, Timer, [wins | Opts]) ->
    gethostbyaddr_tm(Addr, Timer, [native | Opts]);
gethostbyaddr_tm(Addr, Timer, [native | Opts]) ->
    %% Fixme: user timer for timeoutvalue
    case inet_gethost_native:gethostbyaddr(Addr) of
	{error,formerr} -> {error, einval};
	{error,_} -> gethostbyaddr_tm(Addr,Timer,Opts);
	Result -> Result
    end;    
gethostbyaddr_tm(Addr, Timer, [_ | Opts]) ->
    gethostbyaddr_tm(Addr, Timer, Opts);
gethostbyaddr_tm(_Addr, _Timer, []) ->
    {error, nxdomain}.

-spec(open/7 :: (
	Fd :: integer(),
	Addr :: ip_address(),
	Port :: ip_port(),
	Opts :: [socket_setopt()],
	Protocol :: protocol_option(),
	Family :: 'inet' | 'inet6',
	Module :: atom()) ->
	{'ok', socket()} | {'error', posix()}).

open(Fd, Addr, Port, Opts, Protocol, Family, Module) when Fd < 0 ->
    case prim_inet:open(Protocol, Family) of
	{ok,S} ->
	    case prim_inet:setopts(S, Opts) of
		ok ->
		    case if is_list(Addr) ->
				 prim_inet:bind(S, add,
						[case A of
						     {_,_} -> A;
						     _     -> {A,Port}
						 end || A <- Addr]);
			    true ->
				 prim_inet:bind(S, Addr, Port)
			 end of
			{ok, _} -> 
			    inet_db:register_socket(S, Module),
			    {ok,S};
			Error  ->
			    prim_inet:close(S),
			    Error
		    end;
		Error  ->
		    prim_inet:close(S),
		    Error
	    end;
	Error ->
	    Error
    end;
open(Fd, _Addr, _Port, Opts, Protocol, Family, Module) ->
    fdopen(Fd, Opts, Protocol, Family, Module).

-spec(fdopen/5 :: (
	Fd :: non_neg_integer(),
	Opts :: [socket_setopt()],
	Protocol :: protocol_option(),
	Family :: family_option(),
	Module :: atom()) ->
	{'ok', socket()} | {'error', posix()}).

fdopen(Fd, Opts, Protocol, Family, Module) ->
    case prim_inet:fdopen(Protocol, Fd, Family) of
	{ok, S} ->
	    case prim_inet:setopts(S, Opts) of
		ok ->
		    inet_db:register_socket(S, Module),
		    {ok, S};
		Error ->
		    prim_inet:close(S), Error
	    end;
	Error -> Error
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  socket stat
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

i() -> i(tcp), i(udp).

i(Proto) -> i(Proto, [port, module, recv, sent, owner,
		      local_address, foreign_address, state]).

i(tcp, Fs) ->
    ii(tcp_sockets(), Fs, tcp);
i(udp, Fs) ->
    ii(udp_sockets(), Fs, udp).

ii(Ss, Fs, Proto) ->
    LLs = [h_line(Fs) | info_lines(Ss, Fs, Proto)],
    Maxs = foldl(
	     fun(Line,Max0) -> smax(Max0,Line) end, 
	     duplicate(length(Fs),0),LLs),
    Fmt = append(map(fun(N) -> "~-" ++ integer_to_list(N) ++ "s " end,
		     Maxs)) ++ "\n",
    foreach(
      fun(Line) -> io:format(Fmt, Line) end, LLs).

smax([Max|Ms], [Str|Strs]) ->
    N = length(Str),
    [ if N > Max -> N; true -> Max end | smax(Ms, Strs)];
smax([], []) -> [].

info_lines(Ss, Fs,Proto)  -> map(fun(S) -> i_line(S, Fs,Proto) end, Ss).
i_line(S, Fs, Proto)      -> map(fun(F) -> info(S, F, Proto) end, Fs).

h_line(Fs) -> map(fun(F) -> h_field(atom_to_list(F)) end, Fs).

h_field([C|Cs]) -> [upper(C) | hh_field(Cs)].

hh_field([$_,C|Cs]) -> [$\s,upper(C) | hh_field(Cs)];
hh_field([C|Cs]) -> [C|hh_field(Cs)];
hh_field([]) -> [].

upper(C) when C >= $a, C =< $z -> (C-$a) + $A;
upper(C) -> C.

    
info(S, F, Proto) ->
    case F of
	owner ->
	    case erlang:port_info(S, connected) of
		{connected, Owner} -> pid_to_list(Owner);
		_ -> " "
	    end;
	port ->
	    case erlang:port_info(S,id) of
		{id, Id}  -> integer_to_list(Id);
		undefined -> " "
	    end;
	sent ->
	    case prim_inet:getstat(S, [send_oct]) of
		{ok,[{send_oct,N}]} -> integer_to_list(N);
		_ -> " "
	    end;
	recv ->
	    case  prim_inet:getstat(S, [recv_oct]) of
		{ok,[{recv_oct,N}]} -> integer_to_list(N);
		_ -> " "
	    end;
	local_address ->
	    fmt_addr(prim_inet:sockname(S), Proto);
	foreign_address ->
	    fmt_addr(prim_inet:peername(S), Proto);
	state ->
	    case prim_inet:getstatus(S) of
		{ok,Status} -> fmt_status(Status);
		_ -> " "
	    end;
	packet ->
	    case prim_inet:getopt(S, packet) of
		{ok,Type} when is_atom(Type) -> atom_to_list(Type);
		{ok,Type} when is_integer(Type) -> integer_to_list(Type);
		_ -> " "
	    end;
	type ->
	    case prim_inet:gettype(S) of
		{ok,{_,stream}} -> "STREAM";
		{ok,{_,dgram}}  -> "DGRAM";
		_ -> " "
	    end;
	fd ->
	    case prim_inet:getfd(S) of
		{ok, Fd} -> integer_to_list(Fd);
		_ -> " "
	    end;
	module ->
	    case inet_db:lookup_socket(S) of
		{ok,Mod} -> atom_to_list(Mod);
		_ -> "prim_inet"
	    end
    end.
%% Possible flags: (sorted)
%% [accepting,bound,busy,connected,connecting,listen,listening,open]
%%
fmt_status(Flags) ->
    case lists:sort(Flags) of
	[accepting | _]               -> "ACCEPTING";
	[bound,busy,connected|_]      -> "CONNECTED*";
	[bound,connected|_]           -> "CONNECTED";
	[bound,listen,listening | _]  -> "LISTENING";
	[bound,listen | _]            -> "LISTEN";
	[bound,connecting | _]        -> "CONNECTING";
	[bound,open]                  -> "BOUND";
	[open]                        -> "IDLE";
	[]                            -> "CLOSED";
	_                             -> "????"
    end.

fmt_addr({error,enotconn}, _) -> "*:*";
fmt_addr({error,_}, _)        -> " ";
fmt_addr({ok,Addr}, Proto) ->
    case Addr of
	%%Dialyzer {0,0}            -> "*:*";
	{{0,0,0,0},Port} -> "*:" ++ fmt_port(Port, Proto);
	{{0,0,0,0,0,0,0,0},Port} -> "*:" ++ fmt_port(Port, Proto);
	{{127,0,0,1},Port} -> "localhost:" ++ fmt_port(Port, Proto);
	{{0,0,0,0,0,0,0,1},Port} -> "localhost:" ++ fmt_port(Port, Proto);
	{IP,Port} -> inet_parse:ntoa(IP) ++ ":" ++ fmt_port(Port, Proto)
    end.

fmt_port(N, Proto) ->
    case inet:getservbyport(N, Proto) of
	{ok, Name} -> Name;
	_ -> integer_to_list(N)
    end.

%% Return a list of all tcp sockets
tcp_sockets() -> port_list("tcp_inet").
udp_sockets() -> port_list("udp_inet").

%% Return all port having the name 'Name'
port_list(Name) ->
    filter(
      fun(Port) ->
	      case erlang:port_info(Port, name) of
		  {name, Name} -> true;
		  _ -> false
	      end
      end, erlang:ports()).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  utils
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

format_error(exbadport) -> "invalid port state";
format_error(exbadseq) ->  "bad command sequence";
format_error(Tag) ->
    erl_posix_msg:message(Tag).

%% Close a TCP socket.
tcp_close(S) when is_port(S) ->
    %% if exit_on_close is set we must force a close even if remotely closed!!!
    prim_inet:close(S),
    receive {tcp_closed, S} -> ok after 0 -> ok end.

%% Close a UDP socket.
udp_close(S) when is_port(S) ->
    receive 
	{udp_closed, S} -> ok
    after 0 ->
	    prim_inet:close(S),
	    receive {udp_closed, S} -> ok after 0 -> ok end
    end.

%% Set controlling process for TCP socket.
tcp_controlling_process(S, NewOwner) when is_port(S), is_pid(NewOwner) ->
    case erlang:port_info(S, connected) of
	{connected, Pid} when Pid =/= self() ->
	    {error, not_owner};
	undefined ->
	    {error, einval};
	_ ->
	    case prim_inet:getopt(S, active) of
		{ok, A0} ->
		    prim_inet:setopt(S, active, false),
		    case tcp_sync_input(S, NewOwner, false) of
			true ->
			    %%  %% socket already closed, 
			    ok;
			false ->
			    case catch erlang:port_connect(S, NewOwner) of
				true -> 
				    unlink(S), %% unlink from port
				    prim_inet:setopt(S, active, A0),
				    ok;
				{'EXIT', Reason} -> 
				    {error, Reason}
			    end
		    end;
		Error ->
		    Error
	    end
    end.

tcp_sync_input(S, Owner, Flag) ->
    receive
	{tcp, S, Data} ->
	    Owner ! {tcp, S, Data},
	    tcp_sync_input(S, Owner, Flag);
	{tcp_closed, S} ->
	    Owner ! {tcp_closed, S},
	    tcp_sync_input(S, Owner, true);
	{S, {data, Data}} ->
	    Owner ! {S, {data, Data}},
	    tcp_sync_input(S, Owner, Flag);	    
	{inet_async, S, Ref, Status} ->
	    Owner ! {inet_async, S, Ref, Status},
	    tcp_sync_input(S, Owner, Flag);
	{inet_reply, S, Status} ->
	    Owner ! {inet_reply, S, Status},
	    tcp_sync_input(S, Owner, Flag)
    after 0 -> 
	    Flag
    end.

%% Set controlling process for UDP or SCTP socket.
udp_controlling_process(S, NewOwner) when is_port(S), is_pid(NewOwner) ->
    case erlang:port_info(S, connected) of
	{connected, Pid} when Pid =/= self() ->
	    {error, not_owner};
	_ ->
	    {ok,A0} = prim_inet:getopt(S, active),
	    prim_inet:setopt(S, active, false),
	    case udp_sync_input(S, NewOwner, false) of
		false ->
		    case catch erlang:port_connect(S, NewOwner) of
			true -> 
			    unlink(S),
			    prim_inet:setopt(S, active, A0),
			    ok;
			{'EXIT', Reason} -> 
			    {error, Reason}
		    end;
		true ->
		    ok
	    end
    end.

udp_sync_input(S, Owner, Flag) ->
    receive
	{sctp, S, _, _, _}=Msg    -> udp_sync_input(S, Owner, Flag, Msg);
	{udp, S, _, _, _}=Msg     -> udp_sync_input(S, Owner, Flag, Msg);
	{udp_closed, S}=Msg       -> udp_sync_input(S, Owner, Flag, Msg);
	{S, {data,_}}=Msg         -> udp_sync_input(S, Owner, Flag, Msg);
	{inet_async, S, _, _}=Msg -> udp_sync_input(S, Owner, Flag, Msg);
	{inet_reply, S, _}=Msg    -> udp_sync_input(S, Owner, Flag, Msg)
    after 0 -> 
	    Flag
    end.

udp_sync_input(S, Owner, Flag, Msg) ->
    Owner ! Msg,
    udp_sync_input(S, Owner, Flag).

start_timer(infinity) -> false;
start_timer(Timeout) -> 
    erlang:start_timer(Timeout, self(), inet).

timeout(false) -> infinity;
timeout(Timer) ->
    case erlang:read_timer(Timer) of
	false -> 0;
	Time  -> Time
    end.

timeout(Time, false) -> Time;
timeout(Time, Timer) ->
    TimerTime = timeout(Timer),
    if TimerTime < Time -> TimerTime;
       true -> Time
    end.
    
stop_timer(false) -> false;
stop_timer(Timer) ->
    case erlang:cancel_timer(Timer) of
	false ->
	    receive
		{timeout,Timer,_} -> false
	    after 0 ->
		    false
	    end;
	T -> T
    end.

