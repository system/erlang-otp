-module(mk_ssl_pkix_oid).

-export([make/0]).

-define(PKIX_MODULES, ['PKIX1Algorithms88', 'PKIX1Explicit88',
		       'PKIX1Implicit88']).

make() ->
    {ok, Fd} = file:open("ssl_pkix_oid.erl", [write]),
    io:fwrite(Fd, "%%% File: ssl_pkix_oid.erl\n"
	      "%%% NB This file has been automatically generated by "
	      "mk_ssl_pkix_oid.\n"
	      "%%% Do not edit it.\n\n", []),
    io:fwrite(Fd, "-module(ssl_pkix_oid).\n", []),
    io:fwrite(Fd, "-export([id2atom/1, atom2id/1, all_atoms/0, "
	      "all_ids/0]).\n\n", []),


    AIds0 = get_atom_ids(?PKIX_MODULES),

    AIds1 = modify_atoms(AIds0),
    gen_id2atom(Fd, AIds1),
    gen_atom2id(Fd, AIds1),
    gen_all(Fd, AIds1),
    file:close(Fd).

get_atom_ids(Ms) ->
    get_atom_ids(Ms, []).

get_atom_ids([], AIdss) ->
    lists:flatten(AIdss);
get_atom_ids([M| Ms], AIdss) ->
    {value, {exports, Exports}} = 
	lists:keysearch(exports, 1, M:module_info()),
    As = lists:zf(
	   fun ({info, 0}) -> false;
	       ({module_info, 0}) -> false;
	       ({encoding_rule, 0}) -> false;
	       ({F, 0}) -> 
		   case atom_to_list(F) of
		   %% Remove upper-bound (ub-) functions
		       "ub-" ++ _Rest ->
			   false;
		       _ ->
			   {true, F}
		   end;
	       (_) -> false 
	   end, Exports),
    AIds = lists:map(fun(F) -> {F, M:F()} end, As),
    get_atom_ids(Ms, [AIds| AIdss]).

modify_atoms(AIds) ->
    F = fun({A, I}) ->
		NAS = case atom_to_list(A) of
			  "id-" ++ Rest ->
			      Rest;
			  Any ->
			      Any
		      end,
		{list_to_atom(NAS), I} end,
    lists:map(F, AIds). 

gen_id2atom(Fd, AIds0) ->
    AIds1 = lists:keysort(2, AIds0),
    Txt = join(";\n", 
	       lists:map(
		 fun({Atom, Id}) ->
			 io_lib:fwrite("id2atom(~p) ->\n    ~p", [Id, Atom]) 
		 end, AIds1)),
    io:fwrite(Fd, "~s;\nid2atom(Any)->\n    Any.\n\n", [Txt]).

gen_atom2id(Fd, AIds0) ->
    AIds1 = lists:keysort(1, AIds0),
    Txt = join(";\n", 
	       lists:map(
		 fun({Atom, Id}) ->
			 io_lib:fwrite("atom2id(~p) ->\n    ~p", [Atom, Id]) 
		 end, AIds1)),
    io:fwrite(Fd, "~s;\natom2id(Any)->\n    Any.\n\n", [Txt]).

gen_all(Fd, AIds) ->
    Atoms = lists:sort([A || {A, _} <- AIds]),
    Ids = lists:sort([I || {_, I} <- AIds]),
    F = fun(X) -> io_lib:fwrite("    ~w", [X]) end,
    ATxt = "all_atoms() ->\n" ++ join(",\n", lists:map(F, Atoms)),
    io:fwrite(Fd, "~s.\n\n", [ATxt]),
    ITxt = "all_ids() ->\n" ++ 	join(",\n", lists:map(F, Ids)),
    io:fwrite(Fd, "~s.\n\n", [ITxt]).

join(Sep, [H1, H2| T]) ->
    [H1, Sep| join(Sep, [H2| T])]; 
join(_Sep, [H1]) ->
    H1;
join(_, []) ->
    [].
