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
%%-----------------------------------------------------------------
%% File: cdr_decode.erl
%% 
%% Description:
%%    This file contains all decoding functions for the CDR
%%    format.
%%
%% Creation date: January 15, 1997
%%
%%-----------------------------------------------------------------
-module(cdr_decode).

-include_lib("orber/src/orber_iiop.hrl").
-include_lib("orber/include/ifr_types.hrl").
-include_lib("orber/include/corba.hrl").
-include_lib("orber/src/orber_debug.hrl").

-include_lib("orber/src/ifr_objects.hrl").

%%-----------------------------------------------------------------
%% External exports
%%-----------------------------------------------------------------
-export([dec_giop_message_header/1, dec_reply_header/4,
	 dec_reply_body/6, dec_locate_reply_header/4, 
	 dec_locate_reply_body/5, dec_message_header/2, dec_request_body/6,
	 dec_octet_sequence_bin/6, dec_message/2]).

%%-----------------------------------------------------------------
%% Functions which only are exported for the testcases.
%%-----------------------------------------------------------------
-export([dec_type/5, dec_byte_order/1, dec_system_exception/4, dec_user_exception/4,
	 dec_byte_order_list/1]).

%%-----------------------------------------------------------------
%% Internal exports
%%-----------------------------------------------------------------

%%-----------------------------------------------------------------
%% Macros
%%-----------------------------------------------------------------
-define(DEBUG_LEVEL, 9).


%%-----------------------------------------------------------------
%% Func: dec_message/3
%% Args: 
%%       TypeCodes - is the type_codes of the return value and out parameters
%%                   when one decodes a reply.
%%       Bytes - is the the message as a byte sequence.
%% Returns: 
%%       A tupple which contains the decoded message,
%%       {ok, Header, Parameters, TypeCodes}.
%%-----------------------------------------------------------------
dec_message(TypeCodes, Bytes) ->
    Message = dec_giop_message_header(Bytes),
    ?PRINTDEBUG2("GIOP header: ~w", [Message]),
    case Message#giop_message.message_type of
        'request' ->
            {Version, ReqHdr, Rest, Len, ByteOrder} = 
		dec_request_header(Message#giop_message.giop_version,
				   Message#giop_message.message, ?GIOP_HEADER_SIZE, 
				   Message#giop_message.byte_order, Bytes),
	    dec_request_body(Version, ReqHdr, Rest, Len, ByteOrder, Bytes);
        'reply' ->
            dec_reply(Message#giop_message.giop_version,
                      TypeCodes, Message#giop_message.message, ?GIOP_HEADER_SIZE,
                      Message#giop_message.byte_order);
        'cancel_request' ->
            dec_cancel_request(Message#giop_message.giop_version,
                               Message#giop_message.message, ?GIOP_HEADER_SIZE, 
                               Message#giop_message.byte_order);
        'locate_request' ->
            dec_locate_request(Message#giop_message.giop_version,
                               Message#giop_message.message, ?GIOP_HEADER_SIZE, 
                               Message#giop_message.byte_order);
        'locate_reply' ->
            dec_locate_reply(Message#giop_message.giop_version,
                             Message#giop_message.message, ?GIOP_HEADER_SIZE, 
                             Message#giop_message.byte_order);
        'close_connection' ->
            'close_connection';
        'message_error' ->
            'message_error';
        'fragment' ->
            'fragment'
    end.

%%-----------------------------------------------------------------
%% Func: dec_giop_message_header/1
%% Args: 
%%       Bytes - is the the message as a byte sequence.
%% Returns: 
%%       A giop_message record.
%%-----------------------------------------------------------------
dec_giop_message_header(<<"GIOP",Major:8,Minor:8,ByteOrderData:8,MessType:8,
			Rest/binary>>) ->
    Version = {Major, Minor},
    ByteOrder = 
	if
	    Version == {1,0} ->
		check_byte_order(ByteOrderData);
	    true ->
		dec_flags(ByteOrderData)
	end,
    %% We know that this long integer is aligned because of the 
    %% fix header structure.
    {MessSize, Message} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    #giop_message{magic = "GIOP", giop_version = Version, 
		  byte_order = ByteOrder, message_type = dec_giop_msg_type(MessType), 
		  message_size = MessSize, message = Message};
dec_giop_message_header(_) ->
    exit(message_error).

%%-----------------------------------------------------------------
%% Func: dec_message_header/2
%% Args: 
%%       Header - #giop_message{}
%%       Bytes - is the the message body as a byte sequence.
%% Returns: 
%%-----------------------------------------------------------------
dec_message_header(TypeCodes, Bytes) ->
    Message = dec_giop_message_header(Bytes),
    ?PRINTDEBUG2("GIOP header: ~w", [Message]),
    case Message#giop_message.message_type of
	'request' ->
	    dec_request_header(Message#giop_message.giop_version,
			       Message#giop_message.message, ?GIOP_HEADER_SIZE, 
			       Message#giop_message.byte_order, Bytes);
	'reply' ->
	    dec_reply(Message#giop_message.giop_version,
		      TypeCodes, Message#giop_message.message, ?GIOP_HEADER_SIZE,
		      Message#giop_message.byte_order);
	'cancel_request' ->
	    dec_cancel_request(Message#giop_message.giop_version,
			       Message#giop_message.message, ?GIOP_HEADER_SIZE, 
			       Message#giop_message.byte_order);
	'locate_request' ->
	    dec_locate_request(Message#giop_message.giop_version,
			       Message#giop_message.message, ?GIOP_HEADER_SIZE, 
			       Message#giop_message.byte_order);
	'locate_reply' ->
	    dec_locate_reply(Message#giop_message.giop_version,
			     Message#giop_message.message, ?GIOP_HEADER_SIZE, 
			     Message#giop_message.byte_order);
	'close_connection' ->
	    'close_connection';
	'message_error' ->
	    'message_error';
	'fragment' ->
	    'fragment'
    end.


%%-----------------------------------------------------------------
%% Func: dec_byte_order/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {Endianess, Rest} where Endianess is big or little.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_byte_order(<<0:8,T/binary>>) ->
    {big, T};
dec_byte_order(<<1:8,T/binary>>) ->
    {little, T}.

%%-----------------------------------------------------------------
%% Func: dec_byte_order_list/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {Endianess, Rest} where Endianess is big or little.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_byte_order_list([0|T]) ->
    {big, T};
dec_byte_order_list([1|T]) ->
    {little, T}.



%%-----------------------------------------------------------------
%% Func: check_byte_order/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {Endianess, Rest} where Endianess is big or little.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
check_byte_order(0) ->
    big;
check_byte_order(1) ->
    little.

%%-----------------------------------------------------------------
%% Func: dec_flags/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {Endianess, Rest} where Endianess is big or little.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_flags(0) ->
    %% Eq. to 00000000
    big;
dec_flags(1) ->
    %% Eq. to 00000001
    little;
dec_flags(X) ->
    %% Not only the Endian flag is set, test which.
    if
	((X band 16#02) == 16#02) ->
	    orber:debug_level_print("[~p] cdr_decode:dec_flags(~p); Fragmented Messages not supported.", 
				    [?LINE, X], ?DEBUG_LEVEL),
	    corba:raise(#'MARSHAL'{minor=103, completion_status=?COMPLETED_MAYBE});
	%% Since the 6 most significant bits are unused we'll accept this for now.
	((X band 16#01) == 16#01) ->
	    little;
	true ->
	    big
    end.

%%-----------------------------------------------------------------
%% Func: dec_giop_msg_type
%% Args: 
%%       An integer message type code
%% Returns: 
%%       An atom which is the message type code name
%%-----------------------------------------------------------------
dec_giop_msg_type(0) ->
    'request';
dec_giop_msg_type(1) ->
    'reply';
dec_giop_msg_type(2) ->
    'cancel_request';
dec_giop_msg_type(3) ->
    'locate_request';
dec_giop_msg_type(4) ->
    'locate_reply';
dec_giop_msg_type(5) ->
    'close_connection';
dec_giop_msg_type(6) ->
    'message_error';
dec_giop_msg_type(7) ->
    'fragment'.

%%-----------------------------------------------------------------
%% Func    : dec_response_flags
%% Args    : 
%% Returns : boolean
%%-----------------------------------------------------------------
%% FIX ME!! Not correct flag handling.
dec_response_flags(Version, <<0:8, Rest/binary>>, Len) ->
    {false, Rest, Len+1};
dec_response_flags(Version, <<1:8, Rest/binary>>, Len) ->
    {true_oneway, Rest, Len+1};
dec_response_flags(Version, <<3:8, Rest/binary>>, Len) ->
    {true, Rest, Len+1};
dec_response_flags(Version, <<X:8, Rest/binary>>, Len) ->
    %% Not only the Response flag is set, test which.
    if
	%% Since the 6 most significant bits are unused we'll accept this for now.
	((X band 16#03) == 16#03) ->
	    {true, Rest, Len+1};
	((X band 16#01) == 16#01) ->
	    {true_oneway, Rest, Len+1};
	true ->
	    {false, Rest, Len+1}
    end.

%%-----------------------------------------------------------------
%% Func    : dec_target_addr
%% Args    : Octet
%% Returns : boolean
%%-----------------------------------------------------------------
dec_target_addr(Version, Message, Len, ByteOrder) ->
    case dec_type(?TARGETADDRESS, Version, Message, Len, ByteOrder, [], 0) of
	{#'GIOP_TargetAddress'{label = 0, value = KeyAddr}, Rest3, Len3, C} ->
	    {corba:string_to_objkey(KeyAddr), Rest3, Len3, C};
	{#'GIOP_TargetAddress'{label = 1, 
			       value = #'IOP_TaggedProfile'{tag=?TAG_INTERNET_IOP,
							    profile_data=PA}}, 
	 Rest3, Len3, C} ->
	    {corba:string_to_objkey(PA), Rest3, Len3, C};
	{#'GIOP_TargetAddress'{label = 2,
			       value = #'GIOP_IORAddressingInfo'{
				 selected_profile_index = PI,
				 ior = IOR}}, Rest3, Len3, C} ->
	    {corba:string_to_objkey(iop_ior:get_objkey(IOR)), Rest3, Len3, C};
	Other ->
	    orber:debug_level_print("[~p] cdr_decode:dec_target_addr(~p); Unsupported TargetAddress.", 
				    [?LINE, Other], ?DEBUG_LEVEL),
	    corba:raise(#'MARSHAL'{minor=103, completion_status=?COMPLETED_MAYBE})
    end.

%%-----------------------------------------------------------------
%% Func: dec_request_header/3
%% Args: 
%%       Message - The message
%%       Len0 - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%-----------------------------------------------------------------
dec_request_header(Version, Message, Len0, ByteOrder, Buffer) when Version == {1,2} ->
    {Request_id, Rest1, Len1, _} = dec_type('tk_ulong', Version, Message, Len0, 
					    ByteOrder, [], 0),
    {ResponseFlags, Rest2, Len2} = dec_response_flags(Version, Rest1, Len1),
    {_, Rest2b, Len2b, _} = dec_type({'tk_array', 'tk_octet', 3}, Version, Rest2, Len2, ByteOrder, [], 0),
    {Object_key, Rest3, Len3, _} = dec_target_addr(Version, Rest2b, Len2b, ByteOrder),
    {Operation, Rest4, Len4, _} = dec_type({'tk_string', 0},  Version, Rest3, Len3, ByteOrder, [], 0),
    {Context, Rest5, Len5} = dec_service_context(Version, Rest4, Len4, ByteOrder),
    {Version, #request_header{service_context=Context, 
			      request_id=Request_id,
			      response_expected=ResponseFlags,
			      object_key=Object_key,
			      operation=Operation, 
			      requesting_principal=""}, Rest5, Len5, ByteOrder};
dec_request_header(Version, Message, Len0, ByteOrder, Buffer) ->
    {Context, Rest1, Len1} = dec_service_context(Version, Message, Len0, ByteOrder),
    {Request_id, Rest2, Len2, _} = dec_type('tk_ulong', Version, Rest1, Len1, ByteOrder, [], 0),
    {Response_expected, Rest3, Len3, _} = dec_type('tk_boolean',  Version, Rest2, Len2,
						   ByteOrder, [], 0),
    {ObjKey, Rest4, Len4, _} = dec_type({'tk_sequence', 'tk_octet', 0},  Version, Rest3,
				   Len3, ByteOrder, [], 0),
    Object_key = corba:string_to_objkey(ObjKey),
    {Operation, Rest5, Len5, _} = dec_type({'tk_string', 0},  Version, Rest4, Len4, ByteOrder, [], 0),
    {Principal, Rest, Len, _} = dec_type({'tk_string', 0},  Version, Rest5,Len5,  ByteOrder, [], 0),
    {Version, #request_header{service_context=Context, 
			      request_id=Request_id,
			      response_expected=Response_expected,
			      object_key=Object_key,
			      operation=Operation, 
			      requesting_principal=Principal}, Rest, Len, ByteOrder}.


%%-----------------------------------------------------------------
%% Func: dec_service_context/4
%% Args: Version - e.g. 1.2
%%       Message - The message
%%       Len - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%-----------------------------------------------------------------
dec_service_context(Version, Message, Len, ByteOrder) ->
    {Context, Rest, Len1} = dec_type(?IOP_SERVICECONTEXT, Version, Message, 
				     Len, ByteOrder),
    {dec_used_contexts(Version, Context, []), Rest, Len1}.

dec_used_contexts(Version, [], Ctxs) ->
    Ctxs;
dec_used_contexts({1,0}, [#'IOP_ServiceContext'{context_id=?IOP_CodeSets}|T], Ctxs) ->
    %% Not supported by 1.0, drop it.
    dec_used_contexts({1,0}, T, Ctxs);
dec_used_contexts(Version, [#'IOP_ServiceContext'{context_id=?IOP_CodeSets,
						  context_data = Bytes}|T], Ctxs) ->
    {ByteOrder, Rest} = dec_byte_order(list_to_binary(Bytes)),
    {CodeCtx, _, _} =  dec_type(?CONV_FRAME_CODESETCONTEXT, Version, 
				Rest, 1, ByteOrder),
    dec_used_contexts(Version, T, [CodeCtx|Ctxs]);
dec_used_contexts(Version, [H|T], Ctxs) ->
    dec_used_contexts(Version, T, [H|Ctxs]).

%%-----------------------------------------------------------------
%% Func: dec_request_body
%% Args: Version - e.g. 1.2
%% Returns: 
%%-----------------------------------------------------------------
dec_request_body(Version, ReqHdr, Rest, Len, ByteOrder, Buffer) ->
    set_codeset_data(ReqHdr#request_header.service_context),
    {Parameters, TypeCodes, _} = 
	dec_request_body(Version, ReqHdr#request_header.object_key, 
			 ReqHdr#request_header.operation, 
			 Rest, Len, ByteOrder, Buffer, Len),
    {Version, ReqHdr, Parameters, TypeCodes}.

dec_request_body(Version, Object_key, Operation, Body, Len, ByteOrder, Buffer, Counter) 
  when Version == {1,2} ->
    case orber_typedefs:get_op_def(Object_key, Operation) of
	{RetType, [], OutParameters} ->
	    {[], {RetType, [], OutParameters}, Len};
	{RetType, InParameters, OutParameters} ->
	    {Rest, Len1, NewC} = dec_align(Body, Len, 8, Counter),
	    {Parameters, Len2} = dec_parameters(Version, InParameters, Rest, Len1, 
						ByteOrder, Buffer, NewC),
	    {Parameters, {RetType, InParameters, OutParameters}, Len2}
    end;
dec_request_body(Version, Object_key, Operation, Body, Len, ByteOrder, Buffer, Counter) ->
    {RetType, InParameters, OutParameters} =
	orber_typedefs:get_op_def(Object_key, Operation),
    {Parameters, Len1} = dec_parameters(Version, InParameters, Body, Len, ByteOrder, Buffer, Counter),
    {Parameters, {RetType, InParameters, OutParameters}, Len1}.

dec_parameters(_, [], _, Len, _, _, _) ->
    {[], Len};
dec_parameters(Version, [P1 |InParList], Body, Len, ByteOrder, Buffer, Counter) ->
    {Object, Rest, Len1, NewCounter} = dec_type(P1, Version, Body, Len, ByteOrder, Buffer, Counter),
    {List, Len2} = dec_parameters(Version, InParList, Rest, Len1, ByteOrder, Buffer, NewCounter),
    {[Object | List], Len2}.

set_codeset_data([]) ->
    put(char, ?ISO8859_1_ID),
    put(wchar, ?ISO_10646_UCS_2_ID);
set_codeset_data([#'CONV_FRAME_CodeSetContext'{char_data=?ISO8859_1_ID,
					       wchar_data=?ISO_10646_UCS_2_ID}|T]) ->
    put(char, ?ISO8859_1_ID),
    put(wchar, ?ISO_10646_UCS_2_ID);
set_codeset_data([#'CONV_FRAME_CodeSetContext'{char_data=Char,
					       wchar_data=Wchar}|T]) ->
    %% Should not raise an exception here since we don't know if operations using
    %% wchar/wstring will be used.
    put(char, Char),
    put(wchar, Wchar);
set_codeset_data([H|T]) ->
    set_codeset_data(T).

%%-----------------------------------------------------------------
%% Func: dec_reply/5
%% Args: 
%%       Message - The message
%%       Len0 - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%       A tuple {ReplyHeader, Result} where ReplyHeader is a
%%       reply_header record and Result the decode result.
%%-----------------------------------------------------------------
dec_reply(Version, TypeCodes, Message, Len0, ByteOrder) ->
    {ReplyHeader, Rest, Len} = dec_reply_header(Version, Message, Len0, ByteOrder),
    {Result, Par} = 
	case ReplyHeader#reply_header.reply_status of
	    'no_exception' ->
		{R, P, _} = dec_reply_body(Version, TypeCodes, Rest, Len, ByteOrder, Message),
		{R, P};
	    'system_exception' ->
		{R, _} = dec_system_exception(Version, Rest, Len, ByteOrder),
		{R, []};
	    'user_exception' ->
		{R, _} = dec_user_exception(Version, Rest, Len, ByteOrder),
		{R, []};
	    'location_forward' ->
		{R, _, _} = dec_reply_body(Version, {{'tk_objref', "", ""}, [],[]}, 
					   Rest, Len, ByteOrder, Message),
	    {R, []};
	    'location_forward_perm' ->
		{R, _, _} = dec_reply_body(Version, {{'tk_objref', "", ""}, [],[]}, 
					   Rest, Len, ByteOrder, Message),
		{R, []};
	    'needs_addressing_mode' ->
		{R, _, _} = dec_reply_body(Version, {'tk_short', [],[]}, 
					   Rest, Len, ByteOrder, Message),
		{R, []}
	     end,
    {ReplyHeader, Result, Par}.


%% ## NEW IIOP 1.2 ##
dec_reply_header(Version, Message, Len0, ByteOrder) when Version == {1,2} ->
    {Request_id, Rest1, Len1} = dec_type('tk_ulong', Version, Message, Len0, ByteOrder),
    {ReplyStatus, Rest2, Len2} = dec_reply_status(Version, Rest1, Len1, ByteOrder),
    {Context, Rest, Len3} = dec_service_context(Version, Rest2, Len2, ByteOrder),
    {#reply_header{service_context=Context, request_id=Request_id, reply_status=ReplyStatus},
     Rest, Len3};

dec_reply_header(Version, Message, Len0, ByteOrder) ->
    {Context, Rest1, Len1} = dec_service_context(Version, Message, Len0, ByteOrder),
    {Request_id, Rest2, Len2} = dec_type('tk_ulong', Version, Rest1, Len1, ByteOrder),
    {ReplyStatus, Rest, Len3} = dec_reply_status(Version, Rest2, Len2, ByteOrder),
    {#reply_header{service_context=Context, request_id=Request_id, reply_status=ReplyStatus},
     Rest, Len3}.

dec_reply_status(Version, Status, Len, ByteOrder) ->
    {L, Rest, Len1}= dec_type('tk_ulong', Version, Status, Len, ByteOrder),
    {dec_giop_reply_status_type(L), Rest, Len1}.

dec_reply_body(_, {'tk_void', _, []}, <<>>, Len, _, _) ->
    %% This case is mainly to be able to avoid removing non-existent alignment for
    %% IIOP-1.2 messages if the body should be empty, i.e., void return value and
    %% no out parameters.
    {ok, [], Len};
dec_reply_body(Version, {RetType, InParameters, OutParameters}, Body, Len, 
	       ByteOrder, Bytes) when Version == {1,2} ->
    {Rest, Len1, Counter} = dec_align(Body, Len, 8, Len),
    {Result, Rest2, Len2, C} = dec_type(RetType, Version, Rest, Len1, ByteOrder, Bytes, Counter),
    {Par, Len3} = dec_parameters(Version, OutParameters, Rest2, Len2, ByteOrder, Bytes, C),
    {Result, Par, Len3};
dec_reply_body(Version, {RetType, InParameters, OutParameters}, Body, Len, ByteOrder, Bytes) ->
    {Result, Rest, Len1, C} = dec_type(RetType, Version, Body, Len, ByteOrder, Bytes, Len),
    {Par, Len2} = dec_parameters(Version, OutParameters, Rest, Len1, ByteOrder, Bytes, C),
    {Result, Par, Len2}.


%%-----------------------------------------------------------------
%% Func: dec_cancel_request/3
%% Args: 
%%       Message - The message
%%       Len - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%       A cancel_request_header record.
%%-----------------------------------------------------------------
dec_cancel_request(Version, Message, Len, ByteOrder) ->
    {Request_id, _, _} = dec_type('tk_ulong', Version, Message, Len, ByteOrder),
    #cancel_request_header{request_id=Request_id}.

%%-----------------------------------------------------------------
%% Func: dec_locate_request/3
%% Args: 
%%       Message - The message
%%       Len - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%       A locate_request_header record.
%%-----------------------------------------------------------------
%% ## NEW IIOP 1.2 ##
dec_locate_request(Version, Message, Len, ByteOrder) when Version == {1,2} ->
    {Request_id, Rest, Len1} = dec_type('tk_ulong', Version, Message, Len, ByteOrder),
    {Object_key, _, _, _} = dec_target_addr(Version, Rest, Len1, ByteOrder),
    {Version, #locate_request_header{request_id=Request_id, object_key=Object_key}};
dec_locate_request(Version, Message, Len, ByteOrder) ->
    {Request_id, Rest, Len1} = dec_type('tk_ulong', Version, Message, Len, ByteOrder),
    {ObjKey, _, _} = dec_type({'tk_sequence', 'tk_octet', 0}, Version, Rest,
				   Len1, ByteOrder),
    Object_key = corba:string_to_objkey(ObjKey),    
    {Version, #locate_request_header{request_id=Request_id, object_key=Object_key}}.


%%-----------------------------------------------------------------
%% Func: dec_locate_reply/3
%% Args: 
%%       Message - The message
%%       Len - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%       A locate_reply_header record.
%%-----------------------------------------------------------------
dec_locate_reply(Version, Message, Len, ByteOrder) ->
    {ReplyHeader, Rest1, Len1} = dec_locate_reply_header(Version, Message, Len, ByteOrder),
    {ReplyHeader, dec_locate_reply_body(Version, ReplyHeader#locate_reply_header.locate_status, Rest1, 
					Len1, ByteOrder)}.

dec_locate_reply_header(Version, Message, Len, ByteOrder) ->
    {Request_id, Rest1, Len1} = dec_type('tk_ulong', Version, Message, Len, ByteOrder),
    {Locate_status, Rest2, Len2} = dec_locate_status(Version, Rest1, Len, ByteOrder),
    {#locate_reply_header{request_id=Request_id, locate_status=Locate_status}, Rest2, Len2}.
   
dec_locate_reply_body(Version, LocateStatus, Rest, Len, ByteOrder) 
  when Version == {1,2} ->
    case LocateStatus of
	'object_forward' ->
	    {ObjRef, _, _, _} = dec_objref(Version, Rest, Len, ByteOrder),
	    ObjRef;
	'object_forward_perm' ->
	    {ObjRef, _, _, _} = dec_objref(Version, Rest, Len, ByteOrder),
	    ObjRef;
	'loc_system_exception' ->
	    %% This should be updated but since 'dec_system_exception' removes
	    %% alignment, which the LocateReplyBody don't hyave, for 1.2 we
	    %% pretend it's 1.1 for now
	    {SysExc, _} = dec_system_exception({1,1}, Rest, Len, ByteOrder),
	    {'EXCEPTION', SysExc};
	'loc_needs_addressing_mode' ->
	    %% Not supported.
	    [];
	_ ->
	    []
    end;
dec_locate_reply_body(Version, LocateStatus, Rest, Len, ByteOrder) ->
    case LocateStatus of
	'object_forward' ->
	    {ObjRef, _, _, _} = dec_objref(Version, Rest, Len, ByteOrder),
	    ObjRef;
	_ ->
	    []
    end.

dec_locate_status(Version, Bytes, Len, ByteOrder) ->
    {L, Rest, Len1} = dec_type('tk_ulong', Version, Bytes, Len, ByteOrder),
    {dec_giop_locate_status_type(L), Rest, Len1}.

%%-----------------------------------------------------------------
%% Func: dec_giop_reply_status_type
%% Args:
%%       An integer status code
%% Returns:
%%       An atom which is the reply status
%%-----------------------------------------------------------------
dec_giop_reply_status_type(0) ->
    'no_exception';
dec_giop_reply_status_type(1) ->
    'user_exception';
dec_giop_reply_status_type(2) ->
    'system_exception';
dec_giop_reply_status_type(3) ->
    'location_forward';
%% ## NEW IIOP 1.2 ##
dec_giop_reply_status_type(4) ->
    'location_forward_perm';
dec_giop_reply_status_type(5) ->
    'needs_addressing_mode'.
 
%%-----------------------------------------------------------------
%% Func: dec_giop_locate_status_type
%% Args:
%%       An integer status code
%% Returns:
%%       An atom which is the reply status
%%-----------------------------------------------------------------
dec_giop_locate_status_type(0) ->
    'unknown_object';
dec_giop_locate_status_type(1) ->
    'object_here';
dec_giop_locate_status_type(2) ->
    'object_forward';
%% ## NEW IIOP 1.2 ##
dec_giop_locate_status_type(3) ->
    'object_forward_perm';
dec_giop_locate_status_type(4) ->
    'loc_system_exception';
dec_giop_locate_status_type(5) ->
    'loc_needs_addressing_mode'.
 

%%-----------------------------------------------------------------
%% Func: dec_type/5
%%-----------------------------------------------------------------
dec_type(Type, Version, Bytes, Len, ByteOrder) ->
    {Val, Rest, Len2, _} = 
	dec_type(Type, Version, Bytes, Len, ByteOrder, [], 0),
    {Val, Rest, Len2}.

dec_type('tk_null', Version, Bytes, Len, _, _, C) ->
    {'null', Bytes, Len, C}; 
dec_type('tk_void', Version, Bytes, Len, _, _, C) ->
    {'ok', Bytes, Len, C}; 
dec_type('tk_short', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
    {Short, Rest1} = cdrlib:dec_short(ByteOrder, Rest),
    {Short, Rest1, Len1 + 2, NewC+2};
dec_type('tk_long', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Long, Rest1} = cdrlib:dec_long(ByteOrder, Rest),
    {Long, Rest1, Len1 + 4, NewC+4};
dec_type('tk_longlong', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 8, C),
    {Long, Rest1} = cdrlib:dec_longlong(ByteOrder, Rest),
    {Long, Rest1, Len1 + 8, NewC+8};
dec_type('tk_ushort', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
    {Short, Rest1} = cdrlib:dec_unsigned_short(ByteOrder, Rest),
    {Short, Rest1, Len1 + 2, NewC+2};
dec_type('tk_ulong', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Long, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    {Long, Rest1, Len1 + 4, NewC+4};
dec_type('tk_ulonglong', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 8, C),
    {Long, Rest1} = cdrlib:dec_unsigned_longlong(ByteOrder, Rest),
    {Long, Rest1, Len1 + 8, NewC+8};
dec_type('tk_float', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Float, Rest1} = cdrlib:dec_float(ByteOrder, Rest),
    {Float, Rest1, Len1 + 4, NewC+4};
dec_type('tk_double', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 8, C),
    {Double, Rest1} = cdrlib:dec_double(ByteOrder, Rest),
    {Double, Rest1, Len1 + 8, NewC+8};
dec_type('tk_boolean', Version, Bytes, Len, _, _, C) ->
    {Bool, Rest} = cdrlib:dec_bool(Bytes),
    {Bool, Rest, Len + 1, C+1};
dec_type('tk_char', Version, Bytes, Len, _, _, C) ->
    {Char, Rest} = cdrlib:dec_char(Bytes),
    {Char, Rest, Len + 1, C+1};
dec_type('tk_wchar', {1,2}, Bytes, Len, ByteOrder, _, C) ->
    %% This is not correct but for now me must decode in same way as for 1.1.
    case get(wchar) of
	?ISO_10646_UCS_2_ID ->
	    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
	    {WChar, Rest2} = cdrlib:dec_unsigned_short(ByteOrder, Rest),
	    {WChar, Rest2, Len1 + 2, NewC+2};
	_->
	    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
	    {WChar, Rest2} = cdrlib:dec_unsigned_short(ByteOrder, Rest),
	    {WChar, Rest2, Len1 + 2, NewC+2}
    end;
%% For 1.1 the wchar is limited to the use of two-octet fixed-length encoding.
dec_type('tk_wchar', Version, Bytes, Len, ByteOrder, _, C) ->
    case get(wchar) of
	?ISO_10646_UCS_2_ID ->
	    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
	    {WChar, Rest2} = cdrlib:dec_unsigned_short(ByteOrder, Rest),
	    {WChar, Rest2, Len1 + 2, NewC+2};
	_->
	    %% We should raise the DATA_CONVERSION system exception but
	    %% it's not possible since all ORB:s do not include
	    %% IOP::ServiceContext.
	    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
	    {WChar, Rest2} = cdrlib:dec_unsigned_short(ByteOrder, Rest),
	    {WChar, Rest2, Len1 + 2, NewC+2}
    end;
dec_type('tk_octet', Version, Bytes, Len, _, _, C) ->
    {Octet, Rest} = cdrlib:dec_octet(Bytes),
    {Octet, Rest, Len + 1, C+1};
dec_type('tk_any', Version, Bytes, Len, ByteOrder, Buff, C) ->
    {TypeCode, Rest1, Len1, NewC} = dec_type('tk_TypeCode', Version, Bytes, Len, ByteOrder, Buff, C),
    {Value, Rest2, Len2, NewC2} = dec_type(TypeCode, Version, Rest1, Len1, ByteOrder, Buff, NewC),
    {#any{typecode=TypeCode, value=Value}, Rest2, Len2, NewC2};
dec_type('tk_TypeCode', Version, Bytes, Len, ByteOrder, Buff, C) ->
    dec_type_code(Version, Bytes, Len, ByteOrder, Buff, C);
dec_type('tk_Principal', Version, Bytes, Len, ByteOrder, Buff, C) ->
    dec_sequence(Version, Bytes, 'tk_octet', Len, ByteOrder, Buff, C);
dec_type({'tk_objref', IFRId, Name}, Version, Bytes, Len, ByteOrder, Buff, C) -> 
    dec_objref(Version, Bytes, Len, ByteOrder, Buff, C);
dec_type({'tk_struct', IFRId, Name, ElementList}, Version, Bytes, Len, ByteOrder, Buff, C) -> 
    dec_struct(Version, IFRId, Name, ElementList, Bytes, Len, ByteOrder, Buff, C); 
dec_type({'tk_union', IFRId, Name, DiscrTC, Default, ElementList},
	 Version, Bytes, Len, ByteOrder, Buff, C) ->
    dec_union(Version, IFRId, Name, DiscrTC, Default, ElementList, Bytes, Len, ByteOrder, Buff, C);
dec_type({'tk_enum', IFRId, Name, ElementList}, Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Enum, Rest1} = cdrlib:dec_enum(ByteOrder, ElementList, Rest),
    {Enum, Rest1, Len1 + 4, NewC+4}; 
dec_type({'tk_string', MaxLength}, Version, Bytes, Len, ByteOrder, Buff, C) -> % MaxLength Not Used
    dec_string(Version, Bytes, Len, ByteOrder, Buff, C);
dec_type({'tk_wstring', MaxLength}, Version, Bytes, Len, ByteOrder, Buff, C) -> % MaxLength Not Used
    dec_wstring(Version, Bytes, Len, ByteOrder, Buff, C);
dec_type({'tk_sequence', ElemTC, MaxLength}, Version, Bytes, Len, ByteOrder, Buff, C) -> % MaxLength Not Used
    dec_sequence(Version, Bytes, ElemTC, Len, ByteOrder, Buff, C);
dec_type({'tk_array', ElemTC, Size}, Version, Bytes, Len, ByteOrder, Buff, C) ->
    dec_array(Version, Bytes, Size, ElemTC, Len, ByteOrder, Buff, C);
dec_type({'tk_alias', IFRId, Name, TC}, Version, Bytes, Len, ByteOrder, Buff, C) ->
    dec_type(TC, Version, Bytes, Len, ByteOrder, Buff, C); 
%dec_type({'tk_except', IFRId, Name, ElementList}, Version, Bytes, Len, ByteOrder) ->
dec_type(Type, _, _, _, _, _, _) ->
    orber:debug_level_print("[~p] cdr_decode:dec_type(~p)", [?LINE, Type], ?DEBUG_LEVEL),
    corba:raise(#'MARSHAL'{minor=104, completion_status=?COMPLETED_MAYBE}).

stringify_enum({tk_enum,_,_,_}, Label) ->
    atom_to_list(Label);
stringify_enum(_, Label) ->
    Label.
%%-----------------------------------------------------------------
%% Func: dec_sequence/7 and dec_sequence/8
%%-----------------------------------------------------------------
dec_sequence(Version, Message, 'tk_octet', Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    <<OctetSeq:Size/binary, Rest2/binary>> = Rest1,
    {binary_to_list(OctetSeq), Rest2, Len1+4+Size, NewC+4+Size};
dec_sequence(Version, Message, 'tk_char', Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    <<OctetSeq:Size/binary, Rest2/binary>> = Rest1,
    {binary_to_list(OctetSeq), Rest2, Len1+4+Size, NewC+4+Size};
%% We test if it's a sequence of struct's or unions. By doing this we only
%% have to look up the IFR-ID once instead of N times (N eq length of sequence).
dec_sequence(Version, Message, {'tk_struct', IFRId, ShortName, ElementList}, 
	     Len, ByteOrder, Buff, C) when IFRId /= "", ShortName /= "" ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    case  is_known_struct(ShortName) of
	true ->
	    dec_sequence_struct(Version, Rest1, Size, ElementList, Len1 + 4, 
				ByteOrder, Buff, NewC+4, ShortName);
	false ->
	    Name = ifrid_to_name(IFRId, ir_StructDef),
	    dec_sequence_struct(Version, Rest1, Size, ElementList, Len1 + 4, 
				ByteOrder, Buff, NewC+4, list_to_atom(Name))
    end;
dec_sequence(Version, Message, 
	     {'tk_union', IFRId, TCName, DiscrTC, Default, ElementList}, 
	     Len, ByteOrder, Buff, C) when TCName /= 'GIOP_TargetAddress' ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    Name = ifrid_to_name(IFRId, ir_UnionDef),
    dec_sequence_union(Version, Rest1, Size, DiscrTC, Default, ElementList, Len1 + 4,
		       ByteOrder, Buff, NewC+4, list_to_atom(Name));
dec_sequence(Version, Message, TypeCode, Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    dec_sequence(Version, Rest1, Size, TypeCode, Len1 + 4, ByteOrder, Buff, NewC+4).


dec_sequence(_, Message, 0, Type, Len, ByteOrder, Buff, C) ->
    {[], Message, Len, C};
dec_sequence(Version, Message, N, Type, Len, ByteOrder, Buff, C) ->
    {Object, Rest1, Len1, NewC} = dec_type(Type, Version, Message, Len, ByteOrder, Buff, C),
    {Seq, Rest2, Len2, NewC2} = dec_sequence(Version, Rest1, N - 1,  Type, Len1, ByteOrder, Buff, NewC),
    {[Object | Seq], Rest2, Len2, NewC2}.

dec_sequence_struct(_, Message, 0, Type, Len, ByteOrder, Buff, C, Name) ->
    {[], Message, Len, C};
dec_sequence_struct(Version, Message, N, TypeCodeList, Len, ByteOrder, Buff, C, Name) ->
    {Struct, Rest1, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {Seq, Rest2, Len2, NewC2} = dec_sequence_struct(Version, Rest1, N - 1,  TypeCodeList, Len1, ByteOrder, 
						    Buff, NewC, Name),
    {[list_to_tuple([Name |Struct]) | Seq], Rest2, Len2, NewC2}.
dec_sequence_union(_, Message, 0, DiscrTC, Default, ElementList, Len, ByteOrder, Buff, C, Name) ->
    {[], Message, Len, C};
dec_sequence_union(Version, Message, N, DiscrTC, Default, ElementList, Len, ByteOrder, Buff, C, Name) ->

    {Label, Rest1, Len1, NewC} = dec_type(DiscrTC, Version, Message, Len, ByteOrder, Buff, C),
    Result = dec_union(Version, stringify_enum(DiscrTC, Label), ElementList, Default, 
				     Rest1, Len1, ByteOrder, Buff, NewC),
    {Value, Rest2, Len2, NewC3} = case Result of
		{default, R, L, NewC2} ->
		    dec_union(Version, default, ElementList, Default, 
				     R, L, ByteOrder, Buff, NewC2);
		X ->
		    X
	    end,
    {Seq, Rest3, Len3, NewC4} = dec_sequence_union(Version, Rest2, N - 1, 
						   DiscrTC, Default, ElementList, 
						   Len2, ByteOrder, 
						   Buff, NewC3, Name),
    {[{Name, Label, Value} | Seq], Rest3, Len3, NewC4}.

%% A special case; when something is encapsulated (i.e. sent as octet-sequence)
%% we sometimes don not want the result to be converted to a list.
dec_octet_sequence_bin(Version, Message, Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    <<OctetSeq:Size/binary, Rest2/binary>> = Rest1,
    {OctetSeq, Rest2, Len1+4+Size, NewC+4+Size}.

is_known_struct('IOP_IOR') -> true;
is_known_struct('IOP_TaggedProfile') -> true;
is_known_struct('IOP_TaggedComponent') -> true;
is_known_struct('SSLIOP_SSL') -> true;
is_known_struct('IIOP_Version') -> true;
is_known_struct('IOP_ServiceContext') -> true;
is_known_struct('CONV_FRAME_CodeSetContext') -> true;
is_known_struct('CONV_FRAME_CodeSetComponent') -> true;
is_known_struct('CONV_FRAME_CodeSetComponentInfo') -> true;
is_known_struct(_) -> false.

%%-----------------------------------------------------------------
%% Func: dec_array/5
%%-----------------------------------------------------------------
dec_array(Version, Message, Size, TypeCode, Len, ByteOrder, Buff, C) ->
    {Seq, Rest1, Len1, NewC} = dec_sequence(Version, Message, Size, TypeCode, Len,
				     ByteOrder, Buff, C),
    {list_to_tuple(Seq), Rest1, Len1, NewC}.


%%-----------------------------------------------------------------
%% Func: dec_string/4
%%-----------------------------------------------------------------
dec_string(Version, Message, Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    if
	Size > 0 ->
	    DataSize = Size-1,
	    <<String:DataSize/binary, Null:1/binary, Rest2/binary>> = Rest1,
	    {binary_to_list(String), Rest2, Len1+4+Size, NewC+4+Size};
	true ->
	    {"", Rest1, Len1 + 4, NewC+4}
    end.

%%-----------------------------------------------------------------
%% Func: dec_string/4
%%-----------------------------------------------------------------
%dec_wstring({1,2}, Message, Len, ByteOrder, Buff, C) ->
%    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
%    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
%    CodeSet = get(wchar),
%    if
%	Size > 0, CodeSet == ?ISO_10646_UCS_2_ID ->
%	    {String, Rest2, Len2, NewC2} = dec_sequence(Version, Rest1, Size - 1, 'tk_wchar',
%						 Len1 + 4, ByteOrder, Buff, NewC+4),
%	    %% Remove the NULL character.
%	    {_, Rest3} = cdrlib:dec_unsigned_short(ByteOrder, Rest2),
%	    {String, Rest3, Len2 + 2, NewC2+2};
%	Size > 0 ->
%	    {String, Rest2, Len2, NewC2} = dec_sequence(Version, Rest1, Size - 1, 'tk_wchar',
%						 Len1 + 4, ByteOrder, Buff, NewC+4),
%	    {_, Rest3} = cdrlib:dec_unsigned_short(ByteOrder, Rest2),
%	    {String, Rest3, Len2 + 2, NewC2+2};
%	true ->
%	    {"", Rest1, Len1 + 4, NewC+4}
%    end;
dec_wstring(Version, Message, Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    CodeSet = get(wchar),
    if
%	Size > 0, CodeSet == ?ISO_10646_UCS_2_ID ->
	Size > 0 ->
	    {String, Rest2, Len2, NewC2} = dec_sequence(Version, Rest1, Size - 1, 'tk_wchar',
						 Len1 + 4, ByteOrder, Buff, NewC+4),
	    %% Remove the NULL character.
	    {_, Rest3} = cdrlib:dec_unsigned_short(ByteOrder, Rest2),
	    {String, Rest3, Len2 + 2, NewC2+2};
%	Size == 0, CodeSet == ?ISO_10646_UCS_2_ID ->
	Size == 0 ->
	    {"", Rest1, Len1 + 4, NewC+4};
%	CodeSet == ?ISO_10646_UCS_2_ID ->
	true ->
	    orber:debug_level_print("[~p] cdr_decode:dec_wstring(~p);",
				    [?LINE, Rest1], ?DEBUG_LEVEL),
	    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_NO})
%	true ->
%	    orber:debug_level_print("[~p] cdr_decode:dec_wstring(~p); Unsupported CodeSet.",
%				    [?LINE, CodeSet], ?DEBUG_LEVEL),
%	    corba:raise(#'CODESET_INCOMPATIBLE'{completion_status=?COMPLETED_NO})
    end.


%%-----------------------------------------------------------------
%% Func: dec_union/9
%%-----------------------------------------------------------------
%% ## NEW IIOP 1.2 ##
dec_union(Version, IFRId, 'GIOP_TargetAddress', DiscrTC, Default, ElementList, Bytes, Len, ByteOrder, Buff, C) ->
    {Label, Rest1, Len1, NewC} = dec_type(DiscrTC, Version, Bytes, Len, ByteOrder, Buff, C),
    {Value, Rest2, Len2, NewC3} = dec_union(Version, Label, ElementList, Default, 
					    Rest1, Len1, ByteOrder, Buff, NewC),
    {#'GIOP_TargetAddress'{label = Label, value = Value}, Rest2, Len2, NewC3};


dec_union(Version, IFRId, _, DiscrTC, Default, ElementList, Bytes, Len, ByteOrder, Buff, C) ->
    {Label, Rest1, Len1, NewC} = dec_type(DiscrTC, Version, Bytes, Len, ByteOrder, Buff, C),
    Result = dec_union(Version, stringify_enum(DiscrTC, Label), ElementList, Default, 
				     Rest1, Len1, ByteOrder, Buff, NewC),
    {Value, Rest2, Len2, NewC3} = case Result of
		{default, R, L, NewC2} ->
		    dec_union(Version, default, ElementList, Default, 
				     R, L, ByteOrder, Buff, NewC2);
		X ->
		    X
	    end,
    Name = ifrid_to_name(IFRId, ir_UnionDef),
    {{list_to_atom(Name), Label, Value}, Rest2, Len2, NewC3}.

dec_union(_, _, [], Default,  Message, Len, _, Buff, C) when Default < 0 ->
    {undefined, Message, Len, C};
dec_union(_, _, [], Default, Message, Len, _, Buff, C) ->
    {default, Message, Len, C};
dec_union(Version, Label, [{Label, Name, Type} | List ], Default, Message, Len, ByteOrder, Buff, C) ->
    dec_type(Type, Version, Message, Len, ByteOrder, Buff, C);
dec_union(Version, Label, [_ | List], Default, Message,  Len, ByteOrder, Buff, C) ->
    dec_union(Version, Label, List, Default, Message, Len, ByteOrder, Buff, C).

%%-----------------------------------------------------------------
%% Func: dec_struct/7
%%-----------------------------------------------------------------
dec_struct(Version, "", "", TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(Struct), Rest, Len1, NewC};
dec_struct(Version, [], Name, TypeCodeList, Message, Len, ByteOrder, Buff, C) -> 
    %% This case is used when communicating with ORB:s which don't supply the IFRId
    %% field in struct type codes (used in any)
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple([list_to_atom(Name) |Struct]), Rest, Len1, NewC};
dec_struct(Version, IFRId, ShortName, TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    case is_known_struct(ShortName) of
	true ->
	    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
	    {list_to_tuple([ShortName |Struct]), Rest, Len1, NewC};
	false ->
	    Name = ifrid_to_name(IFRId, ir_StructDef),
	    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
	    {list_to_tuple([list_to_atom(Name) |Struct]), Rest, Len1, NewC}
    end.

dec_struct1(_, [], Message, Len, ByteOrder, _, C) ->
    {[], Message, Len, C};
dec_struct1(Version, [{ElemName, ElemType} | TypeCodeList], Message, Len, ByteOrder, Buff, C) ->
    {Element, Rest, Len1, NewC} = dec_type(ElemType, Version, Message, Len, ByteOrder, Buff, C),
    {Struct, Rest1, Len2, NewC2} = dec_struct1(Version, TypeCodeList, Rest, Len1, ByteOrder, Buff, NewC),
    {[Element |Struct], Rest1, Len2, NewC2}.

ifrid_to_name([], _) ->
    orber:debug_level_print("[~p] cdr_decode:ifrid_to_name([]). No Id supplied.", 
			    [?LINE], ?DEBUG_LEVEL),
    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE});
ifrid_to_name(Id, Type) -> 
    case orber:get_lightweight_nodes() of
	false when Type == ir_UnionDef ->
	    case mnesia:dirty_index_read(ir_UnionDef, Id, #ir_UnionDef.id) of
		[#ir_UnionDef{absolute_name = [$:,$:|N]}] ->
		    change_colons_to_underscore(N, []);
		Other ->
		    orber:debug_level_print("[~p] cdr_decode:ifrid_to_name(~p). IFR Id not found: ~p", 
					    [?LINE, Id, Other], ?DEBUG_LEVEL),
		    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE})
	    end;
	false when Type == ir_StructDef ->
	    case mnesia:dirty_index_read(ir_StructDef, Id, #ir_StructDef.id) of
		[#ir_StructDef{absolute_name = [$:,$:|N]}] ->
		    change_colons_to_underscore(N, []);
		Other ->
		    orber:debug_level_print("[~p] cdr_decode:ifrid_to_name(~p). IFR Id not found: ~p", 
					    [?LINE, Id, Other], ?DEBUG_LEVEL),
		    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE})
	    end;
	false when Type == ir_ExceptionDef ->
	    case mnesia:dirty_index_read(ir_ExceptionDef, Id, #ir_ExceptionDef.id) of
		[#ir_ExceptionDef{absolute_name = [$:,$:|N]}] ->
		    change_colons_to_underscore(N, []);
		Other ->
		    orber:debug_level_print("[~p] cdr_decode:ifrid_to_name(~p). IFR Id not found: ~p", 
					    [?LINE, Id, Other], ?DEBUG_LEVEL),
		    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE})
	    end;
	Nodes ->
	    {A,B,C} = now(),
	    random:seed(A,B,C),
	    L = length(Nodes),
	    IFR = get_ifr_node(Nodes, random:uniform(L), L),
	    'OrberApp_IFR':get_absolute_name(IFR, Id)
    end.

change_colons_to_underscore([$:, $: | T], Acc) ->
    change_colons_to_underscore(T, [$_ |Acc]);
change_colons_to_underscore([H |T], Acc) ->
    change_colons_to_underscore(T, [H |Acc]);
change_colons_to_underscore([], Acc) ->
    lists:reverse(Acc).

get_ifr_node([], _, _) ->
    %% Were not able to contact any of the given nodes.
    orber:debug_level_print("[~p] cdr_decode:get_ifr_node([]). No Node available.", 
			    [?LINE], ?DEBUG_LEVEL),
    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE});
get_ifr_node(Nodes, N, L) ->
    Node = lists:nth(N, Nodes),
    case catch corba:resolve_initial_references_remote("OrberIFR", [Node]) of
	IFR when record(IFR, 'IOP_IOR') ->
	    IFR;
	_ ->
	    %% Not able to commincate with the node. Try next one.
	    NewL = L-1,
	    get_ifr_node(lists:delete(Node, Nodes), random:uniform(NewL), NewL)
    end.

    
%%-----------------------------------------------------------------
%% Func: dec_objref/4
%%-----------------------------------------------------------------
dec_objref(Version, Message, Len, ByteOrder) ->
    dec_objref(Version, Message, Len, ByteOrder, [], 0).
dec_objref(Version, Message, Len, ByteOrder, Buff, C) ->
    {IOR, Rest, Length} = iop_ior:decode(Version, Message, Len, ByteOrder),
    {IOR, Rest, Length, C+Length-Len}.

%%-----------------------------------------------------------------
%% Func: dec_system_exception/4 and dec_user_exception/4
%%-----------------------------------------------------------------
dec_system_exception(Version, Message, Len, ByteOrder) when Version == {1,2} ->
    {Rest0, Len0, Counter} = dec_align(Message, Len, 8, Len),
    {TypeId, Rest1, Len1} = dec_type({'tk_string', 0}, Version, Rest0, Len0, ByteOrder),
    Name = get_system_exception_name(TypeId),
    {Struct, Rest2, Len2} = dec_exception_1(Version, [{"minor",'tk_ulong'},
						      {"completed",
					      {'tk_enum', "", "completion_status",
					       ["COMPLETED_YES", "COMPLETED_NO",
						"COMPLETED_MAYBE"]}}],
					    Rest1, Len1, ByteOrder),
    {list_to_tuple([list_to_atom(Name), "" |Struct]), Len2};
dec_system_exception(Version, Message, Len, ByteOrder) ->
    {TypeId, Rest1, Len1} = dec_type({'tk_string', 0}, Version, Message, Len, ByteOrder),
    Name = get_system_exception_name(TypeId),
    {Struct, Rest2, Len2} = dec_exception_1(Version, [{"minor",'tk_ulong'},
						      {"completed",
					      {'tk_enum', "", "completion_status",
					       ["COMPLETED_YES", "COMPLETED_NO",
						"COMPLETED_MAYBE"]}}],
					    Rest1, Len1, ByteOrder),
    {list_to_tuple([list_to_atom(Name), "" |Struct]), Len2}.

dec_user_exception(Version, Message, Len, ByteOrder) when Version == {1,2} ->
    {Rest0, Len0, Counter} = dec_align(Message, Len, 8, Len),
    {TypeId, Rest1, Len1} = dec_type({'tk_string', 0}, Version, Rest0, Len0, ByteOrder),
    Name = ifrid_to_name(TypeId, ir_ExceptionDef),
    {'tk_except', _, _, ElementList} = get_user_exception_type(TypeId),
    {Struct, Rest2, Len2} = dec_exception_1(Version, ElementList, Rest1, Len1,
					    ByteOrder),
    {list_to_tuple([list_to_atom(Name), TypeId |Struct]), Len2};
dec_user_exception(Version, Message, Len, ByteOrder) ->
    {TypeId, Rest1, Len1} = dec_type({'tk_string', 0}, Version, Message, Len, ByteOrder),
    Name = ifrid_to_name(TypeId, ir_ExceptionDef),
    {'tk_except', _, _, ElementList} = get_user_exception_type(TypeId),
    {Struct, Rest2, Len2} = dec_exception_1(Version, ElementList, Rest1, Len1,
					    ByteOrder),
    {list_to_tuple([list_to_atom(Name), TypeId |Struct]), Len2}.

dec_exception_1(_, [], Message, Len, ByteOrder) ->
    {[], Message, Len};
dec_exception_1(Version, [{ElemName, ElemType} | ElementList], Message,
		Len, ByteOrder) ->
    {Element, Rest, Len1} = dec_type(ElemType, Version, Message, Len, ByteOrder),
    {Struct, Rest1, Len2} = dec_exception_1(Version, ElementList, Rest, Len1,
						   ByteOrder),
    {[Element |Struct], Rest1, Len2}.

get_user_exception_type(TypeId) ->
    case orber:get_lightweight_nodes() of
	false ->
	    case mnesia:dirty_index_read(ir_ExceptionDef, TypeId,
					 #ir_ExceptionDef.id) of
		[ExcDef] when record(ExcDef, ir_ExceptionDef) ->  
		    ExcDef#ir_ExceptionDef.type;
		Other ->
		    orber:debug_level_print("[~p] cdr_decode:get_user_exception_type(~p). IFR Id not found: ~p", 
					    [?LINE, TypeId, Other], ?DEBUG_LEVEL),
		    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE})
	    end;
	Nodes ->
	    {A,B,C} = now(),
	    random:seed(A,B,C),
	    L = length(Nodes),
	    IFR = get_ifr_node(Nodes, random:uniform(L), L),
	    'OrberApp_IFR':get_user_exception_type(IFR, TypeId)
    end.

get_system_exception_name(TypeId) ->
    case string:tokens(TypeId, ":/") of
	[IDL, OMGORG, CORBA, Name, Version] ->
	    Name;
	[IDL, CORBA, Name, Version] ->
	    Name;
	_ ->
             %% The CORBA-spec states that this exception should be raised if
             %% it's a system exception we do not support.
	    "UNKNOWN"
    end.

%%-----------------------------------------------------------------
%% Func: dec_type_code/4
%%-----------------------------------------------------------------
dec_type_code(Version, Message, Len, ByteOrder, Buff, C) ->
    {TypeNo, Message1, Len1, NewC} = dec_type('tk_ulong', Version, Message, Len, ByteOrder, Buff, C),
    dec_type_code(TypeNo, Version, Message1, Len1, ByteOrder, Buff, NewC).

%%-----------------------------------------------------------------
%% Func: dec_type_code/5
%%-----------------------------------------------------------------
dec_type_code(0, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_null', Message, Len, C};
dec_type_code(1, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_void', Message, Len, C};
dec_type_code(2, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_short', Message, Len, C};
dec_type_code(3, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_long', Message, Len, C};
dec_type_code(23, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_longlong', Message, Len, C};
dec_type_code(4, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_ushort', Message, Len, C};
dec_type_code(5, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_ulong', Message, Len, C};
dec_type_code(24, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_ulonglong', Message, Len, C};
dec_type_code(6, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_float', Message, Len, C};
dec_type_code(7, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_double', Message, Len, C};
dec_type_code(8, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_boolean', Message, Len, C};
dec_type_code(9, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_char', Message, Len, C};
dec_type_code(26, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_wchar', Message, Len, C};
dec_type_code(10, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_octet', Message, Len, C};
dec_type_code(11, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_any', Message, Len, C};
dec_type_code(12, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_TypeCode', Message, Len, C};
dec_type_code(13, Version, Message, Len, ByteOrder, _, C) ->
    {'tk_Principal', Message, Len, C};
dec_type_code(14, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name}, <<>>, Len2, NewC} = dec_type({'tk_struct', "", "",
					    [{"repository ID", {'tk_string', 0}},
					     {"name", {'tk_string', 0}}]},
					   Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_objref', RepId, Name}, Message1, Len1, NewC};
dec_type_code(15, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, ElementList}, <<>>, Len2, NewC} =
	dec_type({'tk_struct', "", "",
		  [{"repository ID", {'tk_string', 0}},
		   {"name", {'tk_string', 0}},
		   {"element list",
		    {'tk_sequence', {'tk_struct', "","",
				     [{"member name", {'tk_string', 0}},
				      {"member type", 'tk_TypeCode'}]},
		     0}}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_struct', RepId, Name, ElementList}, Message1, Len1, NewC};
dec_type_code(16, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, DiscrTC, Default}, Rest2, RestLen2, NewC} =
	dec_type({'tk_struct', "", "",
		  [{"repository ID", {'tk_string', 0}},
		   {"name", {'tk_string', 0}},
		   {"discriminant type", 'tk_TypeCode'},
		   {"default used", 'tk_long'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {ElementList, <<>>, RestLen3, NewC2} =
	dec_type({'tk_sequence', {'tk_struct', "","",
				  [{"label value", DiscrTC},
				   {"member name", {'tk_string', 0}},
				   {"member type", 'tk_TypeCode'}]}, 0},
		 Version, Rest2, RestLen2, ByteOrder1, Buff, NewC),
    NewElementList =
	case check_enum(DiscrTC) of
	    true ->
		lists:map(fun({L,N,T}) -> {atom_to_list(L),N,T} end, ElementList);
	    false ->
		ElementList
	end,
    {{'tk_union', RepId, Name, DiscrTC, Default, NewElementList}, Message1, Len1, NewC2};
dec_type_code(17, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, ElementList}, <<>>, Len2, NewC} =
	dec_type({'tk_struct', "", "",
		  [{"repository ID", {'tk_string', 0}},
		   {"name", {'tk_string', 0}},
		   {"element list",
		    {'tk_sequence', {'tk_string', 0}, 0}}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_enum', RepId, Name, ElementList}, Message1, Len1, NewC};
dec_type_code(18, Version, Message, Len, ByteOrder, Buff, C) ->
    {MaxLength, Message1, Len1, NewC} =
	dec_type('tk_ulong', Version, Message, Len, ByteOrder, Buff, C),
    {{'tk_string', MaxLength}, Message1, Len1, NewC};
dec_type_code(19, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{ElemTC, MaxLength}, <<>>, Len2, NewC} =
	dec_type({'tk_struct', "", "", [{"element type", 'tk_TypeCode'},
					{"max length", 'tk_ulong'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_sequence', ElemTC, MaxLength}, Message1, Len1, NewC};
dec_type_code(20, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{ElemTC, Length}, <<>>, Len2, NewC} =
	dec_type({'tk_struct', "", "", [{"element type", 'tk_TypeCode'},
					{"length", 'tk_ulong'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_array', ElemTC, Length}, Message1, Len1, NewC};
dec_type_code(21, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, TC}, <<>>, Len2, NewC} =
	dec_type({'tk_struct', "", "", [{"repository ID", {'tk_string', 0}},
					{"name", {'tk_string', 0}},
					{"TypeCode", 'tk_TypeCode'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_alias', RepId, Name, TC}, Message1, Len1, NewC};
dec_type_code(22, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg get the byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, ElementList}, <<>>, Len2, NewC} =
	dec_type({'tk_struct', "", "",
		  [{"repository ID", {'tk_string', 0}},
		   {"name", {'tk_string', 0}},
		   {"element list",
		    {'tk_sequence', {'tk_struct', "","",
				     [{"member name", {'tk_string', 0}},
				      {"member type", 'tk_TypeCode'}]},
		     0}}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_except', RepId, Name, ElementList}, Message1, Len1, NewC};
dec_type_code(27, Version, Message, Len, ByteOrder, Buff, C) ->
    {MaxLength, Message1, Len1, NewC} =
	dec_type('tk_ulong', Version, Message, Len, ByteOrder, Buff, C),
    {{'tk_wstring', MaxLength}, Message1, Len1, NewC};
dec_type_code(16#ffffffff, Version, Message, Len, ByteOrder, Buff, C) ->  %% placeholder
    {Indirection, Message1, Len1, NewC} =
	dec_type('tk_long', Version, Message, Len, ByteOrder, Buff, C),
    Position = C+Indirection,
    <<_:Position/binary, SubBuff/binary>> = Buff,
    {TC, _, _, _} = dec_type_code(Version, SubBuff, Position, ByteOrder, Buff, Position),
    {TC, Message1, Len1, NewC};
dec_type_code(Type, _, _, _, _, _, _) -> 
    orber:debug_level_print("[~p] cdr_decode:dec_type_code(~p); No match.", 
			    [?LINE, Type], ?DEBUG_LEVEL),
    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE}).

check_enum({'tk_enum', _, _, _}) ->
    true;
check_enum(_) ->
    false.


decode_complex_tc_parameters(Version, Message, Len, ByteOrder) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, 0),
    {Size, Rest1} = cdrlib:dec_unsigned_long(ByteOrder, Rest),
    <<OctetSeq:Size/binary, Rest2/binary>> = Rest1,
    {OctetSeq, Rest2, Len1+4+Size, NewC+4}.

%%-----------------------------------------------------------------
%% Func: dec_align/3
%% Args: 
%%       R - The byte sequence that shall be aligned.
%%       Len - The number of bytes read so far.
%%       Alignment - The alignment as an integer (for example: 2,4,8).
%% Returns: 
%%       An aligned byte sequence.
%%-----------------------------------------------------------------
dec_align(R, Len, Alignment, C) ->
    Rem = Len rem Alignment,
    if Rem == 0 ->
	    {R, Len, C};
       true ->
	    Diff = Alignment - Rem,
	    <<_:Diff/binary,Rest/binary>> = R,
	    {Rest, Len + Diff, C + Diff}
    end.

%%---------------- EOF MODULE ----------------------------------------
