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
%% Creation date: 970115
%%
%%-----------------------------------------------------------------
-module(cdr_decode).

-include_lib("orber/src/orber_iiop.hrl").
-include_lib("orber/include/ifr_types.hrl").
-include_lib("orber/include/corba.hrl").
-include_lib("orber/src/orber_debug.hrl").

%%-----------------------------------------------------------------
%% External exports
%%-----------------------------------------------------------------
-export([dec_message/2, dec_giop_message_header/1, peek_message_size/1, dec_reply_header/4,
	 dec_reply_body/5, dec_reply_body/6, dec_locate_reply_header/4, dec_locate_reply_body/5]).

%%-----------------------------------------------------------------
%% Functions which only are exported for the testcases.
%%-----------------------------------------------------------------
-export([dec_type/5, dec_byte_order/1, dec_system_exception/4, dec_user_exception/4]).

%%-----------------------------------------------------------------
%% Internal exports
%%-----------------------------------------------------------------
-export([]).

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
%%       {ok, Header, Parameters}.
%%-----------------------------------------------------------------
dec_message(TypeCodes, Bytes) ->
    Message = dec_giop_message_header(Bytes),
    ?PRINTDEBUG2("GIOP header: ~w", [Message]),
    case Message#giop_message.message_type of
	'request' ->
	    dec_request(Message#giop_message.giop_version,
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
%% Func: dec_giop_message_header/1
%% Args: 
%%       Bytes - is the the message as a byte sequence.
%% Returns: 
%%       A giop_message record.
%%-----------------------------------------------------------------
dec_giop_message_header(Bytes) ->
    {Magic, Rest1} =  dec_magic(Bytes),
    {Version, Rest2} = dec_giop_version(Rest1),
    {ByteOrder, Rest3} = if
	Version == {1,0} ->
	    dec_byte_order(Rest2);
	true ->
	    dec_flags(Rest2)
    end,
    {MessType, Rest4} = dec_mess_type(Rest3),
    {MessSize, Message} = dec_mess_size(Rest4, ByteOrder),
    #giop_message{magic = Magic, giop_version = Version, 
		  byte_order = ByteOrder, message_type = MessType, 
		   message_size = MessSize, message = Message}.

peek_message_size(Bytes) ->
    M = dec_giop_message_header(Bytes),
    M#giop_message.message_size.

%%-----------------------------------------------------------------
%% Func: dec_magic/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {"GIOP", Rest} where Rest is the remaining
%%       message byte sequence.
%%-----------------------------------------------------------------
dec_magic([$G, $I, $O, $P |Rest]) ->
    {"GIOP", Rest};
dec_magic(_) ->
    exit(message_error).

%%-----------------------------------------------------------------
%% Func: dec_giop_version/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {GIOP_version, Rest} where GIOP_version is a tuple 
%%       with a major and minor value. Rest is the remaining
%%       message byte sequence.
%%-----------------------------------------------------------------
dec_giop_version([GIOP_MAJOR, GIOP_MINOR | Rest]) ->
    {{GIOP_MAJOR, GIOP_MINOR}, Rest}; 
dec_giop_version(_) ->
    exit(message_error).


%%-----------------------------------------------------------------
%% Func: dec_byte_order/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {Endianess, Rest} where Endianess is big or little.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_byte_order([0|Rest]) ->
    {big, Rest};
dec_byte_order([1|Rest]) ->
    {little, Rest}.

%%-----------------------------------------------------------------
%% Func: dec_flags/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {Endianess, Rest} where Endianess is big or little.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_flags([0 |Rest]) ->
    {big, Rest};
dec_flags([_ |Rest]) ->
    {little, Rest}.

%%-----------------------------------------------------------------
%% Func: dec_mess_type/1
%% Args: 
%%       The message as a byte sequence.
%% Returns: 
%%       A tuple {MsgType, Rest} where MsgType is an 
%%       integer >= 0 and <= 6.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_mess_type([Type|Rest]) ->
    {dec_giop_msg_type(Type), Rest}.

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
%% Func: dec_mess_size/2
%% Args: 
%%       Bytes - is the the message as a byte sequence.
%%       ByteOrder - little or big
%% Returns: 
%%       A tuple {Length, Rest} where Length is the length of the message.
%%       Rest is the remaining message byte sequence.
%%-----------------------------------------------------------------
dec_mess_size(Bytes, ByteOrder) ->
    %% We know that this long integer is aligned because of the 
    %% fix header structure.
    cdrlib:dec_unsigned_long(Bytes, ByteOrder).

%%-----------------------------------------------------------------
%% Func: dec_request/3
%% Args: 
%%       Message - The message
%%       Len0 - Number of bytes already read.
%%       ByteOrder - little or big
%% Returns: 
%%       A tuple {RequestHeader, Parameters, TypeCodes} where RequestHeader is a
%%       request_header record, Parameters a list of the decode
%%       parameters and TypeCodes is the operation description.
%%-----------------------------------------------------------------
dec_request(Version, Message, Len0, ByteOrder, Buffer) ->
    {Context, Rest1, Len1} = dec_service_context(Version, Message, Len0, ByteOrder),
    {Request_id, Rest2, Len2, _} = dec_type('tk_ulong', Version, Rest1, Len1, ByteOrder, [], 0),
    {Response_expected, Rest3, Len3, _} = dec_type('tk_boolean',  Version, Rest2, Len2,
						   ByteOrder, [], 0),
    {ObjKey, Rest4, Len4, _} = dec_type({'tk_sequence', 'tk_octet', 0},  Version, Rest3,
				   Len3, ByteOrder, [], 0),
    Object_key = corba:string_to_objkey(ObjKey),
    {Operation, Rest5, Len5, _} = dec_type({'tk_string', 0},  Version, Rest4, Len4, ByteOrder, [], 0),
    {Principal, Rest, Len, _} = dec_type({'tk_string', 0},  Version, Rest5,Len5,  ByteOrder, [], 0),
    {Parameters, TypeCodes, _} = dec_request_body(Version, Object_key,
				       Operation, Rest, Len, ByteOrder, Buffer, Len),
    {Version, #request_header{service_context=Context, request_id=Request_id,
		    response_expected=Response_expected,
		    object_key=Object_key,
		    operation=Operation, requesting_principal=Principal},
     Parameters, TypeCodes}.


dec_service_context(Version, Message, Len, ByteOrder) ->
    {Context, Rest, Len1} = dec_type({'tk_sequence',
				      {'tk_struct', 0, 'ServiceContext',
				       [{"context_id", 'tk_long'},
					{"context_data",
					 {'tk_sequence', 'tk_octet', 0}}]}, 0},
					Version, Message, Len, ByteOrder).

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

remove_extra_bytes([], Len) ->
    {[], Len};
remove_extra_bytes([_|Xs], Len) ->
    remove_extra_bytes(Xs, Len + 1).

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
    {Result, Par} = case ReplyHeader#reply_header.reply_status of
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
		     {R, _, _, _} = dec_objref(Version, Rest, Len, ByteOrder, Message, Len),
		     {R, []}
	     end,
    {ReplyHeader, Result, Par}.

dec_reply_header(Version, Message, Len0, ByteOrder) ->
    {Context, Rest1, Len1} = dec_service_context(Version, Message, Len0, ByteOrder),
    {Request_id, Rest2, Len2} = dec_type('tk_ulong', Version, Rest1, Len1, ByteOrder),
    {ReplyStatus, Rest, Len3} = dec_reply_status(Version, Rest2, Len2, ByteOrder),
    {#reply_header{service_context=Context, request_id=Request_id, reply_status=ReplyStatus},
     Rest, Len3}.

dec_reply_status(Version, Status, Len, ByteOrder) ->
    {L, Rest, Len1}= dec_type('tk_ulong', Version, Status, Len, ByteOrder),
    {dec_giop_reply_status_type(L), Rest, Len1}.

%% Next case is added to handle code upgrade; remove later.
dec_reply_body(Version, {RetType, InParameters, OutParameters}, Body, Len, ByteOrder) ->
    dec_reply_body(Version, {RetType, InParameters, OutParameters}, Body, Len, ByteOrder, []).

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
    'location_forward'.

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
    'object_forward'.





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
    {Short, Rest1} = cdrlib:dec_short(Rest, ByteOrder),
    {Short, Rest1, Len1 + 2, NewC+2};
dec_type('tk_long', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Long, Rest1} = cdrlib:dec_long(Rest, ByteOrder),
    {Long, Rest1, Len1 + 4, NewC+4};
dec_type('tk_longlong', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 8, C),
    {Long, Rest1} = cdrlib:dec_longlong(Rest, ByteOrder),
    {Long, Rest1, Len1 + 8, NewC+8};
dec_type('tk_ushort', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 2, C),
    {Short, Rest1} = cdrlib:dec_unsigned_short(Rest, ByteOrder),
    {Short, Rest1, Len1 + 2, NewC+2};
dec_type('tk_ulong', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Long, Rest1} = cdrlib:dec_unsigned_long(Rest, ByteOrder),
    {Long, Rest1, Len1 + 4, NewC+4};
dec_type('tk_ulonglong', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 8, C),
    {Long, Rest1} = cdrlib:dec_unsigned_longlong(Rest, ByteOrder),
    {Long, Rest1, Len1 + 8, NewC+8};
dec_type('tk_float', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 4, C),
    {Float, Rest1} = cdrlib:dec_float(Rest, ByteOrder),
    {Float, Rest1, Len1 + 4, NewC+4};
dec_type('tk_double', Version, Bytes, Len, ByteOrder, _, C) ->
    {Rest, Len1, NewC} = dec_align(Bytes, Len, 8, C),
    {Double, Rest1} = cdrlib:dec_double(Rest, ByteOrder),
    {Double, Rest1, Len1 + 8, NewC+8};
dec_type('tk_boolean', Version, Bytes, Len, _, _, C) ->
    {Bool, Rest} = cdrlib:dec_bool(Bytes),
    {Bool, Rest, Len + 1, C+1};
dec_type('tk_char', Version, Bytes, Len, _, _, C) ->
    {Char, Rest} = cdrlib:dec_char(Bytes),
    {Char, Rest, Len + 1, C+1};
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
    {Enum, Rest1} = cdrlib:dec_enum(ElementList, Rest, ByteOrder),
    {Enum, Rest1, Len1 + 4, NewC+4}; 
dec_type({'tk_string', MaxLength}, Version, Bytes, Len, ByteOrder, Buff, C) -> % MaxLength Not Used
    dec_string(Version, Bytes, Len, ByteOrder, Buff, C);
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
%% Func: dec_sequence/5 and dec_sequence/6
%%-----------------------------------------------------------------
dec_sequence(Version, Message, TypeCode, Len, ByteOrder, Buff, C) ->
    {Rest, Len1, NewC} = dec_align(Message, Len, 4, C),
    {Size, Rest1} = cdrlib:dec_unsigned_long(Rest, ByteOrder),
    dec_sequence(Version, Rest1, Size, TypeCode, Len1 + 4, ByteOrder, Buff, NewC+4).


dec_sequence(_, Message, 0, Type, Len, ByteOrder, Buff, C) ->
    {[], Message, Len, C};
dec_sequence(Version, Message, N, Type, Len, ByteOrder, Buff, C) ->
    {Object, Rest1, Len1, NewC} = dec_type(Type, Version, Message, Len, ByteOrder, Buff, C),
    {Seq, Rest2, Len2, NewC2} = dec_sequence(Version, Rest1, N - 1,  Type, Len1, ByteOrder, Buff, NewC),
    {[Object | Seq], Rest2, Len2, NewC2}.


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
    {Size, Rest1} = cdrlib:dec_unsigned_long(Rest, ByteOrder),
    if
	Size > 0 ->
	    {String, Rest2, Len2, NewC2} = dec_sequence(Version, Rest1, Size - 1, 'tk_char',
						 Len1 + 4, ByteOrder, Buff, NewC+4),
	    {_, Rest3} = cdrlib:dec_octet(Rest2),
	    {String, Rest3, Len2 + 1, NewC2+1};
	true ->
	    {"", Rest1, Len1 + 4, NewC+4}
    end.


%%-----------------------------------------------------------------
%% Func: dec_union/9
%%-----------------------------------------------------------------

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
    Name = ifrid_to_name(IFRId),
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
dec_struct(Version, IFRId, 'IOP_IOR', TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(['IOP_IOR' |Struct]), Rest, Len1, NewC};
dec_struct(Version, IFRId, 'IOP_TaggedProfile', TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(['IOP_TaggedProfile' |Struct]), Rest, Len1, NewC};
dec_struct(Version, IFRId, 'IOP_TaggedComponent', TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(['IOP_TaggedComponent' |Struct]), Rest, Len1, NewC};
dec_struct(Version, IFRId, 'SSLIOP_SSL', TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(['SSLIOP_SSL' |Struct]), Rest, Len1, NewC};
%dec_struct(Version, IFRId, 'IIOP_ProfileBody', TypeCodeList, Message, Len, ByteOrder) ->
%    {Struct, Rest, Len1} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder),
%    {list_to_tuple(['IIOP_ProfileBody' |Struct]), Rest, Len1};
dec_struct(Version, IFRId, 'IIOP_Version', TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(['IIOP_Version' |Struct]), Rest, Len1, NewC};
dec_struct(Version, IFRId, 'ServiceContext', TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple(['ServiceContext' |Struct]), Rest, Len1, NewC};
dec_struct(Version, [], Name, TypeCodeList, Message, Len, ByteOrder, Buff, C) -> 
    %% This case is due to that for example Orbix, don't supply the IFRId field in
    %% struct type codes (used in any)
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple([list_to_atom(Name) |Struct]), Rest, Len1, NewC};
dec_struct(Version, IFRId, _, TypeCodeList, Message, Len, ByteOrder, Buff, C) ->
    Name = ifrid_to_name(IFRId),
    {Struct, Rest, Len1, NewC} = dec_struct1(Version, TypeCodeList, Message, Len, ByteOrder, Buff, C),
    {list_to_tuple([list_to_atom(Name) |Struct]), Rest, Len1, NewC}.

dec_struct1(_, [], Message, Len, ByteOrder, _, C) ->
    {[], Message, Len, C};
dec_struct1(Version, [{ElemName, ElemType} | TypeCodeList], Message, Len, ByteOrder, Buff, C) ->
    {Element, Rest, Len1, NewC} = dec_type(ElemType, Version, Message, Len, ByteOrder, Buff, C),
    {Struct, Rest1, Len2, NewC2} = dec_struct1(Version, TypeCodeList, Rest, Len1, ByteOrder, Buff, NewC),
    {[Element |Struct], Rest1, Len2, NewC2}.

ifrid_to_name([]) ->
    orber:debug_level_print("[~p] cdr_decode:ifrid_to_name([]). No Id supplied.", 
			    [?LINE], ?DEBUG_LEVEL),
    corba:raise(#'MARSHAL'{minor=107, completion_status=?COMPLETED_MAYBE});
ifrid_to_name(Id) -> 
    case orber:get_lightweight_nodes() of
	false ->
	    %% This way may be more beutiful, but less effective. On the other
	    %% hand we must duplicate code. Decide about which.
%	    IFR=corba:resolve_initial_references("OrberIFR"),
%	    'OrberApp_IFR':get_absolute_name(IFR, Id);
	    Rep = orber_ifr:find_repository(),
	    Key = orber_ifr:'Repository_lookup_id'(Rep, Id),
	    [$:, $: |N] = orber_ifr:'Contained__get_absolute_name'(Key),
	    change_colons_to_underscore(N, []);
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
dec_system_exception(Version, Message, Len, ByteOrder) ->
    {TypeId, Rest1, Len1} = dec_type({'tk_string', 0}, Version, Message, Len, ByteOrder),
    Name = get_system_exception_name(TypeId),
    {Struct, Rest2, Len2} = dec_exception_1(Version, [{"minor",'tk_ulong'},
						      {"completed",
					      {'tk_enum', "", "completion_status",
					       ["COMPLETED_YES", "COMPLETED_NO",
						"COMPLETED_MAYBE"]}}],
					    Rest1, Len1, ByteOrder),
%    {[], Len3} = remove_extra_bytes(Rest2, Len2),
    {list_to_tuple([list_to_atom(Name), "" |Struct]), Len2}.

dec_user_exception(Version, Message, Len, ByteOrder) ->
    {TypeId, Rest1, Len1} = dec_type({'tk_string', 0}, Version, Message, Len, ByteOrder),
    Name = ifrid_to_name(TypeId),
    {'tk_except', _, _, ElementList} = get_user_exception_type(TypeId),
    {Struct, Rest2, Len2} = dec_exception_1(Version, ElementList, Rest1, Len1,
					    ByteOrder),
%    {[], Len3} = remove_extra_bytes(Rest2, Len2),
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
	    %% This way may be more beutiful (next 2 lines), but less effective. 
	    %% On the other hand we must duplicate code. Decide about which.
%	    IFR=corba:resolve_initial_references("OrberIFR"),
%	    'OrberApp_IFR':get_user_exception_type(IFR, Id);
	    Rep = orber_ifr:find_repository(),
	    ExceptionDef = orber_ifr:'Repository_lookup_id'(Rep, TypeId),
	    ContainedDescr = orber_ifr_exceptiondef:describe(ExceptionDef),
	    ExceptionDescr = ContainedDescr#contained_description.value,
	    ExceptionDescr#exceptiondescription.type;
	Nodes ->
	    {A,B,C} = now(),
	    random:seed(A,B,C),
	    L = length(Nodes),
	    IFR = get_ifr_node(Nodes, random:uniform(L), L),
	    'OrberApp_IFR':get_user_exception_type(IFR, TypeId)
    end.

get_system_exception_name(TypeId) ->
    Start = string:chr(TypeId, $/),
    End = string:rchr(TypeId, $:),
    string:substr(TypeId, Start+1, End - (Start+1)).

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
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name}, [], Len2, NewC} = dec_type({'tk_struct', "", "",
					    [{"repository ID", {'tk_string', 0}},
					     {"name", {'tk_string', 0}}]},
					   Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_objref', RepId, Name}, Message1, Len1, NewC};
dec_type_code(15, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, ElementList}, [], Len2, NewC} =
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
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, DiscrTC, Default}, Rest2, RestLen2, NewC} =
	dec_type({'tk_struct', "", "",
		  [{"repository ID", {'tk_string', 0}},
		   {"name", {'tk_string', 0}},
		   {"discriminant type", 'tk_TypeCode'},
		   {"default used", 'tk_long'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {ElementList, [], RestLen3, NewC2} =
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
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, ElementList}, [], Len2, NewC} =
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
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{ElemTC, MaxLength}, [], Len2, NewC} =
	dec_type({'tk_struct', "", "", [{"element type", 'tk_TypeCode'},
					{"max length", 'tk_ulong'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_sequence', ElemTC, MaxLength}, Message1, Len1, NewC};
dec_type_code(20, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{ElemTC, Length}, [], Len2, NewC} =
	dec_type({'tk_struct', "", "", [{"element type", 'tk_TypeCode'},
					{"length", 'tk_ulong'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_array', ElemTC, Length}, Message1, Len1, NewC};
dec_type_code(21, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, TC}, [], Len2, NewC} =
	dec_type({'tk_struct', "", "", [{"repository ID", {'tk_string', 0}},
					{"name", {'tk_string', 0}},
					{"TypeCode", 'tk_TypeCode'}]},
		 Version, Rest1, 1, ByteOrder1, Buff, C+1+Ex),
    {{'tk_alias', RepId, Name, TC}, Message1, Len1, NewC};
dec_type_code(22, Version, Message, Len, ByteOrder, Buff, C) ->
    {ComplexParams, Message1, Len1, Ex} = decode_complex_tc_parameters(Version, Message, Len, ByteOrder),
    %% Decode marshalled parameters, eg ge a byteorder first
    {ByteOrder1, Rest1} = dec_byte_order(ComplexParams),
    {{RepId, Name, ElementList}, [], Len2, NewC} =
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
dec_type_code(16#ffffffff, Version, Message, Len, ByteOrder, Buff, C) ->  %% placeholder
    {Indirection, Message1, Len1, NewC} =
	dec_type('tk_long', Version, Message, Len, ByteOrder, Buff, C),
    SubList = lists:nthtail(C+Indirection, Buff),
    {TC, _, _, _} = dec_type_code(Version, SubList, C+Indirection, ByteOrder, Buff, C+Indirection),
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
    {Size, Rest1} = cdrlib:dec_unsigned_long(Rest, ByteOrder),
    {ComplexParams, Message2, Len2, _} =
	dec_sequence(Version, Rest1, Size, 'tk_octet', Len1 + 4, ByteOrder, [], 0),
    {ComplexParams, Message2, Len2, NewC+4}.


%    {ComplexParams, Message1, Len1, _} =
%    	dec_type({'tk_sequence', 'tk_octet', 0}, Version, Message, Len, ByteOrder, [], 0),
%    {ComplexParams, Message1, Len1}.

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
	    {remove_bytes(R, Alignment - Rem), Len + (Alignment - Rem), C + (Alignment - Rem)}
    end.

remove_bytes(R, 0) ->
    R;
remove_bytes([_|R],N) ->
    remove_bytes(R, N - 1).

