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
%% Purpose: Help functions for handling the SSL-Record protocol 
%% 
%%----------------------------------------------------------------------

-module(ssl_record).

-include("ssl_record.hrl").
-include("ssl_internal.hrl").
-include("ssl_alert.hrl").
-include("ssl_handshake.hrl").
-include("ssl_debug.hrl").

%% Connection state handling
-export([init_connection_states/1, 
         current_connection_state/2, pending_connection_state/2,
         update_security_params/3,
         set_mac_secret/4,
	 set_master_secret/2, get_master_secret/1, get_pending_master_secret/1,
         activate_pending_connection_state/2,
         increment_sequence_number/2, update_cipher_state/3,
         set_pending_cipher_state/4,
         update_compression_state/3]).

%% Handling of incoming data
-export([get_tls_records/2, compress/3, uncompress/3, cipher/2, decipher/2]).

%% Encoding records
-export([encode_handshake/3, encode_alert_record/3,
	 encode_change_cipher_spec/2, encode_data/3]).

%% Decoding
-export([decode_cipher_text/2]).

%% Misc.
-export([protocol_version/1, lowest_protocol_version/2,
	 highest_protocol_version/1, supported_protocol_versions/0,
	 highest_protocol_version/0, is_acceptable_version/1]).

-export([compressions/0]).

%%====================================================================
%% Internal application API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: init_connection_states(Role) -> #connection_states{} 
%%	Role = client | server
%%      Random = binary()
%%
%% Description: Creates a connection_states record with appropriate
%% values for the initial SSL connection setup. 
%%--------------------------------------------------------------------
init_connection_states(Role) ->
    ConnectionEnd = record_protocol_role(Role),
    Current = initial_connection_state(ConnectionEnd),
    Pending = empty_connection_state(ConnectionEnd),
    #connection_states{current_read = Current,
		       pending_read = Pending,
		       current_write = Current,
		       pending_write = Pending
                      }.

%%--------------------------------------------------------------------
%% Function: current_connection_state(States, Type) -> #connection_state{}
%%	States = #connection_states{}
%%      Type = read | write
%%
%% Description: Returns the instance of the connection_state record
%% that is currently defined as the current conection state.
%%--------------------------------------------------------------------  
current_connection_state(#connection_states{current_read = Current},
			 read) ->
    Current;
current_connection_state(#connection_states{current_write = Current},
			 write) ->
    Current.

%%--------------------------------------------------------------------
%% Function: pending_connection_state(States, Type) -> #connection_state{}
%%	States = #connection_states{}
%%      Type = read | write
%%
%% Description: Returns the instance of the connection_state record
%% that is currently defined as the pending conection state.
%%--------------------------------------------------------------------  
pending_connection_state(#connection_states{pending_read = Pending},    
			 read) ->
    Pending;
pending_connection_state(#connection_states{pending_write = Pending},
			 write) ->
    Pending.

%%--------------------------------------------------------------------
%% Function: update_security_params(Params, States) -> 
%%                                                     #connection_states{}
%%      Params = #security_parameters{}
%%	States = #connection_states{}
%%
%% Description: Creates a new instance of the connection_states record
%% where the pending states gets its security parameters
%% updated to <Params>.
%%--------------------------------------------------------------------  
update_security_params(ReadParams, WriteParams, States = 
		       #connection_states{pending_read = Read,
					  pending_write = Write}) -> 
    States#connection_states{pending_read =
                             Read#connection_state{security_parameters = 
                                                   ReadParams},
                             pending_write = 
                             Write#connection_state{security_parameters = 
                                                    WriteParams}
                            }.
%%--------------------------------------------------------------------
%% Function: set_mac_secret(ClientWriteMacSecret,
%%                            ServerWriteMacSecret, Role, States) -> 
%%                                       #connection_states{}
%%      MacSecret = binary()
%%	States = #connection_states{}
%%	Role = server | client
%%
%% update the mac_secret field in pending connection states
%%--------------------------------------------------------------------
set_mac_secret(ClientWriteMacSecret, ServerWriteMacSecret, client, States) ->
    set_mac_secret(ServerWriteMacSecret, ClientWriteMacSecret, States);
set_mac_secret(ClientWriteMacSecret, ServerWriteMacSecret, server, States) ->
    set_mac_secret(ClientWriteMacSecret, ServerWriteMacSecret, States).

set_mac_secret(ReadMacSecret, WriteMacSecret,
	       States = #connection_states{pending_read = Read,
					   pending_write = Write}) ->
    States#connection_states{
      pending_read = Read#connection_state{mac_secret = ReadMacSecret},
      pending_write = Write#connection_state{mac_secret = WriteMacSecret}
     }.


%%--------------------------------------------------------------------
%% Function: set_master_secret(MasterSecret, States) -> 
%%                                                #connection_states{}
%%      MacSecret = 
%%	States = #connection_states{}
%%
%% Set master_secret in pending connection states
%%--------------------------------------------------------------------
set_master_secret(MasterSecret,
                  States = #connection_states{pending_read = Read,
                                              pending_write = Write}) -> 
    ReadSecPar = Read#connection_state.security_parameters,
    Read1 = Read#connection_state{
              security_parameters = ReadSecPar#security_parameters{
                                      master_secret = MasterSecret}},
    WriteSecPar = Write#connection_state.security_parameters,
    Write1 = Write#connection_state{
               security_parameters = WriteSecPar#security_parameters{
                                       master_secret = MasterSecret}},
    States#connection_states{pending_read = Read1, pending_write = Write1}.

%%--------------------------------------------------------------------
%% Function: get_master_secret(CStates) -> binary()
%%	CStates = #connection_states{}
%%
%% Get master_secret from current state
%%--------------------------------------------------------------------
get_master_secret(CStates) ->
    CS = CStates#connection_states.current_write,
    SP = CS#connection_state.security_parameters,
    SP#security_parameters.master_secret.

%%--------------------------------------------------------------------
%% Function: get_pending_master_secret(CStates) -> binary()
%%	CStates = #connection_states{}
%%
%% Get master_secret from pending state
%%--------------------------------------------------------------------
get_pending_master_secret(CStates) ->
    CS = CStates#connection_states.pending_write,
    SP = CS#connection_state.security_parameters,
    SP#security_parameters.master_secret.

%%--------------------------------------------------------------------
%% Function: activate_pending_connection_state(States, Type) -> 
%%                                                   #connection_states{} 
%%	States = #connection_states{}
%%      Type = read | write
%%
%% Description: Creates a new instance of the connection_states record
%% where the pending state of <Type> has been activated. 
%%--------------------------------------------------------------------
activate_pending_connection_state(States = 
                                  #connection_states{pending_read = Pending},
                                  read) ->
    NewCurrent = Pending#connection_state{sequence_number = 0},
    SecParams = Pending#connection_state.security_parameters,
    ConnectionEnd = SecParams#security_parameters.connection_end,
    NewPending = empty_connection_state(ConnectionEnd),
    States#connection_states{current_read = NewCurrent,
                             pending_read = NewPending
                            };

activate_pending_connection_state(States = 
                                  #connection_states{pending_write = Pending},
                                  write) ->
    NewCurrent = Pending#connection_state{sequence_number = 0},
    SecParams = Pending#connection_state.security_parameters,
    ConnectionEnd = SecParams#security_parameters.connection_end,
    NewPending = empty_connection_state(ConnectionEnd),
    States#connection_states{current_write = NewCurrent,
                             pending_write = NewPending
                            }.

%%--------------------------------------------------------------------
%% Function: increment_sequence_number(States, Type) -> #connection_states{} 
%%	States = #connection_states{}
%%      Type = read | write
%%
%% Description: Creates a new instance of the connection_states record
%% where the sequence number of the current state of <Type> has been
%% incremented.
%%--------------------------------------------------------------------
increment_sequence_number(States = #connection_states{current_read = Current},
			  read) ->
    SeqNr = Current#connection_state.sequence_number + 1,
    States#connection_states{current_read = Current#connection_state{
					      sequence_number = SeqNr
					     }};

increment_sequence_number(States = #connection_states{current_write = Current},
			  write) ->
    SeqNr = Current#connection_state.sequence_number + 1,
    States#connection_states{current_write = Current#connection_state{
					       sequence_number = SeqNr
					      }}.

%%--------------------------------------------------------------------
%% Function: update_cipher_state(CipherState, States, Type) -> 
%%                                                    #connection_states{}
%%      CipherState = #cipher_state{}
%%	States = #connection_states{}
%%      Type = read | write
%%
%% update the cipher state in the specified current connection state
%%--------------------------------------------------------------------
update_cipher_state(CipherState, 
		    States = #connection_states{current_read = Current},
		    read) ->
    States#connection_states{current_read = Current#connection_state{
					      cipher_state = CipherState
					     }};

update_cipher_state(CipherState,
		    States = #connection_states{current_write = Current},
		    write) ->
    States#connection_states{current_write = Current#connection_state{
					       cipher_state = CipherState
					      }}.


%%--------------------------------------------------------------------
%% Function: set_pending_cipher_state(States, CSCW, CSSW, Role) -> 
%%                                                #connection_states{}
%%  CSCW = CSSW = #cipher_state{}
%%	States = #connection_states{}
%%
%% set the cipher state in the specified pending connection state
%%--------------------------------------------------------------------
set_pending_cipher_state(States, CSCW, CSSW, server) ->
    set_pending_cipher_state(States, CSSW, CSCW, client);
set_pending_cipher_state(#connection_states{pending_read = PRCS,
                                            pending_write = PWCS} = States,
                         CSCW, CSSW, client) ->
    States#connection_states{
        pending_read = PRCS#connection_state{cipher_state = CSCW},
        pending_write = PWCS#connection_state{cipher_state = CSSW}}.

%%--------------------------------------------------------------------
%% Function: update_compression_state(CompressionState, States, Type) -> 
%%                                                    #connection_states{}
%%      CompressionState = #compression_state{}
%%	States = #connection_states{}
%%      Type = read | write
%%
%% Description: Creates a new instance of the connection_states record
%% where the compression state of the current state of <Type> has been
%% updated.
%%--------------------------------------------------------------------
update_compression_state(CompressionState, 
			 States = #connection_states{current_read = Current},
			 read) ->
    States#connection_states{current_read = Current#connection_state{
                                              compression_state = 
                                              CompressionState
                                             }};

update_compression_state(CompressionState,
			 States = #connection_states{current_write = Current},
			 write) ->
    States#connection_states{current_write = Current#connection_state{
                                               compression_state = 
                                               CompressionState
                                              }}.

%%--------------------------------------------------------------------
%% Function: get_tls_record(Data, Buffer) -> Result
%%      Result = {[#tls_compressed{}], NewBuffer}
%%      Data = Buffer = NewBuffer = binary()
%%
%% Description: given old buffer and new data from TCP, packs up a records
%% and returns it as a list of #tls_compressed, also returns leftover
%% data
%%--------------------------------------------------------------------
get_tls_records(Data, Buffer) ->
    get_tls_records_aux(list_to_binary([Buffer, Data]), []).

%% Matches a ssl v2 client hello message.
%% The server must be able to receive such messages, from clients that
%% are willing to use ssl v3 or higher, but have ssl v2 compatibility.
get_tls_records_aux(<<?BYTE(Byte0), ?BYTE(Byte1),
		     ?BYTE(?CLIENT_HELLO), ?BYTE(MajVer), ?BYTE(MinVer),
		     ?UINT16(CSLength), ?UINT16(0),
		     ?UINT16(CDLength), 
		     _CipherSuites:CSLength/binary, 
		     _ChallangeData:CDLength/binary, Data/binary>> = Msg, 
		    Acc) when (Byte0 bsr 7) == 1 ->
    Length = Byte0 band 2#01111111 + Byte1 - 1,
    <<?BYTE(_), ?BYTE(_), ?BYTE(_), Fragment:Length/binary, Data/binary>> = Msg,
    C = #tls_cipher_text{type = ?HANDSHAKE,
			 version = #protocol_version{major = MajVer, 
 						     minor = MinVer},
			 length = Length+3,
			 fragment = <<?BYTE(?CLIENT_HELLO), ?UINT24(Length),
				     Fragment/binary>>},
    get_tls_records_aux(Data, [C | Acc]);

get_tls_records_aux(<<?BYTE(CT), ?BYTE(MajVer), ?BYTE(MinVer),
                     ?UINT16(Length), Data:Length/binary, Rest/binary>>,
                    Acc) when CT == ?CHANGE_CIPHER_SPEC; 
			      CT == ?ALERT;
			      CT == ?HANDSHAKE; 
			      CT == ?APPLICATION_DATA ->
    C = #tls_cipher_text{type = CT,
                         version = #protocol_version{major = MajVer, 
						     minor = MinVer},
                         length = Length,
                         fragment = Data},
    get_tls_records_aux(Rest, [C | Acc]);
get_tls_records_aux(<<?BYTE(_CT), ?BYTE(_MajVer), ?BYTE(_MinVer),
                     ?UINT16(Length), _/binary>>,
                    _Acc) when Length > ?MAX_CIPHER_TEXT_LENGTH->
    error;                                        % TODO appropriate error code
get_tls_records_aux(Data, Acc) ->
    {lists:reverse(Acc), Data}.

%%--------------------------------------------------------------------
%% Function: protocol_version(Version) -> #protocol_version{}
%%     Version = atom()
%%     
%% Description: Creates a protocol version record from a version atom
%% or vice versa.
%%--------------------------------------------------------------------
protocol_version('tlsv1.1') ->
    #protocol_version{major = 3, minor = 2};
protocol_version(tlsv1) ->
    #protocol_version{major = 3, minor = 1};
protocol_version(sslv3) ->
    #protocol_version{major = 3, minor = 0};
protocol_version(sslv2) ->
    #protocol_version{major = 2, minor = 0};
protocol_version(#protocol_version{major = 3, minor = 2}) ->
    'tlsv1.1';
protocol_version(#protocol_version{major = 3, minor = 1}) ->
    tlsv1;
protocol_version(#protocol_version{major = 3, minor = 0}) ->
    sslv3;
protocol_version(#protocol_version{major = 2, minor = 0}) ->
    sslv2.
%%--------------------------------------------------------------------
%% Function: protocol_version(Version1, Version2) -> #protocol_version{}
%%     Version1 = Version2 = #protocol_version{}
%%     
%% Description: Lowes protocol version of two given versions 
%%--------------------------------------------------------------------
lowest_protocol_version(Version = #protocol_version{major = M, minor = N}, 
			#protocol_version{major = M, minor = O}) 
  when N < O ->
    Version;
lowest_protocol_version(#protocol_version{major = M, minor = _}, 
			Version = #protocol_version{major = M, minor = _}) ->
    Version;
lowest_protocol_version(Version = #protocol_version{major = M}, 
			#protocol_version{major = N}) when M < N ->
    Version;
lowest_protocol_version(_,Version) ->
    Version.
%%--------------------------------------------------------------------
%% Function: protocol_version(Versions) -> #protocol_version{}
%%     Versions = [#protocol_version{}]
%%     
%% Description: Highest protocol version present in a list
%%--------------------------------------------------------------------
highest_protocol_version(Versions) ->
    [Ver | Vers] = Versions,
    highest_protocol_version(Ver, Vers).

highest_protocol_version(Version, []) ->
    Version;
highest_protocol_version(Version = #protocol_version{major = N, 
						     minor = M}, 
			 [#protocol_version{major = N, 
					    minor = O} | Rest]) 
  when M > O ->
    highest_protocol_version(Version, Rest);
highest_protocol_version(#protocol_version{major = M, 
					   minor = _}, 
			 [Version = 
			  #protocol_version{major = M, 
					    minor = _} | Rest]) ->
    highest_protocol_version(Version, Rest);
highest_protocol_version(Version = #protocol_version{major = M}, 
			 [#protocol_version{major = N} | Rest]) 
  when M > N ->
    highest_protocol_version(Version, Rest);
highest_protocol_version(_, [Version | Rest]) ->
    highest_protocol_version(Version, Rest).

%%--------------------------------------------------------------------
%% Function: supported_protocol_versions() -> Versions
%%     Versions = [#protocol_version{}]
%%     
%% Description: Protocol versions supported
%%--------------------------------------------------------------------
supported_protocol_versions() ->
    Fun = fun(Version) ->
		  ssl_record:protocol_version(Version)
	  end,
    case application:get_env(ssl, protocol_version) of
	undefined ->
	    lists:map(Fun, ?DEFAULT_SUPPORTED_VERSIONS);
	{ok, []} ->
	    lists:map(Fun, ?DEFAULT_SUPPORTED_VERSIONS);
	{ok, Vsns} when is_list(Vsns) ->
	    lists:map(Fun, Vsns);
	{ok, Vsn} ->
	    [Fun(Vsn)]
    end.

%%--------------------------------------------------------------------
%% Function: protocol_version(Versions) -> #protocol_version{}
%%     Versions = [#protocol_version{}]
%%     
%% Description: Highest protocol version supported
%%--------------------------------------------------------------------
highest_protocol_version() ->
    highest_protocol_version(supported_protocol_versions()).

%%--------------------------------------------------------------------
%% Function: is_acceptable_version(Version) -> true | false
%%     Version = #protocol_version{}
%%     
%% Description: ssl version 2 is not acceptable security risks are too big.
%%--------------------------------------------------------------------
is_acceptable_version(#protocol_version{major = N}) 
  when N >= ?LOWEST_MAJOR_SUPPORTED_VERSION ->
    true;
is_acceptable_version(_) ->
    false.

%%--------------------------------------------------------------------
%% Function: random() -> 32-bytes binary()
%%     
%% Description: generates a random binary for the hello-messages
%%--------------------------------------------------------------------
random() ->
    Secs_since_1970 = calendar:datetime_to_gregorian_seconds(
			calendar:universal_time()) - 62167219200,
    Random_28_bytes = crypto:rand_bytes(28),
    <<?UINT32(Secs_since_1970), Random_28_bytes/binary>>.

%%--------------------------------------------------------------------
%% Function: compressions() -> binary()
%%     
%% Description: return a list of compressions supported (currently none)
%%--------------------------------------------------------------------
compressions() ->
    [?byte(?NULL)].

%%--------------------------------------------------------------------
%% Function: uncompress(Method, #tls_compressed{}, CompressionState)
%%           -> {#tls_plain_text, NewCompState}
%%     
%% expand compressed data using given compression
%%--------------------------------------------------------------------
uncompress(?NULL, #tls_compressed{type = Type,
                                  version = Version,
                                  length = Length,
                                  fragment = Fragment}, CS) ->
    {#tls_plain_text{type = Type,
                     version = Version,
                     length = Length,
                     fragment = Fragment}, CS}.


%%--------------------------------------------------------------------
%% Function: compress(Method, #tls_plain_text{}, CompressionState)
%%           -> {#tls_compressed, NewCompState}
%%     
%% compress data using given compression
%%--------------------------------------------------------------------
compress(?NULL, #tls_plain_text{type = Type,
                                version = Version,
                                length = Length,
                                fragment = Fragment}, CS) ->
    {#tls_compressed{type = Type,
                     version = Version,
                     length = Length,
                     fragment = Fragment}, CS}.

%%--------------------------------------------------------------------
%% Function: cipher(Method, #tls_compressed{}, ConnectionState)
%%                  {#tls_cipher_text, NewConnectionState}
%%
%%
%%--------------------------------------------------------------------
cipher(#tls_compressed{type = Type, version = Version,
		       length = Length, fragment = Fragment}, CS0) ->
    {Hash, CS1} = hash_and_bump_seqno(CS0, Type, Version, Length, Fragment),
    SP = CS1#connection_state.security_parameters,
    CipherS0 = CS1#connection_state.cipher_state,
    BCA = SP#security_parameters.bulk_cipher_algorithm,
    ?DBG_HEX(Fragment),
    {Ciphered, CipherS1} = ssl_cipher:cipher(BCA, CipherS0, Hash, Fragment),
    ?DBG_HEX(Ciphered),
    CS2 = CS1#connection_state{cipher_state=CipherS1},
    {#tls_cipher_text{type = Type,
                      version = Version,
                      length = erlang:iolist_size(Ciphered),
                      cipher = BCA, %% TODO, kolla om det är BCA det ska vara...
                      fragment = Ciphered}, CS2}.

%%--------------------------------------------------------------------
%% Function: decipher(Method, #tls_cipher_text{}, ConnectionState)
%%           -> {#tls_compressed, NewConnectionState}
%%
%%
%%--------------------------------------------------------------------
decipher(#tls_cipher_text{type = Type,
                          version = Version,
                          length = Length,
                          cipher = _Cipher,
                          fragment = Fragment}, CS)
  when Type == ?CHANGE_CIPHER_SPEC ->
    %% These are never encrypted
    {#tls_compressed{type = Type,
                     version = Version,
                     length = Length,
                     fragment = erlang:iolist_to_binary(Fragment)}, CS};                          
decipher(#tls_cipher_text{type = Type,
                          version = Version,
                          %%length = Length,
                          cipher = _Cipher,
                          fragment = Fragment}, CS0) ->
    SP = CS0#connection_state.security_parameters,
    BCA = SP#security_parameters.bulk_cipher_algorithm, % eller Cipher?
    HashSz = SP#security_parameters.hash_size,
    CipherS0 = CS0#connection_state.cipher_state,
    {T, Mac, CipherS1} = ssl_cipher:decipher(BCA, HashSz, CipherS0, Fragment),
    CS1 = CS0#connection_state{cipher_state = CipherS1},
    TLength = size(T),
    {Hash, CS2} = hash_and_bump_seqno(CS1, Type, Version, TLength, Fragment),
    ok = check_hash(Hash, Mac),
    {#tls_compressed{type = Type,
                     version = Version,
                     length = TLength,
                     fragment = T}, CS2}.

check_hash(_, _) ->
    ok. %% TODO kolla också

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

initial_connection_state(ConnectionEnd) ->
    #connection_state{security_parameters =
                      initial_security_params(ConnectionEnd),
                      sequence_number = 0
                     }.

initial_security_params(ConnectionEnd) ->
    #security_parameters{connection_end = ConnectionEnd,
                         bulk_cipher_algorithm = ?NULL,
                         mac_algorithm = ?NULL,         
                         compression_algorithm = ?NULL,
                         cipher_type = ?NULL
                        }.

empty_connection_state(ConnectionEnd) ->
    SecParams = empty_security_params(ConnectionEnd),
    #connection_state{security_parameters = SecParams}.

empty_security_params(ConnectionEnd = ?CLIENT) ->
    #security_parameters{connection_end = ConnectionEnd,
                         client_random = random()};
empty_security_params(ConnectionEnd = ?SERVER) ->
    #security_parameters{connection_end = ConnectionEnd,
                         server_random = random()}.

record_protocol_role(client) ->
    ?CLIENT;
record_protocol_role(server) ->
    ?SERVER.

split_bin(Bin, ChunkSize) ->
    split_bin(Bin, ChunkSize, []).

split_bin(<<>>, _, Acc) ->
    lists:reverse(Acc);
split_bin(Bin, ChunkSize, Acc) ->
    case Bin of
        <<Chunk:ChunkSize/binary, Rest/binary>> ->
            split_bin(Rest, ChunkSize, [Chunk | Acc]);
        _ ->
            lists:reverse(Acc, [Bin])
    end.

encode_data(Frag, Version, ConnectionStates) ->
    Bin = erlang:iolist_to_binary(Frag),
    Data = split_bin(Bin, ?MAX_PLAIN_TEXT_LENGTH-2048),
    {CS1, Acc} = 
        lists:foldl(fun(B, {CS0, Acc}) ->
			    T = #tls_plain_text{type = ?APPLICATION_DATA, 
						version = Version,
						length = size(B), 
						fragment = B},
			    {ET, CS1} = encode_plain_text(T, CS0),
			    {CS1, [ET | Acc]}
		    end, {ConnectionStates, []}, Data),
    {lists:reverse(Acc), CS1}.

encode_handshake(Frag, Version, ConnectionStates) ->
    PT = #tls_plain_text{type = ?HANDSHAKE,
                         version = Version,
                         length = erlang:iolist_size(Frag),
                         fragment = Frag},
    encode_plain_text(PT, ConnectionStates).

encode_alert_record(#alert{level = Level, description = Description},
                    Version, ConnectionStates) ->
    PT = #tls_plain_text{type = ?ALERT,
                         version = Version,
                         length = 2,
                         fragment = <<?BYTE(Level), ?BYTE(Description)>>},
    encode_plain_text(PT, ConnectionStates).

encode_change_cipher_spec(Version, ConnectionStates) ->
    PT = #tls_plain_text{type = ?CHANGE_CIPHER_SPEC,
                         version = Version,
                         length = 1,
                         fragment = [1]},
    encode_plain_text(PT, ConnectionStates).

encode_plain_text(PT, ConnectionStates) ->
    CS0 = ConnectionStates#connection_states.current_write,
    CompS0 = CS0#connection_state.compression_state,
    SecParams = (CS0#connection_state.security_parameters),
    CompAlg = SecParams#security_parameters.compression_algorithm,
    {Comp, CompS1} = compress(CompAlg, PT, CompS0),
    CS1 = CS0#connection_state{compression_state = CompS1},
    {CipherText, CS2} = cipher(Comp, CS1),
    CTBin = encode_tls_cipher_text(CipherText),
    {CTBin, ConnectionStates#connection_states{current_write = CS2}}.

encode_tls_cipher_text(#tls_cipher_text{type = Type,
                                        version = Version,
                                        length = Length,
                                        fragment = Fragment}) ->
    #protocol_version{major = MajVer, minor = MinVer} = Version,
    [?byte(Type), ?byte(MajVer), ?byte(MinVer), ?uint16(Length), Fragment].

decode_cipher_text(CipherText, CSs0) ->
    CR0 = CSs0#connection_states.current_read,
    #connection_state{compression_state = CompressionS0,
		      security_parameters = SP} = CR0,
    CA = SP#security_parameters.compression_algorithm,
    {Compressed, CR1} = decipher(CipherText, CR0),
    {Plain, CompressionS1} = uncompress(CA, Compressed, CompressionS0),
    CSs1 = CSs0#connection_states{
	     current_read = CR1#connection_state{
			      compression_state = CompressionS1}},
    {Plain, CSs1}.

hash_and_bump_seqno(#connection_state{sequence_number = SeqNo,
					       mac_secret = MacSecret,
					       security_parameters = 
					       SecPars} = CS0,
		    Type, Version, Length, Fragment) ->
    Hash = ssl_cipher:mac_hash(SecPars#security_parameters.mac_algorithm,
			       Version, MacSecret, SeqNo, Type,
			       Length, Fragment),
    {Hash, CS0#connection_state{sequence_number = SeqNo+1}}.
