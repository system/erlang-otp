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
%% Purpose : Constant folding optimisation for Core

%% Propagate atomic values and fold in values of safe calls to
%% constant arguments.  Also detect and remove literals which are
%% ignored in a 'seq'.  Could handle lets better by chasing down
%% complex 'arg' expressions and finding values.
%%
%% Try to optimise case expressions by removing unmatchable or
%% unreachable clauses.  Also change explicit tuple arg into multiple
%% values and extend clause patterns.  We must be careful here not to
%% generate cases which we know to be safe but later stages will not
%% recognise as such, e.g. the following is NOT acceptable:
%%
%%    case 'b' of
%%        <'b'> -> ...
%%    end
%%
%% Variable folding is complicated by variable shadowing, for example
%% in:
%%    fdef 'foo'/1 =
%%        fun (X) ->
%%            let <A> = X
%%            in  let <X> = Y
%%                in ... <use A>
%% If we were to simply substitute X for A then we would be using the
%% wrong X.  Our solution is to rename variables that are the values
%% of substitutions.  We could rename all shadowing variables but do
%% the minimum.  We would then get:
%%    fdef 'foo'/1 =
%%        fun (X) ->
%%            let <X1> = Y
%%            in ... <use X>
%%
%% This is done by carefully shadowing variables and substituting
%% values.  See details when defining functions.
%%
%% It would be possible to extend to replace repeated evaluation of
%% "simple" expressions by the value (variable) of the first call.
%% For example, after a "let Z = X+1" then X+1 would be replaced by Z
%% where X is valid.  The Sub uses the full Core expression as key.
%% It would complicate handling of patterns as we would have to remove
%% all values where the key contains pattern variables.

-module(sys_core_fold).

-export([module/2,function/1]).

-import(lists, [map/2,foldl/3,mapfoldl/3,all/2,any/2]).
-include("core_parse.hrl").

%% Variable value info.
-record(sub, {v=[]}).				%Variable substitutions

module(#c_mdef{body=B0}=Mod, Opts) ->
    B1 = map(fun function/1, B0),
    {ok,Mod#c_mdef{body=B1}}.

function(#c_fdef{body=B0}=Fdef) ->
    %%ok = io:fwrite("~w:~p~n", [?LINE,{Fdef#c_fdef.func,Fdef#c_fdef.arity}]),
    B1 = expr(B0, sub_new()),			%This must be a fun!
    Fdef#c_fdef{body=B1}.

%% body(Expr, Sub) -> Expr.
%%  No special handling of anything except valuess.

body(#c_values{anno=A,es=Es0}, Sub) ->
    Es1 = expr_list(Es0, Sub),
    #c_values{anno=A,es=Es1};
body(E, Sub) -> expr(E, Sub).

%% guard(Expr, Sub) -> Expr.
%%  Guards have restricted formats, the Erlang guard tests end up
%%  either as the arg of a #c_seq{} or the final body in a #c_let{} or
%%  #c_seq{}.  Must handle type tests as tests.

guard(#c_seq{arg=Arg0,body=B0}=Seq, Sub) ->
    case {guard_test(Arg0, Sub),guard(B0, Sub)} of
	{#c_atom{name=true},B} -> B;
	{#c_atom{name=false}=False,B} -> False;
	{Arg,#c_atom{name=true}} -> Arg;
	{Arg,#c_atom{name=false}=False} -> False;
	{Arg,B} -> Seq#c_seq{arg=Arg,body=B}
    end;
guard(#c_let{vars=Vs0,arg=Arg0,body=B0}=Let, Sub0) ->
    Arg1 = body(Arg0, Sub0),
    %% Optimise let and add new substitutions.
    {Vs1,Args,Sub1} = let_substs(Vs0, Arg1, Sub0),
    B1 = guard(B0, Sub1),
    %% Optimise away let if no values remain to be set.
    if Vs1 == [] -> B1;
       true ->
	    Let#c_let{vars=Vs1,arg=core_lib:make_values(Args),body=B1}
    end;
guard(E, Sub) ->
    guard_test(E, Sub).

guard_test(#c_call{op=#c_remote{mod=erlang,name=N,arity=1}=Op,
		   args=[A0]}=Call, Sub) ->
    %% Here we must special case things.
    A1 = expr(A0, Sub),
    case catch begin
		   LitA = core_lib:literal_value(A1),
		   {ok,core_lib:make_literal(eval_test(N, LitA))}
	       end of
	{ok,Val} -> Val;
	Other -> Call#c_call{args=[A1]}
    end;
guard_test(Test, Sub) ->
    expr(Test, Sub).

eval_test(integer, I) when integer(I) -> true;
eval_test(integer, I) -> false;
eval_test(float, I) when float(I) -> true;
eval_test(float, I) -> false;
eval_test(number, I) when number(I) -> true;
eval_test(number, I) -> false;
eval_test(atom, I) when atom(I) -> true;
eval_test(atom, I) -> false;
eval_test(constant, I) when constant(I) -> true;
eval_test(constant, I) -> false;
eval_test(list, I) when list(I) -> true;
eval_test(list, I) -> false;
eval_test(tuple, I) when tuple(I) -> true;
eval_test(tuple, I) -> false.

%% expr(Expr, Sub) -> Expr.

expr(#c_var{}=V, Sub) ->
    sub_get_var(V, Sub);
expr(#c_int{}=I, Sub) -> I;
expr(#c_float{}=F, Sub) -> F;
expr(#c_atom{}=A, Sub) -> A;
expr(#c_char{}=C, Sub) -> C;
expr(#c_string{}=S, Sub) -> S;
expr(#c_nil{}=N, Sub) -> N;
expr(#c_cons{anno=A,head=H,tail=T}, Sub) ->
    #c_cons{anno=A,head=expr(H, Sub),tail=expr(T, Sub)};
expr(#c_tuple{anno=A,es=Es}, Sub) ->
    #c_tuple{anno=A,es=expr_list(Es, Sub)};
expr(#c_bin{anno=A,es=Es}, Sub) ->
    #c_bin{anno=A,es=bin_elem_list(Es, Sub)};
expr(#c_fun{vars=Vs0,body=B0}=Fun, Sub0) ->
    {Vs1,Sub1} = pattern_list(Vs0, Sub0),
    B1 = body(B0, Sub1),
    Fun#c_fun{vars=Vs1,body=B1};
expr(#c_seq{arg=Arg0,body=B0}=Seq, Sub) ->
    B1 = body(B0, Sub),
    %% Optimise away pure literal arg as its value is ignored.
    case body(Arg0, Sub) of
	#c_values{es=Es}=Arg1 ->
	    case is_pure_literal_list(Es) of
		true -> B1;
		false -> Seq#c_seq{arg=Arg1,body=B1}
	    end;
	Arg1 ->
	    case is_pure_literal(Arg1) of
		true -> B1;
		false -> Seq#c_seq{arg=Arg1,body=B1}
	    end
    end;
expr(#c_let{vars=Vs0,arg=Arg0,body=B0}=Let, Sub0) ->
    Arg1 = body(Arg0, Sub0),			%This is a body
    %% Optimise let and add new substitutions.
    {Vs1,Args,Sub1} = let_substs(Vs0, Arg1, Sub0),
    B1 = body(B0, Sub1),
    %% Optimise away let if the body consists of a single variable or
    %% if no values remain to be set.
    case {Vs1,Args,B1} of
	{[#c_var{name=Vname}],Args,#c_var{name=Vname}} ->
	    core_lib:make_values(Args);
	{[],[],Body} ->
	    Body;
	Other ->
	    opt_case_in_let(Let#c_let{vars=Vs1,
				      arg=core_lib:make_values(Args),
				      body=B1})
    end;
expr(#c_case{arg=Arg0,clauses=Cs0}=Case, Sub) ->
    Arg1 = body(Arg0, Sub),
    {Arg2,Cs1} = case_opt(Arg1, Cs0),
    Cs2 = clauses(Arg2, Cs1, Sub),
    eval_case(Case#c_case{arg=Arg2,clauses=Cs2});
expr(#c_receive{clauses=Cs0,timeout=T0,action=A0}=Recv, Sub) ->
    Cs1 = clauses(#c_var{name='_'}, Cs0, Sub),	%This is all we know
    T1 = expr(T0, Sub),
    A1 = body(A0, Sub),
    Recv#c_receive{clauses=Cs1,timeout=T1,action=A1};
expr(#c_call{anno=A,op=Op0,args=As0}=Call, Sub) ->
    Op1 = call_op(Op0, Sub),
    As1 = expr_list(As0, Sub),
    call(A, Op1, As1);
expr(#c_catch{body=B0}=Catch, Sub) ->
    B1 = body(B0, Sub),
    Catch#c_catch{body=B1};
expr(#c_local{}=Loc, Sub) -> Loc.

expr_list(Es, Sub) ->
    map(fun (E) -> expr(E, Sub) end, Es).

bin_elem_list(Es, Sub) ->
    map(fun (E) -> bin_elem(E, Sub) end, Es).

bin_elem(#c_bin_elem{val=Val,size=Size}=BinElem, Sub) ->
    BinElem#c_bin_elem{val=expr(Val, Sub),size=expr(Size, Sub)}.


%% is_pure_literal(Expr) -> true | false.
%%  A pure literal cannot fail with badarg.

is_pure_literal(#c_cons{head=H,tail=T}) ->
    case is_pure_literal(H) of
	true -> is_pure_literal(T); 
	false -> false
    end;
is_pure_literal(#c_tuple{es=Es}) -> is_pure_literal_list(Es);
is_pure_literal(#c_bin{es=E}) -> false;
is_pure_literal(E) -> core_lib:is_atomic(E).

is_pure_literal_list(Es) -> lists:all(fun is_pure_literal/1, Es).

%% call_op(Op) -> Op.
%%  Fold call op.  Remotes and internals can only exist here.

call_op(#c_remote{}=Rem, Sub) -> Rem;
call_op(#c_internal{}=Int, Sub) -> Int;
call_op(Expr, Sub) -> expr(Expr, Sub).

%% call(Anno, Op, Args) -> Expr.
%%  Try to safely evaluate the call.  Just try to evaluate arguments,
%%  do the call and convert return values to literals.  If this
%%  succeeds then use the new value, otherwise just fail and use
%%  original call.  Do this at every level.
%%
%%  We evaluate length/1 if the shape of the list is known.
%%
%%  We evaluate element/2 and setelement/3 if the position is constant and
%%  the shape of the tuple is known.
%%
%%  We evalute '++' if the first operand is as literal (or partly literal).

call(A, #c_remote{mod=erlang,name=length,arity=1}=Op, [Arg]=Args) ->
    eval_length(A, Op, Arg);
call(A, #c_remote{mod=erlang,name='++',arity=2}=Op, [Arg1,Arg2]=Args) ->
    eval_append(A, Op, Arg1, Arg2);
call(A, #c_remote{mod=erlang,name=element,arity=2}=Op, [Arg1,Arg2]=Args) ->
    Ref = make_ref(),
    case catch {Ref,eval_element(Arg1, Arg2)} of
	{Ref,Val} -> Val;
	Other -> #c_call{anno=A,op=Op,args=Args}
    end;
call(A, #c_remote{mod=erlang,name=setelement,arity=3}=Op, [Arg1,Arg2,Arg3]=Args) ->
    Ref = make_ref(),
    case catch {Ref,eval_setelement(Arg1, Arg2, Arg3)} of
	{Ref,Val} -> Val;
	Other -> #c_call{anno=A,op=Op,args=Args}
    end;
call(A, #c_remote{mod=erlang,name=N,arity=Arity}=Op, [Arg]=Args) ->
    case catch begin
		   LitA = core_lib:literal_value(Arg),
		   {ok,core_lib:make_literal(eval_call(N, LitA))}
	       end of
	{ok,Val} -> Val;
	Other -> #c_call{anno=A,op=Op,args=Args}
    end;
call(A, #c_remote{mod=erlang,name=N,arity=Arity}=Op, [Arg1,Arg2]=Args) ->
    case catch begin
		   LitA1 = core_lib:literal_value(Arg1),
		   LitA2 = core_lib:literal_value(Arg2),
		   {ok,core_lib:make_literal(eval_call(N, LitA1, LitA2))}
	       end of
	{ok,Val} -> Val;
	Other -> #c_call{anno=A,op=Op,args=Args}
    end;
call(A, Op, Args) -> #c_call{anno=A,op=Op,args=Args}.

%% eval_call(Op, Arg) -> Value.
%% eval_call(Op, Arg1, Arg2) -> Value.
%%  Evaluate safe calls.  We only do arithmetic and logical operators,
%%  there are more but these are the ones that are probably
%%  worthwhile.  It would be MUCH easier if we could apply these!

eval_call('+', X) -> 0 + X;
eval_call('-', X) -> 0 - X;
eval_call('bnot', X) -> bnot X;
eval_call(abs, A) -> abs(A);
eval_call(float, A) -> float(A);
eval_call(round, A) -> round(A);
eval_call(trunc, A) -> trunc(A);
eval_call('not', X) -> not X;
eval_call(hd, L) -> hd(L);
eval_call(tl, L) -> tl(L);
eval_call(length, L) -> length(L);
eval_call(size, T) -> size(T);
eval_call(integer_to_list, I) -> integer_to_list(I);
eval_call(list_to_integer, L) -> list_to_integer(L);
eval_call(float_to_list, F) -> float_to_list(F);
eval_call(list_to_float, L) -> list_to_float(L);
eval_call(atom_to_list, A) -> atom_to_list(A);
eval_call(list_to_atom, L) -> list_to_atom(L);
eval_call(tuple_to_list, T) -> tuple_to_list(T);
eval_call(list_to_tuple, L) -> list_to_tuple(L).

eval_call('*', X, Y) -> X * Y;
eval_call('/', X, Y) -> X / Y;
eval_call('+', X, Y) -> X + Y;
eval_call('-', X, Y) -> X - Y;
eval_call('div', X, Y) -> X div Y;
eval_call('rem', X, Y) -> X rem Y;
eval_call('band', X, Y) -> X band Y;
eval_call('bor', X, Y) -> X bor Y;
eval_call('bxor', X, Y) -> X bxor Y;
eval_call('bsl', X, Y) -> X bsl Y;
eval_call('bsr', X, Y) -> X bsr Y;
eval_call('and', X, Y) -> X and Y;
eval_call('or',  X, Y) -> X or Y;
eval_call('xor', X, Y) -> X xor Y;
eval_call('=:=',  X, Y) -> X =:= Y;
eval_call('=/=',  X, Y) -> X =/= Y;
eval_call('==',  X, Y) -> X == Y;
eval_call('/=',  X, Y) -> X /= Y;
eval_call('=<',  X, Y) -> X =< Y;
eval_call('<',   X, Y) -> X < Y;
eval_call('>=',  X, Y) -> X >= Y;
eval_call('>',   X, Y) -> X > Y;
eval_call('++', X, Y) -> X ++ Y;
eval_call('--', X, Y) -> X -- Y;
eval_call(element, X, Y) -> element(X, Y).

%% eval_length(Anno, Op, List) -> Val.
%%  Evaluates the length for the prefix of List which has a known
%%  shape.

eval_length(A, Op, Core) -> eval_length(A, Op, Core, 0).
    
eval_length(A, Op, #c_nil{}, Len) -> #c_int{anno=A,val=Len};
eval_length(A, Op, #c_cons{tail=T}=Cons, Len) ->
    eval_length(A, Op, T, Len+1);
eval_length(A, Op, List, 0) ->
    #c_call{anno=A,op=Op,args=[List]};
eval_length(A, Op, List, Len) ->
    #c_call{anno=A,op=#c_remote{anno=A,mod=erlang,name='+',arity=2},
	    args=[#c_int{val=Len},#c_call{anno=A,op=Op,args=[List]}]}.

%% eval_append(Anno, Op, FirstList, SecondList) -> Val.
%%  Evaluates the constant part of '++' expression.

eval_append(A, Op, #c_nil{}, List) -> List;
eval_append(A, Op, #c_cons{tail=T}=Cons, List) ->
    Cons#c_cons{tail=eval_append(A, Op, T, List)};
eval_append(A, Op, X, Y) ->
    #c_call{anno=A,op=Op,args=[X,Y]}.

%% eval_element(Pos, Tuple) -> Val.
%%  Evaluates element/2 if Pos and Tuple are literals.

eval_element(#c_int{val=Pos}, #c_tuple{es=Es}) ->
    lists:nth(Pos, Es).

%% eval_setelement(Pos, Tuple, NewVal) -> Val.
%%  Evaluates setelement/3 if Pos and Tuple are literals.

eval_setelement(#c_int{val=Pos}, #c_tuple{es=Es}=Tuple, NewVal) ->
    Tuple#c_tuple{es=eval_setelement1(Pos, Es, NewVal)}.

eval_setelement1(1, [_|T], NewVal) ->
    [NewVal|T];
eval_setelement1(Pos, [H|T], NewVal) when Pos > 1 ->
    [H|eval_setelement1(Pos-1, T, NewVal)].

%% clause(Clause, Sub) -> Clause.

clause(#c_clause{pats=Ps0,guard=G0,body=B0}=Cl, Sub0) ->
    {Ps1,Sub1} = pattern_list(Ps0, Sub0),
    G1 = guard(G0, Sub1),
    B1 = body(B0, Sub1),
    Cl#c_clause{pats=Ps1,guard=G1,body=B1}.

%% let_substs(LetVars, LetArg, Sub) -> {[Var],[Val],Sub}.
%%  Add suitable substitutions to Sub of variables in LetVars.  First
%%  remove variables in LetVars from Sub, then fix subs.  N.B. must
%%  work out new subs in parallel and then apply then to subs.  Return
%%  the unsubstituted variables and values.

let_substs(Vs0, As0, Sub0) ->
    {Vs1,Sub1} = pattern_list(Vs0, Sub0),
    {Vs2,As1,Ss} = let_substs_1(Vs1, As0, Sub1),
    {Vs2,As1,
     foldl(fun ({V,S}, Sub) -> sub_set_name(V, S, Sub) end, Sub1, Ss)}.

let_substs_1(Vs, #c_values{es=As}, Sub) ->
    let_subst_list(Vs, As, Sub);
let_substs_1([V], A, Sub) -> let_subst_list([V], [A], Sub);
let_substs_1(Vs, A, Sub) -> {Vs,A,[]}.

let_subst_list([V|Vs0], [A|As0], Sub) ->
    {Vs1,As1,Ss} = let_subst_list(Vs0, As0, Sub),
    case is_subst(A) of
	true -> {Vs1,As1,sub_subst_var(V, A, Sub) ++ Ss};
	false -> {[V|Vs1],[A|As1],Ss}
    end;
let_subst_list([], [], Sub) -> {[],[],[]}.

%% pattern(Pattern, InSub) -> {Pattern,OutSub}.
%% pattern(Pattern, InSub, OutSub) -> {Pattern,OutSub}.
%%  Variables occurring in Pattern will shadow so they must be removed
%%  from Sub.  If they occur as a value in Sub then we create a new
%%  variable and then add a substitution for that.
%%
%%  Patterns are complicated by sizes in binaries.  These are pure
%%  input variables which create no bindings.  We, therefore, need to
%%  carry around the original substitutions to get the correct
%%  handling.

%%pattern(Pat, Sub) -> pattern(Pat, Sub, Sub). 

pattern(#c_var{name=V0}=Pat, Isub, Osub) ->
    case sub_is_val(Pat, Isub) of
	true ->
	    %% Nesting saves us from using unique variable names.
	    V1 = list_to_atom("fol" ++ atom_to_list(V0)),
	    Pat1 = #c_var{name=V1},
	    {Pat1,sub_set_var(Pat, Pat1, Osub)};
	false -> {Pat,sub_del_var(Pat, Osub)}
    end;
pattern(#c_int{}=Pat, Osub, Isub) -> {Pat,Osub};
pattern(#c_float{}=Pat, Isub, Osub) -> {Pat,Osub};
pattern(#c_atom{}=Pat, Isub, Osub) -> {Pat,Osub};
pattern(#c_char{}=Pat, Isub, Osub) -> {Pat,Osub};
pattern(#c_string{}=Pat, Isub, Osub) -> {Pat,Osub};
pattern(#c_nil{}=Pat, Isub, Osub) -> {Pat,Osub};
pattern(#c_cons{head=H0,tail=T0}=Pat, Isub, Osub0) ->
    {H1,Osub1} = pattern(H0, Isub, Osub0),
    {T1,Osub2} = pattern(T0, Isub, Osub1),
    {Pat#c_cons{head=H1,tail=T1},Osub2};
pattern(#c_tuple{es=Es0}=Pat, Isub, Osub0) ->
    {Es1,Osub1} = pattern_list(Es0, Isub, Osub0),
    {Pat#c_tuple{es=Es1},Osub1};
pattern(#c_bin{es=V0}=Pat, Isub, Osub0) ->
    {V1,Osub1} = bin_pattern_list(V0, Isub, Osub0),
    {Pat#c_bin{es=V1},Osub1};
pattern(#c_alias{var=V0,pat=P0}=Pat, Isub, Osub0) ->
    {V1,Osub1} = pattern(V0, Isub, Osub0),
    {P1,Osub2} = pattern(P0, Isub, Osub1),
    {Pat#c_alias{var=V1,pat=P1},Osub2}.

bin_pattern_list(Ps0, Isub, Osub0) ->
    mapfoldl(fun (P, Osub) -> bin_pattern(P, Isub, Osub) end, Osub0, Ps0).

bin_pattern(#c_bin_elem{val=E0,size=Size0}=Pat, Isub, Osub0) ->
    Size1 = expr(Size0, Isub),
    {E1,Osub1} = pattern(E0, Isub, Osub0),
    {Pat#c_bin_elem{val=E1,size=Size1},Osub1}.

pattern_list(Ps, Sub) -> pattern_list(Ps, Sub, Sub).

pattern_list(Ps0, Isub, Osub0) ->
    mapfoldl(fun (P, Osub) -> pattern(P, Isub, Osub) end, Osub0, Ps0).

%% is_subst(Expr) -> true | false.
%%  Test whether an expression is a suitable substitution.

is_subst(#c_tuple{es=[]}) -> true;		%The empty tuple
is_subst(E) -> core_lib:is_atomic(E).

%% sub_new() -> #sub{}.
%% sub_get_var(Var, #sub{}) -> Value.
%% sub_set_var(Var, Value, #sub{}) -> #sub{}.
%% sub_set_name(Name, Value, #sub{}) -> #sub{}.
%% sub_del_var(Var, #sub{}) -> #sub{}.
%% sub_subst_var(Var, Value, #sub{}) -> [{Name,Value}].
%% sub_is_val(Var, #sub{}) -> bool().
%%  We use the variable name as key so as not have problems with
%%  annotations.  When adding a new substitute we fold substitute
%%  chains so we never have to search more than once.

sub_new() -> #sub{v=[]}.

sub_get_var(#c_var{name=V}=Var, #sub{v=S}) ->
    case v_find(V, S) of
	{ok,Val} -> Val;
	error -> Var
    end.

sub_set_var(#c_var{name=V}, Val, Sub) ->
    sub_set_name(V, Val, Sub).

sub_set_name(V, Val, #sub{v=S}=Sub) ->
    Sub#sub{v=v_store(V, Val, S)}.

sub_del_var(#c_var{name=V}, #sub{v=S}=Sub) ->
    Sub#sub{v=v_erase(V, S)}.

sub_subst_var(#c_var{name=V}, Val, #sub{v=S0}=Sub) ->
    %% Fold chained substitutions.
    [{V,Val}] ++ [ {K,Val} || {K,#c_var{name=V1}} <- S0, V1 == V ].

sub_is_val(#c_var{name=V}, #sub{v=S}) ->
    v_is_value(V, S).

v_find(Key, [{K,Value}|_]) when Key < K -> error;
v_find(Key, [{K,Value}|_]) when Key == K -> {ok,Value};
v_find(Key, [{K,Value}|D]) when Key > K -> v_find(Key, D);
v_find(Key, []) -> error.

v_store(Key, New, [{K,Old}=Pair|Dict]) when Key < K ->
    [{Key,New},Pair|Dict];
v_store(Key, New, [{K,Old}|Dict]) when Key == K ->
    [{Key,New}|Dict];
v_store(Key, New, [{K,Old}=Pair|Dict]) when Key > K ->
    [Pair|v_store(Key, New, Dict)];
v_store(Key, New, []) -> [{Key,New}].

v_erase(Key, [{K,Value}|Dict]) when Key < K -> [{K,Value}|Dict];
v_erase(Key, [{K,Value}|Dict]) when Key == K -> Dict;
v_erase(Key, [{K,Value}|Dict]) when Key > K ->
    [{K,Value}|v_erase(Key, Dict)];
v_erase(Key, []) -> [].

v_is_value(Var, Sub) ->
    any(fun ({V,#c_var{name=Val}}) when Val == Var -> true;
	    (Other) -> false
	end, Sub).

%% clauses(E, [Clause], Sub) -> [Clause].
%%  Trim the clauses by removing all clauses AFTER the first one which
%%  is guaranteed to match.  Also remove all trivially false clauses.

clauses(E, [C0|Cs], Sub) ->
    #c_clause{pats=Ps,guard=G}=C1 = clause(C0, Sub),
    %%ok = io:fwrite("~w: ~p~n", [?LINE,{E,Ps}]),
    case {will_match(E, Ps),will_succeed(G)} of
	{yes,yes} -> [C1];			%Skip the rest
	{no,Suc} -> clauses(E, Cs, Sub);	%Skip this clause
	{Mat,no} -> clauses(E, Cs, Sub);	%Skip this clause
	{Mat,Suc} -> [C1|clauses(E, Cs, Sub)]
    end;
clauses(E, [], Sub) -> [].

%% will_succeed(Guard) -> yes | maybe | no.
%%  Test if we know whether a guard will succeed/fail or just don't
%%  know.  Be VERY conservative!

will_succeed(#c_atom{name=true}) -> yes;
will_succeed(#c_atom{name=false}) -> no;
will_succeed(Guard) -> maybe.

%% will_match(Expr, [Pattern]) -> yes | maybe | no.
%%  Test if we know whether a match will succeed/fail or just don't
%%  know.  Be VERY conservative!

will_match(#c_values{es=Es}, Ps) ->
    will_match_list(Es, Ps, yes);
will_match(E, [P]) ->
    will_match_1(E, P);
will_match(E, Ps) -> no.

will_match_1(E, #c_var{}) -> yes;		%Will always match
will_match_1(E, #c_alias{pat=P}) ->		%Pattern decides
    will_match_1(E, P);
will_match_1(#c_var{}, P) -> maybe;
will_match_1(#c_tuple{es=Es}, #c_tuple{es=Ps}) ->
    will_match_list(Es, Ps, yes);
will_match_1(E, P) -> maybe.

will_match_list([E|Es], [P|Ps], M) ->
    case will_match_1(E, P) of
	yes -> will_match_list(Es, Ps, M);
	maybe -> will_match_list(Es, Ps, maybe);
	no -> no
    end;
will_match_list([], [], M) -> M;
will_match_list(Es, Ps, M) -> no.		%Different length

%% eval_case(Case) -> #c_case{} | #c_let{}.
%%  If possible, evaluate a case at compile time.  We know that the
%%  last clause is guaranteed to match so if there is only one clause
%%  with a pattern containing only variables then rewrite to a let.

eval_case(#c_case{arg=E,clauses=[#c_clause{pats=Ps,body=B}]}=Case) ->
    case is_var_pat(Ps) of
	true -> expr(#c_let{vars=Ps,arg=E,body=B}, sub_new());
	false -> Case
    end;
eval_case(Case) -> Case.

is_var_pat(Ps) -> all(fun (#c_var{}) -> true;
			  (Pat) -> false
		      end, Ps).

%% case_opt(CaseArg, [Clause]) -> {CaseArg,[Clause]}.
%%  Try and optimise case by removing building argument terms.

case_opt(#c_tuple{anno=A,es=Es}, Cs0) ->
    Cs1 = case_opt_cs(Cs0, length(Es)),
    {core_lib:set_anno(core_lib:make_values(Es), A),Cs1};
case_opt(Arg, Cs) -> {Arg,Cs}.

case_opt_cs([#c_clause{pats=Ps0,guard=G,body=B}=C|Cs], Arity) ->
    case case_tuple_pat(Ps0, Arity) of
	{ok,Ps1,Avs} ->
	    Flet = fun ({V,Sub}, Body) -> letify(V, Sub, Body) end,
	    [C#c_clause{pats=Ps1,
			guard=foldl(Flet, G, Avs),
			body=foldl(Flet, B, Avs)}|case_opt_cs(Cs, Arity)];
	error ->				%Can't match
	    case_opt_cs(Cs, Arity)
    end;
case_opt_cs([], Arity) -> [].

%% case_tuple_pat([Pattern], Arity) -> {ok,[Pattern],[{AliasVar,Pat}]} | error.

case_tuple_pat([#c_tuple{anno=A,es=Ps}], Arity) when length(Ps) == Arity ->
    {ok,Ps,[]};
    %%{ok,unalias_pat_list(Ps),[]};
case_tuple_pat([#c_var{anno=A}=V], Arity) ->
    Vars = make_vars(A, 1, Arity),
    {ok,Vars,[{V,#c_tuple{es=Vars}}]};
case_tuple_pat([#c_alias{anno=A,var=V,pat=P}], Arity) ->
    case case_tuple_pat([P], Arity) of
	{ok,Ps,Avs} -> {ok,Ps,[{V,#c_tuple{es=unalias_pat_list(Ps)}}|Avs]};
	error -> error
    end;
case_tuple_pat(Pat, Arity) -> error.

%% unalias_pat(Pattern) -> Pattern.
%%  Remove all the aliases in a pattern but using the alias variables
%%  instead of the values.  We KNOW they will be bound.

unalias_pat(#c_alias{var=V,pat=P}) -> V;
unalias_pat(#c_cons{head=H0,tail=T0}=Cons) ->
    H1 = unalias_pat(H0),
    T1 = unalias_pat(T0),
    Cons#c_cons{head=H1,tail=T1};
unalias_pat(#c_tuple{es=Ps}=Tuple) ->
    Tuple#c_tuple{es=unalias_pat_list(Ps)};
unalias_pat(Atomic) -> Atomic.

unalias_pat_list(Ps) -> map(fun unalias_pat/1, Ps).

make_vars(A, I, Max) when I =< Max ->
    [make_var(A, I)|make_vars(A, I+1, Max)];
make_vars(_, _, _) -> [].
    
make_var(A, N) ->
    #c_var{anno=A,name=list_to_atom("fol" ++ integer_to_list(N))}.

letify(#c_var{name=Vname}=Var, Val, Body) ->
    case core_lib:is_var_used(Vname, Body) of
	true ->
	    A = element(2, Body),
	    #c_let{anno=A,vars=[Var],arg=Val,body=Body};
	false -> Body
    end.

%% opt_case_in_let(LetExpr) -> LetExpr'
%%  In {V1,V2,...} = case E of P -> ... {Val1,Val2,...}; ... end.
%%  avoid building tuples, by converting tuples to multiple values.
%%  (The optimisation is not done if the built tuple is used or returned.)

opt_case_in_let(#c_let{vars=Vs,arg=Arg,body=B}=Let) ->
    case catch opt_case_in_let(Vs, Arg, B) of
	{'EXIT',Reason} -> Let;			%Optimisation not possible.
	Other -> Other
    end;
opt_case_in_let(Other) -> Other.

opt_case_in_let([#c_var{name=V}=Var], Arg0,
		#c_case{arg=#c_var{name=V},clauses=[C1|_]}) ->
    #c_clause{pats=[#c_tuple{es=Es}=Tuple],guard=#c_atom{name=true},body=B} = C1,
    true = all(fun (#c_var{}) ->true;
		   (Other) -> false end, Es),	%Only variables allowed in the tuple.
    false = core_lib:is_var_used(V, B),		%The built tuple must not be used.
    Arg = tuple_to_values(Arg0, length(Es)),	%Might fail.
    #c_let{vars=Es,arg=Arg,body=B}.

%% tuple_to_values(Expr, TupleArity) -> Expr' | exception
%%  Convert tuples in return position of arity TupleArity to values.

tuple_to_values(#c_call{op=#c_internal{name=match_fail,arity=1}}=Call, Arity) ->
    Call;
tuple_to_values(#c_call{op=#c_remote{mod=erlang,name=exit,arity=1}}=Call, Arity) ->
    Call;
tuple_to_values(#c_call{op=#c_remote{mod=erlang,name=fault,arity=1}}=Call, Arity) ->
    Call;
tuple_to_values(#c_call{op=#c_remote{mod=erlang,name=fault,arity=2}}=Call, Arity) ->
    Call;
tuple_to_values(#c_tuple{es=Es}, Arity) when length(Es) =:= Arity ->
    core_lib:make_values(Es);
tuple_to_values(#c_case{clauses=Cs0}=Case, Arity) ->
    Cs = map(fun(E) -> tuple_to_values(E, Arity) end, Cs0),
    Case#c_case{clauses=Cs};
tuple_to_values(#c_seq{body=B0}=Seq, Arity) ->
    Seq#c_seq{body=tuple_to_values(B0, Arity)};
tuple_to_values(#c_let{body=B0}=Let, Arity) ->
    Let#c_let{body=tuple_to_values(B0, Arity)};
tuple_to_values(#c_receive{clauses=Cs0,action=A0}=Rec, Arity) ->
    Cs = map(fun(E) -> tuple_to_values(E, Arity) end, Cs0),
    A = tuple_to_values(A0, Arity),
    Rec#c_receive{clauses=Cs,action=A};
tuple_to_values(#c_clause{body=B0}=Clause, Arity) ->
    B = tuple_to_values(B0, Arity),
    Clause#c_clause{body=B}.