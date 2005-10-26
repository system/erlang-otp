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
-module(snmpa_network_interface).

-export([behaviour_info/1]).

behaviour_info(callbacks) ->
    [{start_link, 4},
     {info,       1}, 
     {verbosity,  2}];
behaviour_info(_) ->
    undefined.


% behaviour_info(callbacks) ->
%     [{start_link,        4}, 
%      {send_pdu,          5},
%      {send_response_pdu, 6},
%      {discard_pdu,       6},
%      {send_pdu_req,      6},
%      {verbosity,         2}];
% behaviour_info(_) ->
%     undefined.

