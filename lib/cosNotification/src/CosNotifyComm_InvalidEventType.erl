%%------------------------------------------------------------
%%
%% Implementation stub file
%% 
%% Target: CosNotifyComm_InvalidEventType
%% Source: /ldisk/daily_build/otp_prebuild_r12b.2008-06-10_20/otp_src_R12B-3/lib/cosNotification/src/CosNotifyComm.idl
%% IC vsn: 4.2.18
%% 
%% This file is automatically generated. DO NOT EDIT IT.
%%
%%------------------------------------------------------------

-module('CosNotifyComm_InvalidEventType').
-ic_compiled("4_2_18").


-include("CosNotifyComm.hrl").

-export([tc/0,id/0,name/0]).



%% returns type code
tc() -> {tk_except,"IDL:omg.org/CosNotifyComm/InvalidEventType:1.0",
                   "InvalidEventType",
                   [{"type",
                     {tk_struct,"IDL:omg.org/CosNotification/EventType:1.0",
                                "EventType",
                                [{"domain_name",{tk_string,0}},
                                 {"type_name",{tk_string,0}}]}}]}.

%% returns id
id() -> "IDL:omg.org/CosNotifyComm/InvalidEventType:1.0".

%% returns name
name() -> "CosNotifyComm_InvalidEventType".



