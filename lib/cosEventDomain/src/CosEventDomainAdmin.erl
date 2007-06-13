%%------------------------------------------------------------
%%
%% Implementation stub file
%% 
%% Target: CosEventDomainAdmin
%% Source: /ldisk/daily_build/otp_prebuild_r11b.2007-06-11_19/otp_src_R11B-5/lib/cosEventDomain/src/CosEventDomainAdmin.idl
%% IC vsn: 4.2.13
%% 
%% This file is automatically generated. DO NOT EDIT IT.
%%
%%------------------------------------------------------------

-module('CosEventDomainAdmin').
-ic_compiled("4_2_13").


%% Interface functions
-export(['CycleDetection'/0, 'AuthorizeCycles'/0, 'ForbidCycles'/0]).
-export(['DiamondDetection'/0, 'AuthorizeDiamonds'/0, 'ForbidDiamonds'/0]).

%%%% Constant: 'CycleDetection'
%%
'CycleDetection'() -> "CycleDetection".

%%%% Constant: 'AuthorizeCycles'
%%
'AuthorizeCycles'() -> 0.

%%%% Constant: 'ForbidCycles'
%%
'ForbidCycles'() -> 1.

%%%% Constant: 'DiamondDetection'
%%
'DiamondDetection'() -> "DiamondDetection".

%%%% Constant: 'AuthorizeDiamonds'
%%
'AuthorizeDiamonds'() -> 0.

%%%% Constant: 'ForbidDiamonds'
%%
'ForbidDiamonds'() -> 1.
