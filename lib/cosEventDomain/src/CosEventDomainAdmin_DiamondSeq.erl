%%------------------------------------------------------------
%%
%% Implementation stub file
%% 
%% Target: CosEventDomainAdmin_DiamondSeq
%% Source: /ldisk/daily_build/otp_prebuild_r12b.2008-04-07_20/otp_src_R12B-1/lib/cosEventDomain/src/CosEventDomainAdmin.idl
%% IC vsn: 4.2.17
%% 
%% This file is automatically generated. DO NOT EDIT IT.
%%
%%------------------------------------------------------------

-module('CosEventDomainAdmin_DiamondSeq').
-ic_compiled("4_2_17").


-include("CosEventDomainAdmin.hrl").

-export([tc/0,id/0,name/0]).



%% returns type code
tc() -> {tk_sequence,{tk_sequence,{tk_sequence,tk_long,0},0},0}.

%% returns id
id() -> "IDL:omg.org/CosEventDomainAdmin/DiamondSeq:1.0".

%% returns name
name() -> "CosEventDomainAdmin_DiamondSeq".



