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
 
-module(ic_fetch).

-include("icforms.hrl").

-compile(export_all).


name2type( G, Name ) ->
    S = icgen:tktab( G ),
    ScopedName = lists:reverse(string:tokens(Name,"_")),
    InfoList = ets:lookup( S, ScopedName ),
    filter( InfoList ).


%% This is en overloaded function,
%% differs in input on unions
member2type(G, X, I) when record(X, union)->
    Name = icgen:get_id2(I),
    case lists:keysearch(Name,2,element(6,X#union.tk)) of
	false ->
	    error;
	{value,Rec} ->
	    ic_fetch:fetchType(element(3,Rec))
    end;
member2type( G, SName, MName ) ->
    S = icgen:tktab( G ),
    SNList = lists:reverse(string:tokens(SName,"_")),
    ScopedName = [MName | SNList],
    InfoList = ets:lookup( S, ScopedName ),
    case filter( InfoList ) of
	error ->
	    error;
	Other ->
	    Other
    end.


filter( [] ) ->
    error;
filter( [I | Is ] ) ->
    case I of
	{ _, member, { _, TKINFO }, _ } ->
	    fetchType( TKINFO );

        { _, struct, _, _ } ->
	    struct;

	{ _, typedef, TKINFO, _ } ->
	    fetchType( TKINFO );

	{ _, module, _, _ } ->
	    module;

	{ _, interface, _, _ } ->
	    interface;

	{ _, op, _, _ } ->
	    op;

	{ _,enum, _, _ } ->
	    enum;

	{ _, spellcheck } ->
	    filter( Is );
	
	_ ->
	    error
    end.


fetchType( { tk_sequence, _, _ } ) ->
    sequence;
fetchType( { tk_array, _, _ } ) ->
    array;
fetchType( { tk_struct, _, _, _} ) ->
    struct;
fetchType( { tk_string, _} ) ->
    string;
fetchType( tk_short ) ->
    short;
fetchType( tk_long ) ->
    long;
fetchType( tk_ushort ) ->
    ushort;
fetchType( tk_ulong ) ->
    ulong;
fetchType( tk_float ) ->
    float;
fetchType( tk_double ) ->
    double;
fetchType( tk_boolean ) ->
    boolean;
fetchType( tk_char ) ->
    char;
fetchType( tk_octet ) ->
    octet;
fetchType( { tk_enum, _, _, _ } ) ->
    enum;
fetchType( { tk_union, _, _, _, _, _ } ) ->
    union;
fetchType( tk_any ) ->
    any;
fetchType( _ ) ->
    error.

isBasicTypeOrEterm(G, N, S) ->
    case isBasicType(G, N, S) of
	true ->
	    true;
	false ->
	    isEterm(G, N, S)
    end.


isEterm(G, N, S) when element(1, S) == scoped_id -> 
    {FullScopedName, _, TK, _} = icgen:get_full_scoped_name(G, N, S),
    case icgen:get_basetype(G, icgen:to_undersc(FullScopedName)) of
	"erlang_term" ->
	    true;
	"ETERM*" ->
	    true;
	X ->
	    false
    end;
isEterm(G, Ni, X) -> 
    false.

isBasicType(G, N, S) when element(1, S) == scoped_id -> 
    {_, _, TK, _} = icgen:get_full_scoped_name(G, N, S),
    isBasicType(fetchType(TK));
isBasicType(G, N, {string, _} ) -> 
    false;
isBasicType(G, N, {Type, _} ) -> 
    isBasicType(Type).


isBasicType( G, Name ) ->
    isBasicType( name2type( G, Name ) ).


isBasicType( Type ) ->
    lists:member(Type,
		 [tk_short,short,
		  tk_long,long,
		  tk_ushort,ushort,
		  tk_ulong,ulong,
		  tk_float,float,
		  tk_double,double,
		  tk_boolean,boolean,
		  tk_char,char,
		  tk_octet,octet]).



isString(G, N, T) when element(1, T) == scoped_id ->
    case icgen:get_full_scoped_name(G, N, T) of
	{FullScopedName, _, {'tk_string',_}, _} ->
	    true;
	_ ->
	    false
    end; 
isString(G, N, T)  when record(T, string) ->
    true;
isString(G, N, Other) ->
    false. 


isArray(G, N, T) when element(1, T) == scoped_id ->
    case icgen:get_full_scoped_name(G, N, T) of
	{FullScopedName, _, {'tk_array', _, _}, _} ->
	    true;
	_ ->
	    false
    end; 
isArray(G, N, T)  when record(T, array) ->
    true;
isArray(G, N, Other) ->
    false. 



isStruct(G, N, T) when element(1, T) == scoped_id ->
    case icgen:get_full_scoped_name(G, N, T) of
	{FullScopedName, _, {'tk_struct', _, _, _}, _} ->
	    true;
	_ ->
	    false
    end; 
isStruct(G, N, T)  when record(T, struct) ->
    true;
isStruct(G, N, Other) ->
    false.



isUnion(G, N, T) when element(1, T) == scoped_id ->
    case icgen:get_full_scoped_name(G, N, T) of
	{FullScopedName, _, {'tk_union', _, _, _,_,_}, _} ->
	    true;
	_Other ->
	    false
    end; 
isUnion(G, N, T)  when record(T, union) ->
    true;
isUnion(G, N, _Other) ->
    false.



%%------------------------------------------------------------
%%
%% Always fetchs TK of a record.
%%
%%------------------------------------------------------------
fetchTk(G,N,X) ->
    case ic_forms:get_tk(X) of
	undefined ->
	    searchTk(G,ictk:get_IR_ID(G, N, X));
	TK ->
	    TK
    end.


%%------------------------------------------------------------
%%
%% seek type code when not accessible by get_tk/1
%%
%%------------------------------------------------------------
searchTk(G,IR_ID) ->
    S = icgen:tktab(G),
    case catch searchTk(S,IR_ID,typedef) of
	{value,TK} ->
	    TK;
	_ -> %% false / exit
 	    case catch searchTk(S,IR_ID,struct) of
		{value,TK} ->
		    TK;
		_  ->  %% false / exit
		    case catch searchTk(S,IR_ID,union) of
			{value,TK} ->
			    TK;
			_ ->
			    undefined
		    end
	    end
    end.


searchTk(S,IR_ID,Type) ->
    L = lists:flatten(ets:match(S,{'_',Type,'$1','_'})),
    case lists:keysearch(IR_ID,2,L) of
	{value,TK} ->
	    {value,TK};
	false ->
	    searchInsideTks(L,IR_ID)
    end.


searchInsideTks([],_IR_ID) ->
    false;
searchInsideTks([{tk_array,TK,_}|Xs],IR_ID) ->
    case searchIncludedTk(TK,IR_ID) of
	{value,TK} ->
	    {value,TK};
	false ->
	    searchInsideTks(Xs,IR_ID)
    end.


searchIncludedTk({tk_array,TK,_},IR_ID) ->
    searchIncludedTk(TK,IR_ID);
searchIncludedTk({tk_sequence,TK,_},IR_ID) ->
    searchIncludedTk(TK,IR_ID);
searchIncludedTk(TK,IR_ID) when atom(TK) ->
    false;
searchIncludedTk(TK,IR_ID) ->
    case element(2,TK) == IR_ID of
	true ->
	    {value,TK};
	false ->
	    false
    end.
	









