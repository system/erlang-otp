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
-module(company).

-compile(export_all).
-compile({parse_transform,mnemosyne_lc}).

%0

-include("company.hrl").

init() ->
    mnesia:create_table(employee,
                        [{attributes, record_info(fields, employee)}]),
    mnesia:create_table(dept,
                        [{attributes, record_info(fields, dept)}]),
    mnesia:create_table(project,
                        [{attributes, record_info(fields, project)}]),
    mnesia:create_table(manager, [{type, bag}, 
                                  {attributes, record_info(fields, manager)}]),
    mnesia:create_table(at_dep,
                         [{attributes, record_info(fields, at_dep)}]),
    mnesia:create_table(in_proj, [{type, bag}, 
                                  {attributes, record_info(fields, in_proj)}]).

%0
    
%1

insert_emp(Emp, DeptId, ProjNames) ->
    Ename = Emp#employee.name,
    Fun = fun() ->
                  mnesia:write(Emp),
                  AtDep = #at_dep{emp = Ename, dept_id = DeptId},
                  mnesia:write(AtDep),
                  mk_projs(Ename, ProjNames)
          end,
    mnesia:transaction(Fun).


mk_projs(Ename, [ProjName|Tail]) ->
    mnesia:write(#in_proj{emp = Ename, proj_name = ProjName}),
    mk_projs(Ename, Tail);
mk_projs(_, []) -> ok.
    

%1

%15
-argtype({females, employee}).
females(E) :-
    E <- table(employee),
    E.sex = female.
%15

%2
females() ->
    F = fun() ->
                Q = query [E.name || E <- table(employee),
                                     E.sex = female] end,
                mnemosyne:eval(Q)
        end,
    mnesia:transaction(F).
%2

%16
females2() ->
    F = fun() ->
                Q = query [E.name || E <- rule(females) ] end,
                mnemosyne:eval(Q)
        end,
    mnesia:transaction(F).
%16

g() -> l.

%3
female_bosses() ->
    Q = query [{E.name, Boss.name} ||
                  E <- table(employee),
                  E.sex = female,
                  Boss <- table(employee),
                  Atdep <- table(at_dep),
                  Mgr <- table(manager),
                  Atdep.emp = E.emp_no,
                  Mgr.emp = Boss.emp_no,
                  Atdep.dept_id = Mgr.dept]
         end,
     mnesia:transaction(fun() -> mnemosyne:eval(Q) end).
%3


                    
%4
raise_females(Amount) ->
    F = fun() ->
                Q = query [E || E <- table(employee),
                                E.sex = female] end,
                Fs = mnemosyne:eval(Q),
                over_write(Fs, Amount)
        end,
    mnesia:transaction(F).

over_write([E|Tail], Amount) ->
    Salary = E#employee.salary + Amount,
    New = E#employee{salary = Salary},
    mnesia:write(New),
    1 + over_write(Tail, Amount);
over_write([], _) ->
    0.
%4

%5
raise(Eno, Raise) ->
    F = fun() ->
                [E] = mnesia:read({employee, Eno}),
                Salary = E#employee.salary + Raise,
                New = E#employee{salary = Salary},
                mnesia:write(New)
        end,
    mnesia:transaction(F).
%5


%6
bad_raise(Eno, Raise) ->
    F = fun() ->
                [E] = mnesia:read({employee, Eno}),
                Salary = E#employee.salary + Raise,
                New = E#employee{salary = Salary},
                io:format("Trying to write ... ~n", []),
                mnesia:write(New)
        end,
    mnesia:transaction(F).
%6


%7
f1() ->
    Q = query 
         [E || E <- table(employee), 
          E.sex = female]
    end, 
    F = fun() -> mnemosyne:eval(Q) end,
    mnesia:transaction(F).
%7

%8
f2() ->
    WildPat = mnesia:table_info(employee, wild_pattern),
    Pat = WildPat#employee{sex = female},
    F = fun() -> mnesia:match_object(Pat) end,
    mnesia:transaction(F).
%8

                       
%9
get_emps(Salary, Dep) ->
    Q = query 
          [E || E <- table(employee),
                At <- table(at_dep),
                E.salary > Salary,
                E.emp_no = At.emp,
                At.dept_id = Dep]
        end,
    F = fun() -> mnemosyne:eval(Q) end,
    mnesia:transaction(F).
%9
%10
get_emps2(Salary, Dep) ->
    Epat = mnesia:table_info(employee, wild_pattern),
    Apat = mnesia:table_info(at_dep, wild_pattern),
    F = fun() ->
                All = mnesia:match_object(Epat),
                High = filter(All, Salary),
                Alldeps = mnesia:match_object(Apat),
                filter_deps(High, Alldeps, Dep)
        end,
    mnesia:transaction(F).
                

filter([E|Tail], Salary) ->
    if 
        E#employee.salary > Salary ->
            [E | filter(Tail, Salary)];
        true ->
            filter(Tail, Salary)
    end;
filter([], _) ->
    [].

filter_deps([E|Tail], Deps, Dep) ->
    case search_deps(E#employee.name, Deps, Dep) of
        true ->
            [E | filter_deps(Tail, Deps, Dep)];
        false ->
            filter_deps(Tail, Deps, Dep)
    end;
filter_deps([], _,_) -> 
    [].


search_deps(Name, [D|Tail], Dep) ->
    if
        D#at_dep.emp == Name,
        D#at_dep.dept_id == Dep -> true;
        true -> search_deps(Name, Tail, Dep)
    end;
search_deps(Name, Tail, Dep) ->
    false.

%10


                
%11
bench1() ->
    Me = #employee{emp_no= 104732,
               name = klacke,
               salary = 7,
               sex = male,
               phone = 99586,
               room_no = {221, 015}},
    
    F = fun() -> insert_emp(Me, 'B/DUR', [erlang, mnesia, otp]) end,
    T1 = timer:tc(company, dotimes, [1000, F]),
    mnesia:add_table_copy(employee, b@skeppet, ram_copies),
    mnesia:add_table_copy(at_dep, b@skeppet, ram_copies),
    mnesia:add_table_copy(in_proj, b@skeppet, ram_copies),
    T2 = timer:tc(company, dotimes, [1000, F]),
    {T1, T2}.

dotimes(0, _) ->
    ok;
dotimes(I, F) ->
    F(), dotimes(I-1, F).

%11
    
    

    
            
%12

dist_init() ->
    mnesia:create_table(employee,
                         [{ram_copies, [a@gin, b@skeppet]},
                          {attributes, record_info(fields,
						   employee)}]),
    mnesia:create_table(dept,
                         [{ram_copies, [a@gin, b@skeppet]},
                          {attributes, record_info(fields, dept)}]),
    mnesia:create_table(project,
                         [{ram_copies, [a@gin, b@skeppet]},
                          {attributes, record_info(fields, project)}]),
    mnesia:create_table(manager, [{type, bag}, 
                                  {ram_copies, [a@gin, b@skeppet]},
                                  {attributes, record_info(fields,
							   manager)}]),
    mnesia:create_table(at_dep,
                         [{ram_copies, [a@gin, b@skeppet]},
                          {attributes, record_info(fields, at_dep)}]),
    mnesia:create_table(in_proj,
                        [{type, bag}, 
                         {ram_copies, [a@gin, b@skeppet]},
                         {attributes, record_info(fields, in_proj)}]).
%12

%13
remove_proj(ProjName) ->
    F = fun() ->
                Ip = mnemosyne:eval(query [X || X <- table(in_proj),
                                                X.proj_name = ProjName]
                                    end),
                mnesia:delete({project, ProjName}),
                del_in_projs(Ip)
        end,
    mnesia:transaction(F).

del_in_projs([Ip|Tail]) ->
    mnesia:delete_object(Ip),
    del_in_projs(Tail);
del_in_projs([]) ->
    done.
%13
                           
%14
sync() ->
    case mnesia:wait_for_tables(tabs(), 10000) of
        {timeout, RemainingTabs} ->
            panic(RemainingTabs);
        ok ->
            synced
    end.

tabs() -> [employee, dept, project, at_dep, in_proj, manager].

%14


panic(X) -> exit({panic, X}).

