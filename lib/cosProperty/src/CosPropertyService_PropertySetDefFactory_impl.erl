%%----------------------------------------------------------------------
%%<copyright>
%% <year>2000-2007</year>
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
%% File        : CosPropertyService_PropertySetDefFactory_impl.erl
%% Description : 
%%
%%----------------------------------------------------------------------
-module('CosPropertyService_PropertySetDefFactory_impl').

%%----------------------------------------------------------------------
%% Include files
%%----------------------------------------------------------------------
-include_lib("orber/include/corba.hrl").
-include_lib("orber/src/orber_iiop.hrl").
-include("CosPropertyService.hrl").
-include("cosProperty.hrl").

%%----------------------------------------------------------------------
%% External exports
%%----------------------------------------------------------------------
-export([init/1,
	 terminate/2,
	 code_change/3]).

-export([create_propertysetdef/2, 
	 create_constrained_propertysetdef/4, 
	 create_initial_propertysetdef/3]).

%%----------------------------------------------------------------------
%% Internal exports
%%----------------------------------------------------------------------
-export([]).

%%----------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------
-record(state, {}).

%%----------------------------------------------------------------------
%% Macros
%%----------------------------------------------------------------------
-define(checkTCfun,   fun(TC) -> orber_tc:check_tc(TC) end).

%%======================================================================
%% External functions
%%======================================================================
%%----------------------------------------------------------------------
%% Function   : init/1
%% Returns    : {ok, State}          |
%%              {ok, State, Timeout} |
%%              ignore               |
%%              {stop, Reason}
%% Description: Initiates the server
%%----------------------------------------------------------------------
init([]) ->
    {ok, #state{}}.

%%----------------------------------------------------------------------
%% Function   : terminate/2
%% Returns    : any (ignored by gen_server)
%% Description: Shutdown the server
%%----------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%----------------------------------------------------------------------
%% Function   : code_change/3
%% Returns    : {ok, NewState}
%% Description: Convert process state when code is changed
%%----------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%---------------------------------------------------------------------%
%% Function   : create_propertysetdef
%% Arguments  : 
%% Returns    : CosPropertyService::PropertySetDef reference.
%% Description: 
%%----------------------------------------------------------------------
create_propertysetdef(_OE_This, State) ->
    {reply, 
     'CosPropertyService_PropertySetDef':
     oe_create({normal, [], [], [], ?PropertySetDef}, [{pseudo, true}]),
     State}.

%%---------------------------------------------------------------------%
%% Function   : create_constrained_propertysetdef
%% Arguments  : PropTypes - list of property types.
%%              PropDefs  - list of property defs.
%% Returns    : CosPropertyService::PropertySetDef |
%%              {'EXCEPTION', CosPropertyService::ConstraintNotSupported}
%% Description: 
%%----------------------------------------------------------------------
create_constrained_propertysetdef(_OE_This, State, PropTypes, PropDefs) ->
    case lists:all(?checkTCfun, PropTypes) of
	true ->
	    crosscheckTC(PropDefs, PropTypes),
	    {reply, 
	     'CosPropertyService_PropertySetDef':
	     oe_create({normal, PropTypes, PropDefs, [], ?PropertySetDef}, [{pseudo, true}]),
	     State};
	false ->
	    corba:raise(#'CosPropertyService_ConstraintNotSupported'{})
    end.

crosscheckTC([], _) ->
    ok;
crosscheckTC([#'CosPropertyService_PropertyDef'
			 {property_name = Name,
			  property_value = Value,
			  property_mode = _Mode}|T], TCs) ->
    case lists:member(any:get_typecode(Value), TCs) of
	true when Name =/= "" ->
	   crosscheckTC(T, TCs); 
	_ ->
	    corba:raise(#'CosPropertyService_ConstraintNotSupported'{})
    end.

%%---------------------------------------------------------------------%
%% Function   : create_initial_propertysetdef
%% Arguments  : 
%% Returns    : CosPropertyService::PropertySetDef |
%%              {'EXCEPTION', CosPropertyService::MultipleExceptions}
%% Description: 
%%----------------------------------------------------------------------
create_initial_propertysetdef(_OE_This, State, PropDefs) ->
    InitProps = evaluate_propertysetdef(PropDefs),
    {reply, 
     'CosPropertyService_PropertySetDef':
	oe_create({normal, [], [], InitProps, ?PropertySetDef}, [{pseudo, true}]),
     State}.

%%======================================================================
%% Internal functions
%%======================================================================
evaluate_propertysetdef(SetDefs) ->
    evaluate_propertysetdef(SetDefs, [], []).
evaluate_propertysetdef([], NewProperties, []) ->
    %% No exceptions found.
    NewProperties;
evaluate_propertysetdef([], _, Exc) ->
    corba:raise(#'CosPropertyService_MultipleExceptions'{exceptions = Exc});
evaluate_propertysetdef([#'CosPropertyService_PropertyDef'
			 {property_name = Name,
			  property_value = Value,
			  property_mode = Mode}|T], X, Exc) ->
    case orber_tc:check_tc(any:get_typecode(Value)) of
	true ->
	    evaluate_propertysetdef(T, [{Name, Value, Mode}|X], Exc);
	false ->
	    evaluate_propertysetdef(T, X, [#'CosPropertyService_PropertyException'
					   {reason = unsupported_type_code,
					    failing_property_name = Name}|Exc])
    end.



%%======================================================================
%% END OF MODULE
%%======================================================================

