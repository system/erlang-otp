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
-module(asn1ct_constructed_ber_bin_v2).

-export([gen_encode_sequence/3]).
-export([gen_decode_sequence/3]).
-export([gen_encode_set/3]).
-export([gen_decode_set/3]).
-export([gen_encode_sof/4]).
-export([gen_decode_sof/4]).
-export([gen_encode_choice/3]).
-export([gen_decode_choice/3]).


-include("asn1_records.hrl").

-import(asn1ct_gen, [emit/1,demit/1]).

-define(ASN1CT_GEN_BER,asn1ct_gen_ber_bin_v2).

% the encoding of class of tag bits 8 and 7
-define(UNIVERSAL,   0).
-define(APPLICATION, 16#40).
-define(CONTEXT,     16#80).
-define(PRIVATE,     16#C0).

% primitive or constructed encoding % bit 6
-define(PRIMITIVE,   0).
-define(CONSTRUCTED, 2#00100000).




%%===============================================================================
%%===============================================================================
%%===============================================================================
%%  Encode/decode SEQUENCE (and SET)
%%===============================================================================
%%===============================================================================
%%===============================================================================

gen_encode_sequence(Erules,Typename,D) when record(D,type) ->
    asn1ct_name:start(),
    asn1ct_name:new(term),
    asn1ct_name:new(bytes),
    
    %% if EXTERNAL type the input value must be transformed to 
    %% ASN1 1990 format
    ValName = 
	case Typename of
	    ['EXTERNAL'] ->
		emit([indent(4),
		      "NewVal = asn1rt_check:transform_to_EXTERNAL1990(Val),",
		      nl]),
		"NewVal";
	    _ ->
	    "Val"
	end,

    {SeqOrSet,TableConsInfo,CompList} = 
	case D#type.def of
	    #'SEQUENCE'{tablecinf=TCI,components=CL} -> 
		{'SEQUENCE',TCI,CL};
	    #'SET'{tablecinf=TCI,components=CL} -> 
		{'SET',TCI,CL}
	end,
    Ext = extensible(CompList),
    CompList1 = case CompList of
		    {Rl,El} -> Rl ++ El;
		    _ -> CompList
		end,
    
%% don't match recordname for now, because of compatibility reasons
%%    emit(["{'",asn1ct_gen:list2rname(Typename),"'"]),
    emit(["{_"]),
    case length(CompList1) of
	0 -> 
	    true;
	CompListLen ->
	    emit([","]),
	    mkcindexlist([Tc || Tc <- lists:seq(1,CompListLen)])
    end,
    emit(["} = ",ValName,",",nl]),
    EncObj =
	case TableConsInfo of
	    {_,_,_,{no_unique,_}} ->
		false;
	    %% ObjectSet, name of the object set in constraints
	    %% 
	    {ObjectSet,AttrN,N,UniqueFieldName} -> %% N is index of attribute that determines constraint
		OSDef =
		    case ObjectSet of
			{Module,OSName} ->
			    asn1_db:dbget(Module,OSName);
			OSName ->
			    asn1_db:dbget(get(currmod),OSName)
		    end,
%		io:format("currmod: ~p~nOSName: ~p~nAttrN: ~p~nN: ~p~nUniqueFieldName: ~p~n",
%			  [get(currmod),OSName,AttrN,N,UniqueFieldName]),
		case (OSDef#typedef.typespec)#'ObjectSet'.gen of
		    true ->
			ObjectEncode = lists:concat(['Obj',AttrN]),
			emit([ObjectEncode," = ",nl]),
			emit(["   'getenc_",ObjectSet,"'(",{asis,UniqueFieldName},
			      ", ",nl]),
			emit([indent(35),"Cindex",N,"),",nl]),
			{AttrN,ObjectEncode};
		    _ ->
			false
		end;
	    _ ->
		false
	end,

    gen_enc_sequence_call(Erules,Typename,CompList1,1,Ext,EncObj),

    emit([nl,"   BytesSoFar = "]),
    case SeqOrSet of
	'SET' when (D#type.def)#'SET'.sorted == dynamic ->
	    emit("?RT_BER:dynamicsort_SET_components(["),
	    mkvlist(asn1ct_name:all(encBytes)),
	    emit(["]),",nl]);
	_ ->
	    emit("["),
	    mkvlist(asn1ct_name:all(encBytes)),
	    emit(["],",nl])
    end,
    emit("LenSoFar = "),
    case asn1ct_name:all(encLen) of
	[] -> emit("0");
	AllLengths -> 
	    mkvplus(AllLengths)
    end,
    emit([",",nl]),
    emit(["?RT_BER:encode_tags(TagIn, BytesSoFar, LenSoFar)."
	  ,nl]).

gen_decode_sequence(Erules,Typename,D) when record(D,type) ->
    asn1ct_name:start(),
    asn1ct_name:new(tag),
    #'SEQUENCE'{tablecinf=TableConsInfo,components=CList} = D#type.def,
    Ext = extensible(CList),
    CompList = case CList of
		   {Rl,El}  -> Rl ++ El;
		   _ -> CList
	       end,

    emit(["   %%-------------------------------------------------",nl]),
    emit(["   %% decode tag and length ",nl]),
    emit(["   %%-------------------------------------------------",nl]),

    asn1ct_name:new(tlv),
    case CompList of
	[] -> % empty sequence
	    true;
	_ ->
	    emit([{curr,tlv}," = "])
    end,
    emit(["?RT_BER:match_tags(",{prev,tlv},",TagIn), ",nl]),
    asn1ct_name:new(tlv),
    asn1ct_name:new(v),

    {DecObjInf,UniqueFName} =
	case TableConsInfo of
	    {ObjectSet,AttrN,_N,UniqueFieldName} ->%% N is index of attribute that determines constraint
		F = fun(#'ComponentType'{typespec=CT})->
			    case {CT#type.constraint,CT#type.tablecinf} of
				{[],[{objfun,_}|_]} -> true;
				_ -> false
			    end
		    end,
		case lists:any(F,CompList) of
		    true -> % when component relation constraint establish
			%% relation from a component to another components
			%% subtype component
			{{AttrN,{deep,ObjectSet,UniqueFieldName}},
			 UniqueFieldName};
		    false ->
			{{AttrN,ObjectSet},UniqueFieldName}
		end;
	    _ ->
		{false,false}
	end,
    case gen_dec_sequence_call(Erules,Typename,CompList,Ext,DecObjInf) of
	no_terms -> % an empty sequence	    
	    emit([nl,nl]),
	    demit(["Result = "]), %dbg
	    %% return value as record
	    asn1ct_name:new(rb),
	    emit(["   {'",asn1ct_gen:list2rname(Typename),"'}.",nl,nl]);
	{LeadingAttrTerm,PostponedDecArgs} ->
	    emit([com,nl,nl]),
	    case {LeadingAttrTerm,PostponedDecArgs} of
		{[],[]} ->
		    ok;
		{_,[]} ->
		    ok;
		{[{ObjSet,LeadingAttr,Term}],PostponedDecArgs} ->
		    DecObj = lists:concat(['DecObj',LeadingAttr,Term]),
		    emit([DecObj," =",nl,"   'getdec_",ObjSet,"'(",
			  {asis,UniqueFName},", ",Term,"),",nl]),
		    gen_dec_postponed_decs(DecObj,PostponedDecArgs)
	    end,
	    demit(["Result = "]), %dbg
	    %% return value as record
	    case Ext of
		{ext,_,_} -> 
		    emit(["case ",{prev,tlv}," of [] -> true; _ -> true end, % ... extra fields skipped",nl]);
		noext -> 
		    emit(["case ",{prev,tlv}," of",nl,
			  "[] -> true;",
			  "_ -> exit({error,{asn1, {unexpected,",{prev,tlv},
			  "}}}) % extra fields not allowed",nl,
			  "end,",nl])
	    end,
	    asn1ct_name:new(rb),
	    case Typename of
		['EXTERNAL'] ->
		    emit(["   OldFormat={'",asn1ct_gen:list2rname(Typename),
			  "', "]),
		    mkvlist(asn1ct_name:all(term)),
		    emit(["},",nl]),
		    emit(["    asn1rt_check:transform_to_EXTERNAL1994",
			  "(OldFormat).",nl]);
		_ ->
		    emit(["   {'",asn1ct_gen:list2rname(Typename),"', "]),
		    mkvlist(asn1ct_name:all(term)),
		    emit(["}.",nl,nl])
	    end
    end.

gen_dec_postponed_decs(_,[]) ->
    emit(nl);
gen_dec_postponed_decs(DecObj,[{_Cname,{FirstPFN,PFNList},Term,TmpTerm,_Tag}|Rest]) ->
%    asn1ct_name:new(term),
    asn1ct_name:new(tmpterm),
    asn1ct_name:new(reason),
    asn1ct_name:new(tmptlv),

%    emit({"{",{curr,term},", _, _} = ",nl}),
%     if
% 	N > 1 ->
% 	    asn1ct_name:new(term),
% 	    emit({{curr,term}," = ",nl});
% 	true ->
% 	    ok
%     end,

%     Tmpterm2=
% 	if
% 	    Tag == [] ->
% 		TmpTerm;
% 	    true ->
% 		emit({indent(3),"{",{curr,tmptlv},",_} = ?RT_BER:decode(",TmpTerm,"),",nl}),
% 		{curr,tmptlv}
% 	end,
    
%    emit({indent(3),"{",{curr,tmptlv},",_} = ?RT_BER:decode(",TmpTerm,"),",nl}),
%    Tmpterm2 = {curr,tmptlv},

    emit([Term," = ",nl]),
    emit([indent(3),"case (catch ",DecObj,"(",{asis,FirstPFN},
%	  ", ",Term,", ", {asis,Tag},", ",{asis,PFNList},")) of",nl}),
%	  ", ",Term,", ",{asis,PFNList},")) of",nl}),
	  ", ",TmpTerm,", ",{asis,PFNList},")) of",nl]),
    emit([indent(6),"{'EXIT', ",{curr,reason},"} ->",nl]),
    emit([indent(9),"exit({'Type not compatible with table constraint',",
	  {curr,reason},"});",nl]),
    emit([indent(6),{curr,tmpterm}," ->",nl]),
    emit([indent(9),{curr,tmpterm},nl]),
%     if
% 	N == 1 ->
% 	    emit({indent(3),"end",nl}), % end of begin
% 	    emit({indent(3),"end,",nl});
% 	true ->
% 	    emit({indent(3),"end,",nl})
%     end,
    emit([indent(3),"end,",nl]),
    gen_dec_postponed_decs(DecObj,Rest).


%%============================================================================
%%  Encode/decode SET
%%
%%============================================================================

gen_encode_set(Erules,Typename,D) when record(D,type) ->
    gen_encode_sequence(Erules,Typename,D).

gen_decode_set(Erules,Typename,D) when record(D,type) ->
    asn1ct_name:start(),
    asn1ct_name:new(term),
    asn1ct_name:new(tag),
    #'SET'{tablecinf=TableConsInfo,components=TCompList} = D#type.def,
    Ext = extensible(TCompList),
    CompList = case TCompList of
		   {Rl,El} -> Rl ++ El;
		   _ -> TCompList
	       end,

    asn1ct_name:clear(),
    asn1ct_name:new(tlv),
    emit([{curr,tlv},
	  " = ?RT_BER:match_tags(",{prev,tlv},",TagIn), ",nl]),
    asn1ct_name:new(v),


    {DecObjInf,UniqueFName} =
	case TableConsInfo of
	    {ObjectSet,AttrN,_N,UniqueFieldName} ->%% N is index of attribute that determines constraint
		F = fun(#'ComponentType'{typespec=CT})->
			    case {CT#type.constraint,CT#type.tablecinf} of
				{[],[{objfun,_}|_]} -> true;
				_ -> false
			    end
		    end,
		case lists:any(F,CompList) of
		    true -> % when component relation constraint establish
			%% relation from a component to another components
			%% subtype component
			{{AttrN,{deep,ObjectSet,UniqueFieldName}},
			 UniqueFieldName};
		    false ->
			{{AttrN,ObjectSet},UniqueFieldName}
		end;
	    _ ->
		{false,false}
	end,

    case CompList of
	[] -> % empty set
	    true;
	_ ->
	    emit(["SetFun = fun(FunTlv) ->", nl]),
	    emit(["case FunTlv of ",nl]),
	    NextNum = gen_dec_set_cases(Erules,Typename,CompList,1),
	    emit([indent(6), {curr,else}," -> ",nl,
		  indent(9),"{",NextNum,", ",{curr,else},"}",nl]),
	    emit([indent(3),"end",nl]),
	    emit([indent(3),"end,",nl]),

	    emit(["PositionList = [SetFun(TempTlv)|| TempTlv <- ",{curr,tlv},"],",nl]),
	    asn1ct_name:new(tlv),
	    emit([{curr,tlv}," = [Stlv || {_,Stlv} <- lists:sort(PositionList)],",nl]),
	    asn1ct_name:new(tlv)

    end,
    case gen_dec_sequence_call(Erules,Typename,CompList,Ext,DecObjInf) of
	no_terms -> % an empty sequence	    
	    emit([nl,nl]),
	    demit(["Result = "]), %dbg
	    %% return value as record
	    emit(["   {'",asn1ct_gen:list2rname(Typename),"'}.",nl]);
	{LeadingAttrTerm,PostponedDecArgs} ->
	    emit([com,nl,nl]),
	    case {LeadingAttrTerm,PostponedDecArgs} of
		{[],[]} ->
		    ok;
		{_,[]} ->
		    ok;
		{[{ObjSet,LeadingAttr,Term}],PostponedDecArgs} ->
		    DecObj = lists:concat(['DecObj',LeadingAttr,Term]),
		    emit([DecObj," =",nl,"   'getdec_",ObjSet,"'(",
			  {asis,UniqueFName},", ",Term,"),",nl]),
		    gen_dec_postponed_decs(DecObj,PostponedDecArgs)
	    end,
	    demit(["Result = "]), %dbg
	    %% return value as record
	    case Ext of
		{ext,_,_} -> 
		    emit(["case ",{prev,tlv}," of [] -> true; _ -> true end, % ... extra fields skipped",nl]);
		noext -> 
		    emit(["case ",{prev,tlv}," of",nl,
			  "[] -> true;",
			  "_ -> exit({error,{asn1, {unexpected,",{prev,tlv},
			  "}}}) % extra fields not allowed",nl,
			  "end,",nl])
	    end,
	    emit(["   {'",asn1ct_gen:list2rname(Typename),"', "]),
	    mkvlist(asn1ct_name:all(term)),
	    emit(["}.",nl])
    end.


%%===============================================================================
%%===============================================================================
%%===============================================================================
%%  Encode/decode SEQUENCE OF and SET OF
%%===============================================================================
%%===============================================================================
%%===============================================================================

gen_encode_sof(Erules,Typename,_InnerTypename,D) when record(D,type) ->
    asn1ct_name:start(),
    {SeqOrSetOf, Cont} = D#type.def,

    Objfun = case D#type.tablecinf of
		 [{objfun,_}|_R] ->
		     ", ObjFun";
		 _ ->
		     ""
	     end,

    emit(["   {EncBytes,EncLen} = 'enc_",asn1ct_gen:list2name(Typename),
	  "_components'(Val",Objfun,",[],0),",nl]),

    emit(["   ?RT_BER:encode_tags(TagIn, EncBytes, EncLen).",nl,nl]),

    gen_encode_sof_components(Erules,Typename,SeqOrSetOf,Cont).
    

gen_decode_sof(Erules,TypeName,_InnerTypeName,D) when record(D,type) ->
    asn1ct_name:start(),
    {SeqOrSetOf, _TypeTag, Cont} = 
	case D#type.def of
	    {'SET OF',_Cont} -> {'SET OF','SET',_Cont};
	    {'SEQUENCE OF',_Cont} -> {'SEQUENCE OF','SEQUENCE',_Cont}
	end,
    TypeNameSuffix = asn1ct_gen:constructed_suffix(SeqOrSetOf,Cont#type.def),
    
    emit(["   %%-------------------------------------------------",nl]),
    emit(["   %% decode tag and length ",nl]),
    emit(["   %%-------------------------------------------------",nl]),
    
    asn1ct_name:new(tlv),
    emit([{curr,tlv},
	  " = ?RT_BER:match_tags(",{prev,tlv},",TagIn), ",nl]),
    asn1ct_name:new(v),

    emit(["["]),

    InnerType = asn1ct_gen:get_inner(Cont#type.def),
    ContName = case asn1ct_gen:type(InnerType) of
		   Atom when atom(Atom) -> Atom;
		   _ -> TypeNameSuffix
	       end,
%% fix me
    ObjFun =
	case D#type.tablecinf of
	    [{objfun,_}|_R] ->
		", ObjFun";
	    _ ->
		[]
	end,
    gen_dec_line(Erules,TypeName,ContName,[],Cont,mandatory,ObjFun),
    %%    gen_dec_line_sof(Erules,Typename,ContName,Cont,ObjFun),
    emit([" || ",{curr,v}," <- ",{curr,tlv},"].",nl,nl,nl]).
    

gen_encode_sof_components(Erules,Typename,SeqOrSetOf,Cont) 
  when record(Cont,type)->

    {Objfun,EncObj} = 
	case Cont#type.tablecinf of
	    [{objfun,_}|_R] ->
		{", ObjFun",{no_attr,"ObjFun"}};
	    _ ->
		{"",false}
	end,
    emit(["'enc_",asn1ct_gen:list2name(Typename),
	  "_components'([]",Objfun,", AccBytes, AccLen) -> ",nl]),

    case catch lists:member(der,get(encoding_options)) of
	true ->
	    emit([indent(3),
		  "{?RT_BER:dynamicsort_SETOF(AccBytes),AccLen};",nl,nl]);
	_ ->
	    emit([indent(3),"{lists:reverse(AccBytes),AccLen};",nl,nl])
    end,
    emit(["'enc_",asn1ct_gen:list2name(Typename),
	  "_components'([H|T]",Objfun,",AccBytes, AccLen) ->",nl]),
    TypeNameSuffix = asn1ct_gen:constructed_suffix(SeqOrSetOf,Cont#type.def),
    gen_enc_line(Erules,Typename,TypeNameSuffix,Cont,"H",3,
		 mandatory,"{EncBytes,EncLen} = ",EncObj),
    emit([",",nl]),
    emit([indent(3),"'enc_",asn1ct_gen:list2name(Typename),
	  "_components'(T",Objfun,","]), 
    emit(["[EncBytes|AccBytes], AccLen + EncLen).",nl,nl]).

%%============================================================================
%%  Encode/decode CHOICE
%%
%%============================================================================

gen_encode_choice(Erules,Typename,D) when record(D,type) ->
    ChoiceTag = D#type.tag,
    {'CHOICE',CompList} = D#type.def,
    Ext = extensible(CompList),
    CompList1 = case CompList of
		    {Rl,El} -> Rl ++ El;
		    _ -> CompList
		end,
    gen_enc_choice(Erules,Typename,ChoiceTag,CompList1,Ext),
    emit([nl,nl]).

gen_decode_choice(Erules,Typename,D) when record(D,type) ->
    asn1ct_name:start(),
    asn1ct_name:new(bytes),
    ChoiceTag = D#type.tag,
    {'CHOICE',CompList} = D#type.def,
    Ext = extensible(CompList),
    CompList1 = case CompList of
		    {Rl,El} -> Rl ++ El;
		    _ -> CompList
		end,
    gen_dec_choice(Erules,Typename,ChoiceTag,CompList1,Ext),
    emit([".",nl]).


%%============================================================================
%%  Encode SEQUENCE
%%
%%============================================================================

gen_enc_sequence_call(Erules,TopType,[#'ComponentType'{name=Cname,typespec=Type,prop=Prop}|Rest],Pos,Ext,EncObj) ->
    asn1ct_name:new(encBytes),
    asn1ct_name:new(encLen),
    Element = 
	case TopType of
	    ['EXTERNAL'] ->
		io_lib:format("Cindex~w",[Pos]);
	    _ ->
		io_lib:format("Cindex~w",[Pos])
	end,
    InnerType = asn1ct_gen:get_inner(Type#type.def),
    print_attribute_comment(InnerType,Pos,Cname,Prop),
    gen_enc_line(Erules,TopType,Cname,Type,Element,3,Prop,EncObj),
    case Rest of
	[] ->
	    emit([com,nl]);
	_ ->
	    emit([com,nl]),
	    gen_enc_sequence_call(Erules,TopType,Rest,Pos+1,Ext,EncObj)
    end;

gen_enc_sequence_call(_Erules,_TopType,[],_Num,_,_) ->
	true.

%%============================================================================
%%  Decode SEQUENCE
%%
%%============================================================================

gen_dec_sequence_call(Erules,TopType,CompList,Ext,DecObjInf) ->
    gen_dec_sequence_call1(Erules,TopType, CompList, 1, Ext,DecObjInf,[],[]).


gen_dec_sequence_call1(Erules,TopType,[#'ComponentType'{name=Cname,typespec=Type,prop=Prop,tags=Tags}|Rest],Num,Ext,DecObjInf,LeadingAttrAcc,ArgsAcc) ->
    {LA,PostponedDec} = 
	gen_dec_component(Erules,TopType,Cname,Tags,Type,Num,Prop,
			  Ext,DecObjInf),
    case Rest of
	[] ->
	    {LA ++ LeadingAttrAcc,PostponedDec ++ ArgsAcc};
	_ ->
	    emit([com,nl]),
	    asn1ct_name:new(bytes),
	    gen_dec_sequence_call1(Erules,TopType,Rest,Num+1,Ext,DecObjInf,
				   LA++LeadingAttrAcc,PostponedDec++ArgsAcc)
    end;

gen_dec_sequence_call1(_Erules,_TopType,[],1,_,_,_,_) ->
    no_terms.


%%----------------------------
%%SEQUENCE mandatory
%%----------------------------

gen_dec_component(Erules,TopType,Cname,CTags,Type,Pos,Prop,Ext,DecObjInf) ->
    InnerType = 
	case asn1ct_gen:get_constraint(Type#type.constraint,
				       tableconstraint_info) of
	    no ->
		asn1ct_gen:get_inner(Type#type.def);
	    _ ->
		Type#type.def
	end,
    Prop1 = case {Prop,Ext} of
		{mandatory,{ext,Epos,_}} when Pos >= Epos ->
		    'OPTIONAL';
		_ ->
		    Prop
	    end,
    print_attribute_comment(InnerType,Pos,Cname,Prop1),
    asn1ct_name:new(term),
    case {Prop1,InnerType} of
	{_,{typefield,_}} ->
	    asn1ct_name:new(tmpterm),
	    emit(["[",{curr,v},"|",{curr,tlv},"] = ",{prev,tlv},", ",nl]),
	    emit([nl,"  ",{curr,tmpterm}," = "]);
	{_,{objectfield,_,_}} ->
	    asn1ct_name:new(tmpterm),
	    emit(["[",{curr,v},"|",{curr,tlv},"] = ",{prev,tlv},", ",nl]),
	    emit([nl,"  ",{curr,tmpterm}," = "]);
	{mandatory,_} ->
	    emit(["[",{curr,v},"|",{curr,tlv},"] = ",{prev,tlv},", ",nl,
		  {curr,term}," = "]);
	_ ->
	    asn1ct_name:new(tag),
	    emit(["{",{curr,term},",",{curr,tlv},"} = "])
    end,
    asn1ct_name:new(rb),
    PostponedDec = 
	gen_dec_line(Erules,TopType,Cname,CTags,Type,Prop1,DecObjInf),
    asn1ct_name:new(v),
    asn1ct_name:new(tlv),
    asn1ct_name:new(form),
    PostponedDec.




gen_dec_set_cases(_Erules,_TopType,[],Pos) ->
    Pos;
gen_dec_set_cases(Erules,TopType,[Comp|RestComps],Pos) ->
    Name = Comp#'ComponentType'.name,
    Type = Comp#'ComponentType'.typespec,
    CTags = Comp#'ComponentType'.tags,
    
    emit([indent(6),"%",Name,nl]),
    Tags = case Type#type.tag of
	       [] -> % this is a choice without explicit tag
		   [(?ASN1CT_GEN_BER:decode_class(T1class) bsl 10) + T1number|| 
		       {T1class,T1number} <- CTags];
               [FirstTag|_] ->
		   [(?ASN1CT_GEN_BER:decode_class(FirstTag#tag.class) bsl 10) + FirstTag#tag.number]
	   end,
    CaseFun = fun(TagList=[H|T],Fun) ->
		      Semicolon = case TagList of
				      [_Tag1,_|_] -> [";",nl];
				      _ -> ""
				  end,
		      emit(["TTlv = {",H,",_} ->",nl]),
		      emit([indent(4),"{",Pos,", TTlv}",Semicolon]),
		      Fun(T,Fun);
		 ([],_) ->
		      true
	      end,
    CaseFun(Tags,CaseFun),
    emit([";",nl]),
    gen_dec_set_cases(Erules,TopType,RestComps,Pos+1).



%%---------------------------------------------
%%  Encode CHOICE
%%---------------------------------------------
%% for BER we currently do care (a little) if the choice has an EXTENSIONMARKER


gen_enc_choice(Erules,TopType,Tag,CompList,_Ext) ->
    gen_enc_choice1(Erules,TopType,Tag,CompList,_Ext).

gen_enc_choice1(Erules,TopType,_Tag,CompList,_Ext) ->
    asn1ct_name:clear(),
    emit(["   {EncBytes,EncLen} = case element(1,Val) of",nl]),
    gen_enc_choice2(Erules,TopType,CompList),
    emit([nl,"   end,",nl,nl]),
    
    emit(["?RT_BER:encode_tags(TagIn, EncBytes, EncLen).",nl]).


gen_enc_choice2(Erules,TopType,[H1|T]) when record(H1,'ComponentType') ->
    Cname = H1#'ComponentType'.name,
    Type = H1#'ComponentType'.typespec,
    emit(["      ",{asis,Cname}," ->",nl]),
    {Encobj,Assign} =
	case asn1ct_gen:get_constraint(Type#type.constraint,
				       tableconstraint_info) of
	    no ->
		{false,[]};
	    _ ->
		asn1ct_name:new(tmpBytes),
		asn1ct_name:new(encBytes),
		asn1ct_name:new(encLen),
		Emit = ["{",{curr,tmpBytes},", _} = "],
		{{no_attr,"ObjFun"},Emit}
	end,
    gen_enc_line(Erules,TopType,Cname,Type,"element(2,Val)",9,
		 mandatory,Assign,Encobj),
    case Encobj of
	false -> ok;
	_ ->
	    emit([",",nl,indent(9),"{",{curr,encBytes},", ",
		  {curr,encLen},"}"])
    end,
    emit([";",nl]),
    case T of 
	[] ->
	    emit([indent(6), "Else -> ",nl,
		  indent(9),"exit({error,{asn1,{invalid_choice_type,Else}}})"]);
	_ ->
	    true
    end,
    gen_enc_choice2(Erules,TopType,T);

gen_enc_choice2(_Erules,_TopType,[])  ->
    true.




%%--------------------------------------------
%%  Decode CHOICE
%%--------------------------------------------

gen_dec_choice(Erules,TopType, _ChTag, CompList, Ext) ->
    asn1ct_name:clear(),
    asn1ct_name:new(tlv),
    emit([{curr,tlv},
	  " = ?RT_BER:match_tags(",{prev,tlv},",TagIn), ",nl]),
    asn1ct_name:new(tlv),
    asn1ct_name:new(v),
    emit(["case (case ",{prev,tlv},
	  " of [Ctemp",{prev,tlv},"] -> Ctemp",{prev,tlv},
	  "; _ -> ",{prev,tlv}," end)"," of",nl]),
    asn1ct_name:new(tagList),
    asn1ct_name:new(choTags),
    gen_dec_choice_cases(Erules,TopType,CompList),
    emit([indent(6), {curr,else}," -> ",nl]),
    case Ext of
	noext ->
	    emit([indent(9),"exit({error,{asn1,{invalid_choice_tag,",
		  {curr,else},"}}})",nl]);
	_ ->
	    emit([indent(9),"{asn1_ExtAlt, ?RT_BER:encode(",{curr,else},")}",nl])
    end,
    emit([indent(3),"end",nl]),
    asn1ct_name:new(tag),
    asn1ct_name:new(else).


gen_dec_choice_cases(_Erules,_TopType, []) ->
    ok;
gen_dec_choice_cases(Erules,TopType, [H|T]) ->
    Cname = H#'ComponentType'.name,
    Type = H#'ComponentType'.typespec,
    Prop = H#'ComponentType'.prop,
    Tags = Type#type.tag,
    Fcases  = fun([{T1class,T1number}|Tail],Fun) ->		      
		      emit([indent(4),{curr,v}," = {",
			    (?ASN1CT_GEN_BER:decode_class(T1class) bsl 10) +
			    T1number,",_} -> ",nl]),
		      emit([indent(8),"{",{asis,Cname},", "]),
		      gen_dec_line(Erules,TopType,Cname,[],Type,Prop,false),
		      emit(["};",nl,nl]),
		      Fun(Tail,Fun);
		 ([],_) ->
		      ok
	      end,
    emit([nl,"%% '",Cname,"'",nl]),
    case Tags of
	[] -> % choice without explicit tags
	    Fcases(H#'ComponentType'.tags,Fcases);
	[FirstT|RestT] -> 
	    emit([indent(4),"{",
		  (?ASN1CT_GEN_BER:decode_class(FirstT#tag.class) bsl 10) +
		  FirstT#tag.number,", ",{curr,v},"} -> ",nl]),
	    emit([indent(8),"{",{asis,Cname},", "]),
	    gen_dec_line(Erules,TopType,Cname,[],Type#type{tag=RestT},Prop,false),
	    emit(["};",nl,nl])
    end,
    gen_dec_choice_cases(Erules,TopType, T).



%%---------------------------------------
%% Generate the encode/decode code 
%%---------------------------------------

gen_enc_line(Erules,TopType,Cname,Type=#type{constraint=
					     [{tableconstraint_info,_}],
					     def={typefield,_}},
	     Element,Indent,OptOrMand=mandatory,EncObj) 
  when list(Element) ->
    asn1ct_name:new(tmpBytes),
    gen_enc_line(Erules,TopType,Cname,Type,Element,Indent,OptOrMand,
		 ["{",{curr,tmpBytes},",_} = "],EncObj);
gen_enc_line(Erules,TopType,Cname,Type,Element,Indent,OptOrMand,EncObj) 
  when list(Element) ->
    gen_enc_line(Erules,TopType,Cname,Type,Element,Indent,OptOrMand,
		 ["{",{curr,encBytes},",",{curr,encLen},"} = "],EncObj).

gen_enc_line(Erules,TopType,Cname,Type,Element,Indent,OptOrMand,Assign,EncObj)
  when list(Element) ->
    IndDeep = indent(Indent),
    Tag = lists:reverse([?ASN1CT_GEN_BER:encode_tag_val(
			    ?ASN1CT_GEN_BER:decode_class(X#tag.class),
			    X#tag.form,
			    X#tag.number)
			 || X <- Type#type.tag]),
    InnerType = asn1ct_gen:get_inner(Type#type.def),
    WhatKind = asn1ct_gen:type(InnerType),
    emit(IndDeep),
    emit(Assign),
    gen_optormand_case(OptOrMand,Erules,TopType,Cname,Type,InnerType,WhatKind,
		       Element),
    case Type of
	#type{constraint=[{tableconstraint_info,RefedFieldName}],
	      def={typefield,_}} ->
	    {_LeadingAttrName,Fun} = EncObj,
	    case RefedFieldName of
		{notype,T} ->
		    throw({error,{notype,type_from_object,T}});
		{Name,RestFieldNames} when atom(Name) ->
		    case OptOrMand of
			mandatory -> ok;
			_ ->
			    emit(["{",{curr,tmpBytes},",",{curr,tmpLen},
				  "} = "])
		    end,
		    emit([Fun,"(",{asis,Name},", ",Element,", ",
			  {asis,RestFieldNames},"),",nl]),
		    emit(IndDeep),
		    case OptOrMand of
			mandatory ->
			    emit(["{",{curr,encBytes},",",{curr,encLen},
				  "} = "]),
			    emit(["?RT_BER:encode_open_type(",{curr,tmpBytes},
				  ",",{asis,Tag},")"]);
			_ ->
			    emit(["{",{next,tmpBytes},", _} = "]),
			    emit(["?RT_BER:encode_open_type(",{curr,tmpBytes},
				  ",",{asis,Tag},"),",nl]),
			    emit(IndDeep),
			    emit(["{",{next,tmpBytes},", ",{curr,tmpLen},"}"])
		    end;
		_ ->
		    throw({asn1,{'internal error'}})
	    end;
	#type{constraint=[{tableconstraint_info,_}],
	      def={objectfield,PrimFieldName1,PFNList}} ->
	    {_LeadingAttrName,Fun} = EncObj,
	    emit(["?RT_BER:encode_open_type(",Fun,"(",{asis,PrimFieldName1},
		  ", ",Element,", ",{asis,PFNList},"))"]);
	_ ->
	    case WhatKind of
		{primitive,bif} ->
		    EncType =
			case Type#type.def of
			    {fixedtypevaluefield,_,Btype} ->
				Btype;
			    _ ->
				Type
			end,
		    ?ASN1CT_GEN_BER:gen_encode_prim(ber,EncType,{asis,Tag},
						   Element);
		{notype,_} ->
		    emit(["'enc_",InnerType,"'(",Element,", ",{asis,Tag},")"]);
		'ASN1_OPEN_TYPE' ->
		    ?ASN1CT_GEN_BER:gen_encode_prim(ber,Type,{asis,Tag},
						   Element);
		_ ->
		    {EncFunName, _EncMod, _EncFun} = 
			mkfuncname(TopType,Cname,WhatKind,enc),
		    case {WhatKind,Type#type.tablecinf,EncObj} of
			{{constructed,bif},[{objfun,_}|_R],{_,Fun}} ->
			    emit([EncFunName,"(",Element,", ",{asis,Tag},
				  ", ",Fun,")"]);
			_ ->
			    emit([EncFunName,"(",Element,", ",{asis,Tag},")"])
		    end
	    end
    end,
    case OptOrMand of
	mandatory -> true;
	_ ->
	    emit([nl,indent(7),"end"])
    end.

gen_optormand_case(mandatory,_Erules,_TopType,_Cname,_Type,_InnerType,_WhatKind,
		   _Element) ->
    ok;
gen_optormand_case('OPTIONAL',Erules,_TopType,_Cname,_Type,_InnerType,_WhatKind,
		   Element) ->
    emit([" case ",Element," of",nl]),
    emit([indent(9),"asn1_NOVALUE -> {",
	  empty_lb(Erules),",0};",nl]),
    emit([indent(9),"_ ->",nl,indent(12)]);
gen_optormand_case({'DEFAULT',DefaultValue},Erules,TopType,Cname,Type,
		   InnerType,WhatKind,Element) ->
    CurrMod = get(currmod),
    case catch lists:member(der,get(encoding_options)) of
	true ->
	    emit(" case catch "),
	    asn1ct_gen:gen_check_call(TopType,Cname,Type,InnerType,
				      WhatKind,{asis,DefaultValue},
				      Element),
	    emit([" of",nl]),
	    emit([indent(12),"true -> {[],0};",nl]);
	_ ->
	    emit([" case ",Element," of",nl]),
	    emit([indent(9),"asn1_DEFAULT -> {",
		  empty_lb(Erules),
		  ",0};",nl]),
	    case DefaultValue of 
		#'Externalvaluereference'{module=CurrMod,
					  value=V} ->
		    emit([indent(9),"?",{asis,V}," -> {",
			  empty_lb(Erules),",0};",nl]);
		_ ->
		    emit([indent(9),{asis,
				     DefaultValue}," -> {",
			  empty_lb(Erules),",0};",nl])
	    end
    end,
    emit([indent(9),"_ ->",nl,indent(12)]).

    

gen_dec_line(Erules,TopType,Cname,CTags,Type,OptOrMand,DecObjInf)  ->
    BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(v)),
    Tag = 
	[(?ASN1CT_GEN_BER:decode_class(X#tag.class) bsl 10) + X#tag.number ||
	    X <- Type#type.tag],
    ChoiceTags = 
	[(?ASN1CT_GEN_BER:decode_class(Class) bsl 10) + Number|| 
	    {Class,Number} <- CTags], 
    InnerType = 
	case asn1ct_gen:get_constraint(Type#type.constraint,
				       tableconstraint_info) of
	    no ->
		asn1ct_gen:get_inner(Type#type.def);
	    _ ->
		Type#type.def
	end,
    PostpDec = 
	case OptOrMand of
	    mandatory ->
		PostponedDec = 
		    gen_dec_call(InnerType,Erules,TopType,Cname,Type,
				 BytesVar,Tag,
				 mandatory,", mandatory, ",DecObjInf);
	    _ -> %optional or default
		{FirstTag,RestTag} = 
		    case Tag of 
			[] -> 
			    {ChoiceTags,[]};
			[Ft|Rt] -> 
			    {Ft,Rt}
		    end,
		emit(["case ",{prev,tlv}," of",nl]),
		PostponedDec = 
		    case Tag of
			[] when length(ChoiceTags) > 0 -> % a choice without explicit tag
			    Fcases = 
				fun(FirstTag1) ->
					emit(["[",{curr,v}," = {",{asis,FirstTag1},
					      ",_}|Temp",
					      {curr,tlv},
					      "] ->",nl]),
					emit([indent(4),"{"]),
					Pdec= 
					    gen_dec_call(InnerType,Erules,TopType,Cname,Type,
							 BytesVar,RestTag,mandatory,
							 ", mandatory, ",DecObjInf),
					
					emit([", Temp",{curr,tlv},"}"]),
					emit([";",nl]),
					Pdec
				end,
			    hd([Fcases(TmpTag)|| TmpTag <- FirstTag]);

			[] -> % an open type without explicit tag
			    emit(["[",{curr,v},"|Temp",{curr,tlv},"] ->",nl]),
			    emit([indent(4),"{"]),
			    Pdec= 
				gen_dec_call(InnerType,Erules,TopType,Cname,Type,
					     BytesVar,RestTag,mandatory,
					     ", mandatory, ",DecObjInf),
			    
			    emit([", Temp",{curr,tlv},"}"]),
			    emit([";",nl]),
			    Pdec;

			_ ->
			    emit(["[{",{asis,FirstTag},
				  ",",{curr,v},"}|Temp",
				  {curr,tlv},
				  "] ->",nl]),
			    emit([indent(4),"{"]),
			    Pdec= 
				gen_dec_call(InnerType,Erules,TopType,Cname,Type,
					     BytesVar,RestTag,mandatory,
					     ", mandatory, ",DecObjInf),
			    
			    emit([", Temp",{curr,tlv},"}"]),
			    emit([";",nl]),
			    Pdec
		    end,
		
		emit([indent(4),"_ ->",nl]),
		case OptOrMand of
		    {'DEFAULT', Def} ->
			emit([indent(8),"{",{asis,Def},",",{prev,tlv},"}",nl]);
		    'OPTIONAL' ->
			emit([indent(8),"{ asn1_NOVALUE, ",{prev,tlv},"}",nl])
		end,
		emit(["end"]),
		PostponedDec
	end,
    case DecObjInf of
	{Cname,ObjSet} -> % this must be the component were an object is 
	    %% choosen from the object set according to the table 
	    %% constraint.
	    {[{ObjSet,Cname,asn1ct_gen:mk_var(asn1ct_name:curr(term))}],
	     PostpDec};
	_  -> {[],PostpDec}
    end.

gen_dec_call({typefield,_},_,_,_Cname,Type,BytesVar,Tag,_,_,false) ->
    %%  this in case of a choice with typefield components
    asn1ct_name:new(reason),
    asn1ct_name:new(opendec),
    asn1ct_name:new(tmpterm),
    asn1ct_name:new(tmptlv),

    {FirstPFName,RestPFName} = 
	asn1ct_gen:get_constraint(Type#type.constraint,
				  tableconstraint_info),
    emit([nl,indent(6),"begin",nl]),
%    emit([indent(9),{curr,opendec}," = ?RT_BER:decode_open_type(",
    emit([indent(9),{curr,tmptlv}," = ?RT_BER:decode_open_type(",
	  BytesVar,",",{asis,Tag},"),",nl]),
%     emit([indent(9),"{",{curr,tmptlv},",_} = ?RT_BER:decode(",
% 	  {curr,opendec},"),",nl]),

    emit([indent(9),"case (catch ObjFun(",{asis,FirstPFName},
	  ", ",{curr,tmptlv},", ",{asis,RestPFName},
	  ")) of", nl]),%% ??? What about Tag 
    emit([indent(12),"{'EXIT',",{curr,reason},"} ->",nl]),
    emit([indent(15),"exit({'Type not ",
	  "compatible with table constraint', ",{curr,reason},"});",nl]),
    emit([indent(12),{curr,tmpterm}," ->",nl]),
    emit([indent(15),{curr,tmpterm},nl]),
    emit([indent(9),"end",nl,indent(6),"end",nl]),
    [];
gen_dec_call({typefield,_},_,_,Cname,Type,BytesVar,Tag,_,_,_DecObjInf) ->
    emit(["?RT_BER:decode_open_type(",BytesVar,",",{asis,Tag},")"]),
    RefedFieldName = 
	asn1ct_gen:get_constraint(Type#type.constraint,
				  tableconstraint_info),
    [{Cname,RefedFieldName,asn1ct_gen:mk_var(asn1ct_name:curr(term)),
      asn1ct_gen:mk_var(asn1ct_name:curr(tmpterm)),Tag}];
gen_dec_call({objectfield,PrimFieldName,PFNList},_,_,Cname,_,BytesVar,Tag,_,_,_) ->
    emit(["?RT_BER:decode_open_type(",BytesVar,",",{asis,Tag},")"]),
    [{Cname,{PrimFieldName,PFNList},asn1ct_gen:mk_var(asn1ct_name:curr(term)),
      asn1ct_gen:mk_var(asn1ct_name:curr(tmpterm)),Tag}];
gen_dec_call(InnerType,Erules,TopType,Cname,Type,BytesVar,Tag,PrimOptOrMand,
	     OptOrMand,DecObjInf) ->
    WhatKind = asn1ct_gen:type(InnerType),
    gen_dec_call1(WhatKind,InnerType,Erules,TopType,Cname,Type,BytesVar,Tag,
		  PrimOptOrMand,OptOrMand),
    case DecObjInf of
	{Cname,{_,OSet,UniqueFName}} ->
	    emit([",",nl,"ObjFun = 'getdec_",OSet,"'(",
		  {asis,UniqueFName},", ",{curr,term},")"]);
	_ ->
	    ok
    end,
    [].
gen_dec_call1({primitive,bif},InnerType,Erules,_,_,Type,BytesVar,
	      Tag,OptOrMand,_) ->
    case InnerType of
	{fixedtypevaluefield,_,Btype} ->
	    ?ASN1CT_GEN_BER:gen_dec_prim(Erules,Btype,BytesVar,Tag,[],
					?PRIMITIVE,OptOrMand);
	_ ->
	    ?ASN1CT_GEN_BER:gen_dec_prim(Erules,Type,BytesVar,Tag,[],
					?PRIMITIVE,OptOrMand)
    end;
gen_dec_call1('ASN1_OPEN_TYPE',_InnerType,Erules,_,_,Type,BytesVar,
	      Tag,OptOrMand,_) ->
    ?ASN1CT_GEN_BER:gen_dec_prim(Erules,Type,BytesVar,Tag,[],
				?PRIMITIVE,OptOrMand);
gen_dec_call1(WhatKind,_,_Erules,TopType,Cname,Type,BytesVar,Tag,_,_OptOrMand) ->
    {DecFunName, _DecMod, _DecFun} = 
	mkfuncname(TopType,Cname,WhatKind,dec),
    case {WhatKind,Type#type.tablecinf} of
	{{constructed,bif},[{objfun,_}|_Rest]} ->
	    emit([DecFunName,"(",BytesVar,", ",{asis,Tag},", ObjFun)"]);
	_ ->
	    emit([DecFunName,"(",BytesVar,", ",{asis,Tag},")"])
    end.


%%------------------------------------------------------
%% General and special help functions (not exported)
%%------------------------------------------------------


indent(N) ->
    lists:duplicate(N,32). % 32 = space

mkcindexlist([H,T1|T], Sep) -> % Sep is a string e.g ", " or "+ "
    emit(["Cindex",H,Sep]),
    mkcindexlist([T1|T], Sep);
mkcindexlist([H|T], Sep) ->
    emit(["Cindex",H]),
    mkcindexlist(T, Sep);
mkcindexlist([], _) ->
    true.

mkcindexlist(L) ->
    mkcindexlist(L,", ").


mkvlist([H,T1|T], Sep) -> % Sep is a string e.g ", " or "+ "
    emit([{var,H},Sep]),
    mkvlist([T1|T], Sep);
mkvlist([H|T], Sep) ->
    emit([{var,H}]),
    mkvlist(T, Sep);
mkvlist([], _) ->
    true.

mkvlist(L) ->
    mkvlist(L,", ").

mkvplus(L) ->
    mkvlist(L," + ").

extensible(CompList) when list(CompList) ->
    noext;
extensible({RootList,ExtList}) ->
    {ext,length(RootList)+1,length(ExtList)}.


print_attribute_comment(InnerType,Pos,Cname,Prop) ->
    CommentLine = "%%-------------------------------------------------",
    emit([nl,CommentLine]),
    case InnerType of
	{typereference,_,Name} -> 
	    emit([nl,"%% attribute ",Cname,"(",Pos,") with type ",Name]);
	{'Externaltypereference',_,XModule,Name} -> 
	    emit([nl,"%% attribute ",Cname,"(",Pos,")   External ",XModule,":",Name]);
	_ ->
	    emit([nl,"%% attribute ",Cname,"(",Pos,") with type ",InnerType])
    end,
    case Prop of
	mandatory ->
	    continue;
	{'DEFAULT', Def} ->
	    emit([" DEFAULT = ",{asis,Def}]);
	'OPTIONAL' ->
	    emit([" OPTIONAL"])
    end,
    emit([nl,CommentLine,nl]).


mkfuncname(TopType,Cname,WhatKind,DecOrEnc) ->
    CurrMod = get(currmod),
    case WhatKind of
	#'Externaltypereference'{module=CurrMod,type=EType} ->
	    F = lists:concat(["'",DecOrEnc,"_",EType,"'"]),
	    {F, "?MODULE", F};
	#'Externaltypereference'{module=Mod,type=EType} ->
	    {lists:concat(["'",Mod,"':'",DecOrEnc,"_",EType,"'"]),Mod,
	     lists:concat(["'",DecOrEnc,"_",EType,"'"])};
	{constructed,bif} ->
	    F = lists:concat(["'",DecOrEnc,"_",asn1ct_gen:list2name([Cname|TopType]),"'"]),
	    {F, "?MODULE", F}
    end.

empty_lb(ber) ->
    "[]";
empty_lb(ber_bin) ->
    "<<>>";
empty_lb(ber_bin_v2) ->
    "<<>>".
