%%<copyright>
%% <year>2000-2008</year>
%% <holder>Ericsson AB, All Rights Reserved</holder>
%%</copyright>
%%<legalnotice>
%% The contents of this file are subject to the Erlang Public License,
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
%%----------------------------------------------------------------------
%% Purpose: Encode COMPACT Megaco/H.248 text messages from internal form
%%----------------------------------------------------------------------

-module(megaco_compact_text_encoder).

-behaviour(megaco_encoder).

-export([encode_message/3, decode_message/3,
	 decode_mini_message/3, 

	 version_of/2, 

	 encode_transaction/3,
	 encode_action_requests/3,
	 encode_action_request/3,
	 encode_command_request/3,
	 encode_action_reply/3]).

-export([token_tag2string/1, token_tag2string/2]).

%% Backward compatible funcs:
-export([encode_message/2, decode_message/2]).


-include_lib("megaco/src/engine/megaco_message_internal.hrl").

-define(V1_PARSE_MOD,     megaco_text_parser_v1).
-define(V2_PARSE_MOD,     megaco_text_parser_v2).
-define(V3_PARSE_MOD,     megaco_text_parser_v3).
-define(PREV3A_PARSE_MOD, megaco_text_parser_prev3a).
-define(PREV3B_PARSE_MOD, megaco_text_parser_prev3b).
-define(PREV3C_PARSE_MOD, megaco_text_parser_prev3c).


%%----------------------------------------------------------------------
%% Convert a 'MegacoMessage' record into a binary
%% Return {ok, DeepIoList} | {error, Reason}
%%----------------------------------------------------------------------

encode_message(EncodingConfig, 
	       #'MegacoMessage'{mess = #'Message'{version = V}} = MegaMsg) ->
    encode_message(EncodingConfig, V, MegaMsg).

encode_message([{version3,_}|EC], 1, MegaMsg) ->
    megaco_compact_text_encoder_v1:encode_message(EC, MegaMsg);
encode_message(EC, 1, MegaMsg) ->
    megaco_compact_text_encoder_v1:encode_message(EC, MegaMsg);
encode_message([{version3,_}|EC], 2, MegaMsg) ->
    megaco_compact_text_encoder_v2:encode_message(EC, MegaMsg);
encode_message(EC, 2, MegaMsg) ->
    megaco_compact_text_encoder_v2:encode_message(EC, MegaMsg);
encode_message([{version3,v3}|EC], 3, MegaMsg) ->
    megaco_compact_text_encoder_v3:encode_message(EC, MegaMsg);
encode_message([{version3,prev3c}|EC], 3, MegaMsg) ->
    megaco_compact_text_encoder_prev3c:encode_message(EC, MegaMsg);
encode_message([{version3,prev3b}|EC], 3, MegaMsg) ->
    megaco_compact_text_encoder_prev3b:encode_message(EC, MegaMsg);
encode_message([{version3,prev3a}|EC], 3, MegaMsg) ->
    megaco_compact_text_encoder_prev3a:encode_message(EC, MegaMsg);
encode_message(EC, 3, MegaMsg) ->
    megaco_compact_text_encoder_v3:encode_message(EC, MegaMsg);
encode_message(_EC, V, _MegaMsg) ->
    {error, {bad_version, V}}.


%%----------------------------------------------------------------------
%% Convert a binary into a 'MegacoMessage' record
%% Return {ok, MegacoMessageRecord} | {error, Reason}
%%----------------------------------------------------------------------

version_of(_EC, Bin) ->
    case megaco_text_scanner:scan(Bin) of
	{ok, _Tokens, V, _LastLine} ->
	    {ok, V};
	{error, Reason, Line} ->
	    {error, {decode_failed, Reason, Line}}
    end.


decode_message(EC, Bin) ->
    %% d("decode_message -> entry with"
    %%   "~n   EC: ~p", [EC]),
    decode_message(EC, dynamic, Bin).

decode_message([], _, Bin) when is_binary(Bin) ->
    %% d("decode_message([]) -> entry"),
    case megaco_text_scanner:scan(Bin) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?V3_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	{error, Reason, Tokens, Line} ->
	    parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,v3}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(v3) -> entry"),
    case megaco_text_scanner:scan(Bin) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?V3_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	{error, Reason, Tokens, Line} ->
	    parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,prev3c}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(prev3c) -> entry"),
    case megaco_text_scanner:scan(Bin) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?PREV3C_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	{error, Reason, Tokens, Line} ->
	    parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,prev3b}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(prev3b) -> entry"),
    case megaco_text_scanner:scan(Bin) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?PREV3B_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	{error, Reason, Tokens, Line} ->
	    parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,prev3a}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(prev3a) -> entry"),
    case megaco_text_scanner:scan(Bin) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?PREV3A_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	{error, Reason, Tokens, Line} ->
	    parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{flex, Port}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(flex) -> entry"),
    case megaco_flex_scanner:scan(Bin, Port) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?V3_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	%% {error, Reason, Tokens, Line} ->
	%%     parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,v3},{flex, Port}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(v3,flex) -> entry"),
    case megaco_flex_scanner:scan(Bin, Port) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?V3_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	%% {error, Reason, Tokens, Line} ->
	%%     parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,prev3c},{flex, Port}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(prev3c,flex) -> entry"),
    case megaco_flex_scanner:scan(Bin, Port) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?PREV3C_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	%% {error, Reason, Tokens, Line} ->
	%%     parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->
	    parse_error(Reason, Line, [], Bin)
    end;
decode_message([{version3,prev3b},{flex, Port}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(prev3b,flex) -> entry"),
    case megaco_flex_scanner:scan(Bin, Port) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?PREV3B_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	%% {error, Reason, Tokens, Line} ->
	%%     parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message([{version3,prev3a},{flex, Port}], _, Bin) when is_binary(Bin) ->
    %% d("decode_message(prev3a,flex) -> entry"),
    case megaco_flex_scanner:scan(Bin, Port) of
	{ok, Tokens, 1, _LastLine} ->
	    do_decode_message(?V1_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 2, _LastLine} ->
	    do_decode_message(?V2_PARSE_MOD, Tokens, Bin);

	{ok, Tokens, 3, _LastLine} ->
	    do_decode_message(?PREV3A_PARSE_MOD, Tokens, Bin);

	{ok, _Tokens, V, _LastLine} ->
	    {error, {unsupported_version, V}};

	%% {error, Reason, Tokens, Line} ->
	%%     parse_error(Reason, Line, Tokens, Bin);

	{error, Reason, Line} ->               %% OTP-4007
	    parse_error(Reason, Line, [], Bin) %% OTP-4007
    end;
decode_message(EC, _, Bin) when is_binary(Bin) ->
    {error, {bad_encoding_config, EC}};
decode_message(_EC, _, _BadBin) ->
    {error, bad_binary}.


do_decode_message(ParseMod, Tokens, Bin) ->
%%     d("do_decode_message -> entry with"
%%       "~n   ParseMod: ~p"
%%       "~n   Tokens:   ~p", [ParseMod, Tokens]),
    case (catch ParseMod:parse(Tokens)) of
	{ok, MegacoMessage} ->
%% 	    d("do_decode_message -> "
%% 	      "~n   MegacoMessage: ~p", [MegacoMessage]),
	    {ok, MegacoMessage};
	{error, Reason} ->
	    parse_error(Reason, Tokens, Bin);

	%% OTP-4007
	{'EXIT', Reason} ->
	    parse_error(Reason, Tokens, Bin)
    end.


decode_mini_message(EC, _, Bin) when is_binary(Bin) ->
    megaco_text_mini_decoder:decode_message(EC, Bin).


parse_error(Reason, Tokens, Chars) ->
    {error, [{reason, Reason}, {token, Tokens}, {chars, Chars}]}.

parse_error(Reason, Line, Tokens, Chars) ->
    {error, [{reason, Reason, Line}, {token, Tokens}, {chars, Chars}]}.


%%----------------------------------------------------------------------
%% Convert a transaction record into a deep io list
%% Return {ok, DeepIoList} | {error, Reason}
%%----------------------------------------------------------------------
encode_transaction([{version3,_}|EC], 1, Trans) ->
    megaco_compact_text_encoder_v1:encode_transaction(EC, Trans);
encode_transaction(EC, 1, Trans) ->
    megaco_compact_text_encoder_v1:encode_transaction(EC, Trans);
encode_transaction([{version3,_}|EC], 2, Trans) ->
    megaco_compact_text_encoder_v2:encode_transaction(EC, Trans);
encode_transaction(EC, 2, Trans) ->
    megaco_compact_text_encoder_v2:encode_transaction(EC, Trans);
encode_transaction([{version3,prev3c}|EC], 3, Trans) ->
    megaco_compact_text_encoder_prev3c:encode_transaction(EC, Trans);
encode_transaction([{version3,prev3b}|EC], 3, Trans) ->
    megaco_compact_text_encoder_prev3b:encode_transaction(EC, Trans);
encode_transaction([{version3,prev3a}|EC], 3, Trans) ->
    megaco_compact_text_encoder_prev3a:encode_transaction(EC, Trans);
encode_transaction([{version3,v3}|EC], 3, Trans) ->
    megaco_compact_text_encoder_v3:encode_transaction(EC, Trans);
encode_transaction(EC, 3, Trans) ->
    megaco_compact_text_encoder_v3:encode_transaction(EC, Trans);
encode_transaction(_EC, V, _Trans) ->
    {error, {bad_version, V}}.


%%----------------------------------------------------------------------
%% Convert a list of ActionRequest record's into a binary
%% Return {ok, DeepIoList} | {error, Reason}
%%----------------------------------------------------------------------
encode_action_requests([{version3,_}|EC], 1, ActReqs) 
  when list(ActReqs) ->
    megaco_compact_text_encoder_v1:encode_action_requests(EC, ActReqs);
encode_action_requests(EC, 1, ActReqs) when list(ActReqs) ->
    megaco_compact_text_encoder_v1:encode_action_requests(EC, ActReqs);
encode_action_requests([{version3,_}|EC], 2, ActReqs) 
  when list(ActReqs) ->
    megaco_compact_text_encoder_v2:encode_action_requests(EC, ActReqs);
encode_action_requests(EC, 2, ActReqs) when list(ActReqs) ->
    megaco_compact_text_encoder_v2:encode_action_requests(EC, ActReqs);
encode_action_requests([{version3,prev3c}|EC], 3, ActReqs) 
  when list(ActReqs) ->
    megaco_compact_text_encoder_prev3c:encode_action_requests(EC, ActReqs);
encode_action_requests([{version3,prev3b}|EC], 3, ActReqs) 
  when list(ActReqs) ->
    megaco_compact_text_encoder_prev3b:encode_action_requests(EC, ActReqs);
encode_action_requests([{version3,prev3a}|EC], 3, ActReqs) 
  when list(ActReqs) ->
    megaco_compact_text_encoder_prev3a:encode_action_requests(EC, ActReqs);
encode_action_requests([{version3,v3}|EC], 3, ActReqs) 
  when list(ActReqs) ->
    megaco_compact_text_encoder_v3:encode_action_requests(EC, ActReqs);
encode_action_requests(EC, 3, ActReqs) when list(ActReqs) ->
    megaco_compact_text_encoder_v3:encode_action_requests(EC, ActReqs);
encode_action_requests(_EC, V, _ActReqs) ->
    {error, {bad_version, V}}.


%%----------------------------------------------------------------------
%% Convert a ActionRequest record into a binary
%% Return {ok, DeepIoList} | {error, Reason}
%%----------------------------------------------------------------------
encode_action_request([{version3,_}|EC], 1, ActReq) ->
    megaco_compact_text_encoder_v1:encode_action_request(EC, ActReq);
encode_action_request(EC, 1, ActReq) ->
    megaco_compact_text_encoder_v1:encode_action_request(EC, ActReq);
encode_action_request([{version3,_}|EC], 2, ActReq) ->
    megaco_compact_text_encoder_v2:encode_action_request(EC, ActReq);
encode_action_request(EC, 2, ActReq) ->
    megaco_compact_text_encoder_v2:encode_action_request(EC, ActReq);
encode_action_request([{version3,prev3c}|EC], 3, ActReq) ->
    megaco_compact_text_encoder_prev3c:encode_action_request(EC, ActReq);
encode_action_request([{version3,prev3b}|EC], 3, ActReq) ->
    megaco_compact_text_encoder_prev3b:encode_action_request(EC, ActReq);
encode_action_request([{version3,prev3a}|EC], 3, ActReq) ->
    megaco_compact_text_encoder_prev3a:encode_action_request(EC, ActReq);
encode_action_request([{version3,v3}|EC], 3, ActReq) ->
    megaco_compact_text_encoder_v3:encode_action_request(EC, ActReq);
encode_action_request(EC, 3, ActReq) ->
    megaco_compact_text_encoder_v3:encode_action_request(EC, ActReq);
encode_action_request(_EC, V, _ActReq) ->
    {error, {bad_version, V}}.


%%----------------------------------------------------------------------
%% Convert a CommandRequest record into a deep io list
%% Return {ok, DeepIoList} | {error, Reason}
%%----------------------------------------------------------------------
encode_command_request([{version3,_}|EC], 1, CmdReq) ->
    megaco_compact_text_encoder_v1:encode_command_request(EC, CmdReq);
encode_command_request(EC, 1, CmdReq) ->
    megaco_compact_text_encoder_v1:encode_command_request(EC, CmdReq);
encode_command_request([{version3,_}|EC], 2, CmdReq) ->
    megaco_compact_text_encoder_v2:encode_command_request(EC, CmdReq);
encode_command_request(EC, 2, CmdReq) ->
    megaco_compact_text_encoder_v2:encode_command_request(EC, CmdReq);
encode_command_request([{version3,prev3c}|EC], 3, CmdReq) ->
    megaco_compact_text_encoder_prev3c:encode_command_request(EC, CmdReq);
encode_command_request([{version3,prev3b}|EC], 3, CmdReq) ->
    megaco_compact_text_encoder_prev3b:encode_command_request(EC, CmdReq);
encode_command_request([{version3,prev3a}|EC], 3, CmdReq) ->
    megaco_compact_text_encoder_prev3a:encode_command_request(EC, CmdReq);
encode_command_request([{version3,v3}|EC], 3, CmdReq) ->
    megaco_compact_text_encoder_v3:encode_command_request(EC, CmdReq);
encode_command_request(EC, 3, CmdReq) ->
    megaco_compact_text_encoder_v3:encode_command_request(EC, CmdReq);
encode_command_request(_EC, V, _CmdReq) ->
    {error, {bad_version, V}}.


%%----------------------------------------------------------------------
%% Convert a action reply into a deep io list
%% Return {ok, DeepIoList} | {error, Reason}
%%----------------------------------------------------------------------
encode_action_reply([{version3,_}|EC], 1, ActRep) ->
    megaco_compact_text_encoder_v1:encode_action_reply(EC, ActRep);
encode_action_reply(EC, 1, ActRep) ->
    megaco_compact_text_encoder_v1:encode_action_reply(EC, ActRep);
encode_action_reply([{version3,_}|EC], 2, ActRep) ->
    megaco_compact_text_encoder_v2:encode_action_reply(EC, ActRep);
encode_action_reply(EC, 2, ActRep) ->
    megaco_compact_text_encoder_v2:encode_action_reply(EC, ActRep);
encode_action_reply([{version3,prev3c}|EC], 3, ActRep) ->
    megaco_compact_text_encoder_prev3c:encode_action_reply(EC, ActRep);
encode_action_reply([{version3,prev3b}|EC], 3, ActRep) ->
    megaco_compact_text_encoder_prev3b:encode_action_reply(EC, ActRep);
encode_action_reply([{version3,prev3a}|EC], 3, ActRep) ->
    megaco_compact_text_encoder_prev3a:encode_action_reply(EC, ActRep);
encode_action_reply([{version3,v3}|EC], 3, ActRep) ->
    megaco_compact_text_encoder_v3:encode_action_reply(EC, ActRep);
encode_action_reply(EC, 3, ActRep) ->
    megaco_compact_text_encoder_v3:encode_action_reply(EC, ActRep);
encode_action_reply(_EC, V, _ActRep) ->
    {error, {bad_version, V}}.



%%----------------------------------------------------------------------
%% A utility function to pretty print the tags found in a megaco message
%%----------------------------------------------------------------------

-define(TT2S_BEST_VERSION, v3).

token_tag2string(Tag) ->
    token_tag2string(Tag, ?TT2S_BEST_VERSION).

token_tag2string(Tag, 1) ->
    token_tag2string(Tag, v1);
token_tag2string(Tag, v1) ->
    megaco_compact_text_encoder_v1:token_tag2string(Tag);
token_tag2string(Tag, 2) ->
    token_tag2string(Tag, v2);
token_tag2string(Tag, v2) ->
    megaco_compact_text_encoder_v2:token_tag2string(Tag);
token_tag2string(Tag, 3) ->
    token_tag2string(Tag, v3);
token_tag2string(Tag, v3) ->
    megaco_compact_text_encoder_v3:token_tag2string(Tag);
token_tag2string(Tag, prev3b) ->
    megaco_compact_text_encoder_prev3b:token_tag2string(Tag);
token_tag2string(Tag, prev3c) ->
    megaco_compact_text_encoder_prev3c:token_tag2string(Tag);
token_tag2string(Tag, _Vsn) ->
    token_tag2string(Tag, ?TT2S_BEST_VERSION).


%% d(F) ->
%%     d(F, []).

%% d(F, A) ->
%%     d(get(dbg), F, A).

%% d(true, F, A) ->
%%     io:format("~p:" ++ F ++ "~n", [?MODULE|A]);
%% d(_, _, _) ->
%%     ok.
