%%% This file was automatically generated by snmp_mib_to_hrl v3.0
%%% Date: 12-Apr-2002::09:50:38
-ifndef('SNMPv2-TC').
-define('SNMPv2-TC', true).

-define(snmpv2TC, [1,3,6,1,6,3,0]).

%% Range values


%% Definitions from 'StorageType'
-define('StorageType_readOnly', 5).
-define('StorageType_permanent', 4).
-define('StorageType_nonVolatile', 3).
-define('StorageType_volatile', 2).
-define('StorageType_other', 1).

%% Definitions from 'RowStatus'
-define('RowStatus_destroy', 6).
-define('RowStatus_createAndWait', 5).
-define('RowStatus_createAndGo', 4).
-define('RowStatus_notReady', 3).
-define('RowStatus_notInService', 2).
-define('RowStatus_active', 1).

%% Definitions from 'TruthValue'
-define('TruthValue_false', 2).
-define('TruthValue_true', 1).

%% Default values

-endif.