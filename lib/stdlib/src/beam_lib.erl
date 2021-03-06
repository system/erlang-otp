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
%%     $Id $
%%
-module(beam_lib).
-behaviour(gen_server).

-export([info/1,
	 cmp/2,
	 cmp_dirs/2,
	 chunks/2,
	 chunks/3,
	 all_chunks/1,
	 diff_dirs/2,
	 strip/1,
	 strip_files/1,
	 strip_release/1,
	 build_module/1,
	 version/1,
	 md5/1,
	 format_error/1]).

%% The following functions implement encrypted debug info.

-export([crypto_key_fun/1, clear_crypto_key_fun/0]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,
	 terminate/2,code_change/3]).
-export([make_crypto_key/2, get_crypto_key/1]).	%Utilities used by compiler

-import(lists,
	[append/1, delete/2, foreach/2, keysearch/3, keysort/2, 
         member/2, reverse/1, sort/1, splitwith/2]).

-include_lib("kernel/include/file.hrl").
-include("erl_compile.hrl").

%%
%%  Exported functions
%%

info(File) ->
    read_info(beam_filename(File)).

chunks(File, Chunks) ->
    read_chunk_data(File, Chunks).

chunks(File, Chunks, Options) ->
    try read_chunk_data(File, Chunks, Options)
    catch Error -> Error end.

all_chunks(File) ->
    read_all_chunks(File).

cmp(File1, File2) ->
    try cmp_files(File1, File2)
    catch Error -> Error end.

cmp_dirs(Dir1, Dir2) ->
    catch compare_dirs(Dir1, Dir2).

diff_dirs(Dir1, Dir2) ->
    catch diff_directories(Dir1, Dir2).

strip(FileName) ->
    try strip_file(FileName)
    catch Error -> Error end.
    
strip_files(Files) when is_list(Files) ->
    try strip_fils(Files)
    catch Error -> Error end.
    
strip_release(Root) ->
    catch strip_rel(Root).

version(File) ->
    case catch read_chunk_data(File, [attributes]) of
	{ok, {Module, [{attributes, Attrs}]}} ->
	    {value, {vsn, Version}} = keysearch(vsn, 1, Attrs),
	    {ok, {Module, Version}};
	Error ->
	    Error
    end.

md5(File) ->
    case catch read_significant_chunks(File) of
	{ok, {Module, Chunks0}} ->
	    Chunks = filter_funtab(Chunks0),
	    {ok, {Module, erlang:md5([C || {_Id, C} <- Chunks])}};
	Error ->
	    Error
    end.

format_error({error, Error}) ->
    format_error(Error);
format_error({error, Module, Error}) ->
    Module:format_error(Error);
format_error({unknown_chunk, File, ChunkName}) ->
    io_lib:format("~p: Cannot find chunk ~p~n", [File, ChunkName]);
format_error({invalid_chunk, File, ChunkId}) ->
    io_lib:format("~p: Invalid contents of chunk ~p~n", [File, ChunkId]);
format_error({not_a_beam_file, File}) ->
    io_lib:format("~p: Not a BEAM file~n", [File]);
format_error({file_error, File, Reason}) ->
    io_lib:format("~p: ~p~n", [File, file:format_error(Reason)]);
format_error({missing_chunk, File, ChunkId}) ->
    io_lib:format("~p: Not a BEAM file: no IFF \"~s\" chunk~n", 
		  [File, ChunkId]);
format_error({invalid_beam_file, File, Pos}) ->
    io_lib:format("~p: Invalid format of BEAM file near byte number ~p~n", 
		  [File, Pos]);
format_error({chunk_too_big, File, ChunkId, Size, Len}) ->
    io_lib:format("~p: Size of chunk \"~s\" is ~p bytes, "
		  "but only ~p bytes could be read~n",
		  [File, ChunkId, Size, Len]);
format_error({chunks_different, Id}) ->
    io_lib:format("Chunk \"~s\" differs in the two files~n", [Id]);
format_error(different_chunks) ->
    "The two files have different chunks\n";
format_error({modules_different, Module1, Module2}) ->
    io_lib:format("Module names ~p and ~p differ in the two files~n", 
		  [Module1, Module2]);
format_error({not_a_directory, Name}) ->
    io_lib:format("~p: Not a directory~n", [Name]);
format_error({key_missing_or_invalid, File, abstract_code}) ->
    io_lib:format("~p: Cannot decrypt abstract code because key is missing or invalid",
		  [File]);
format_error(badfun) ->
    "not a fun or the fun has the wrong arity";
format_error(exists) ->
    "a fun has already been installed";
format_error(E) ->
    io_lib:format("~p~n", [E]).

%% 
%% Exported functions for encrypted debug info.
%%

crypto_key_fun(F) ->
    call_crypto_server({crypto_key_fun, F}).

clear_crypto_key_fun() ->
    call_crypto_server(clear_crypto_key_fun).

make_crypto_key(des3_cbc, String) ->
    <<K1:8/binary,K2:8/binary>> = First = erlang:md5(String),
    <<K3:8/binary,IVec:8/binary>> = erlang:md5([First|reverse(String)]),
    {K1,K2,K3,IVec}.

%%
%%  Local functions
%%

read_info(File) ->
    try
        {ok, Module, Data} = scan_beam(File, info),
        [if
             is_binary(File) -> {binary, File};
             true -> {file, File}
         end, {module, Module}, {chunks, Data}]
    catch Error -> Error end.

diff_directories(Dir1, Dir2) ->
    {OnlyDir1, OnlyDir2, Diff} = compare_dirs(Dir1, Dir2),
    diff_only(Dir1, OnlyDir1),
    diff_only(Dir2, OnlyDir2),
    foreach(fun(D) -> io:format("** different: ~p~n", [D]) end, Diff),
    ok.
    
diff_only(_Dir, []) -> 
    ok;
diff_only(Dir, Only) ->
    io:format("Only in ~p: ~p~n", [Dir, Only]).

%% -> {OnlyInDir1, OnlyInDir2, Different} | throw(Error)
compare_dirs(Dir1, Dir2) ->
    R1 = sofs:relation(beam_files(Dir1)),
    R2 = sofs:relation(beam_files(Dir2)),
    F1 = sofs:domain(R1),
    F2 = sofs:domain(R2),
    {O1, Both, O2} = sofs:symmetric_partition(F1, F2),
    OnlyL1 = sofs:image(R1, O1),
    OnlyL2 = sofs:image(R2, O2),
    B1 = sofs:to_external(sofs:restriction(R1, Both)),
    B2 = sofs:to_external(sofs:restriction(R2, Both)),
    Diff = compare_files(B1, B2, []),
    {sofs:to_external(OnlyL1), sofs:to_external(OnlyL2), Diff}.

compare_files([], [], Acc) ->
    lists:reverse(Acc);
compare_files([{_,F1} | R1], [{_,F2} | R2], Acc) ->
    NAcc = case catch cmp_files(F1, F2) of
	       {error, _Mod, _Reason} ->
		   [{F1, F2} | Acc];
	       ok ->
		   Acc
	   end,
    compare_files(R1, R2, NAcc).

beam_files(Dir) ->
    ok = assert_directory(Dir),
    L = filelib:wildcard(filename:join(Dir, "*.beam")),
    [{filename:basename(Path), Path} || Path <- L].

%% -> ok | throw(Error)
cmp_files(File1, File2) ->
    {ok, {M1, L1}} = read_significant_chunks(File1),
    {ok, {M2, L2}} = read_significant_chunks(File2),
    if
	M1 =:= M2 ->
	    List1 = filter_funtab(L1),
	    List2 = filter_funtab(L2),
	    cmp_lists(List1, List2);
	true ->
	    error({modules_different, M1, M2})
    end.

cmp_lists([], []) ->
    ok;
cmp_lists([{Id, C1} | R1], [{Id, C2} | R2]) ->
    if
	C1 =:= C2 ->
	    cmp_lists(R1, R2);
	true ->
	    error({chunks_different, Id})
    end;
cmp_lists(_, _) ->
    error(different_chunks).
    
strip_rel(Root) ->
    ok = assert_directory(Root),
    strip_fils(filelib:wildcard(filename:join(Root, "lib/*/ebin/*.beam"))).

%% -> {ok, [{Mod, BinaryOrFileName}]} | throw(Error)
strip_fils(Files) ->
    {ok, [begin {ok, Reply} = strip_file(F), Reply end || F <- Files]}.

%% -> {ok, {Mod, FileName}} | {ok, {Mod, binary()}} | throw(Error)
strip_file(File) ->
    {ok, {Mod, Chunks}} = read_significant_chunks(File),
    {ok, Stripped0} = build_module(Chunks),
    Stripped = compress(Stripped0),
    case File of
	_ when is_binary(File) ->
	    {ok, {Mod, Stripped}};
	_ ->
	    FileName = beam_filename(File),
	    case file:open(FileName, [raw, binary, write]) of
		{ok, Fd} ->
		    case file:write(Fd, Stripped) of
			ok ->
			    file:close(Fd),
			    {ok, {Mod, FileName}};
			Error ->
			    file:close(Fd),
			    file_error(FileName, Error)
		    end;
		Error ->
		    file_error(FileName, Error)
	    end
    end.

build_module(Chunks0) ->
    Chunks = list_to_binary(build_chunks(Chunks0)),
    Size = byte_size(Chunks),
    0 = Size rem 4, % Assertion: correct padding?
    {ok, <<"FOR1", (Size+4):32, "BEAM", Chunks/binary>>}.

build_chunks([{Id, Data} | Chunks]) ->
    BId = list_to_binary(Id),
    Size = byte_size(Data),
    Chunk = [<<BId/binary, Size:32>>, Data | pad(Size)],
    [Chunk | build_chunks(Chunks)];
build_chunks([]) -> 
    [].

pad(Size) ->
    case Size rem 4 of
	0 -> [];
	Rem -> lists:duplicate(4 - Rem, 0)
    end.

%% -> {ok, {Module, Chunks}} | throw(Error)
read_significant_chunks(File) ->
    case read_chunk_data(File, significant_chunks(), [allow_missing_chunks]) of
	{ok, {Module, Chunks0}} ->
	    Mandatory = mandatory_chunks(),
	    Chunks = filter_significant_chunks(Chunks0, Mandatory, File, Module),
	    {ok, {Module, Chunks}}
    end.

filter_significant_chunks([{_, Data}=Pair|Cs], Mandatory, File, Mod)
  when is_binary(Data) ->
    [Pair|filter_significant_chunks(Cs, Mandatory, File, Mod)];
filter_significant_chunks([{Id, missing_chunk}|Cs], Mandatory, File, Mod) ->
    case member(Id, Mandatory) of
	false ->
	    filter_significant_chunks(Cs, Mandatory, File, Mod);
	true ->
	    error({missing_chunk, File, Id})
    end;
filter_significant_chunks([], _, _, _) -> [].

filter_funtab([{"FunT"=Tag, <<L:4/binary, Data0/binary>>}|Cs]) ->
    Data = filter_funtab_1(Data0, <<0:32>>),
    Funtab = <<L/binary, (iolist_to_binary(Data))/binary>>,
    [{Tag, Funtab}|filter_funtab(Cs)];
filter_funtab([H|T]) ->
    [H|filter_funtab(T)];
filter_funtab([]) -> [].

filter_funtab_1(<<Important:20/binary,_OldUniq:4/binary,T/binary>>, Zero) ->
    [Important,Zero|filter_funtab_1(T, Zero)];
filter_funtab_1(Tail, _) when is_binary(Tail) -> [Tail].

read_all_chunks(File0) when is_atom(File0);
			    is_list(File0); 
			    is_binary(File0) ->
    try
        File = beam_filename(File0),
        {ok, Module, ChunkIds0} = scan_beam(File, info),
        ChunkIds = [Name || {Name,_,_} <- ChunkIds0],
        {ok, Module, Chunks} = scan_beam(File, ChunkIds),
        {ok, Module, lists:reverse(Chunks)}
    catch Error -> Error end.

read_chunk_data(File0, ChunkNames) ->
    try read_chunk_data(File0, ChunkNames, [])
    catch Error -> Error end.

%% -> {ok, {Module, Symbols}} | throw(Error)
read_chunk_data(File0, ChunkNames0, Options)
  when is_atom(File0); is_list(File0); is_binary(File0) ->
    File = beam_filename(File0),
    {ChunkIds, Names} = check_chunks(ChunkNames0, File, [], []),
    AllowMissingChunks = member(allow_missing_chunks, Options),
    {ok, Module, Chunks} = scan_beam(File, ChunkIds, AllowMissingChunks),
    AT = ets:new(beam_symbols, []),
    T = {empty, AT},
    try chunks_to_data(Names, Chunks, File, Chunks, Module, T, [])
    after ets:delete(AT) 
    end.
    
%% -> {ok, list()} | throw(Error)
check_chunks([ChunkName | Ids], File, IL, L) when is_atom(ChunkName) ->
    ChunkId = chunk_name_to_id(ChunkName, File),
    check_chunks(Ids, File, [ChunkId | IL], [{ChunkId, ChunkName} | L]);
check_chunks([ChunkId | Ids], File, IL, L) -> % when is_list(ChunkId)
    check_chunks(Ids, File, [ChunkId | IL], [{ChunkId, ChunkId} | L]);
check_chunks([], _File, IL, L) ->
    {lists:usort(IL), reverse(L)}.

%% -> {ok, Module, Data} | throw(Error)
scan_beam(File, What) ->
    scan_beam(File, What, false).

%% -> {ok, Module, Data} | throw(Error)
scan_beam(File, What0, AllowMissingChunks) ->
    case scan_beam1(File, What0) of
	{missing, _FD, Mod, Data, What} when AllowMissingChunks ->
	    {ok, Mod, [{Id, missing_chunk} || Id <- What] ++ Data};
	{missing, FD, _Mod, _Data, What} ->
	    error({missing_chunk, filename(FD), hd(What)});
	R ->
	    R
    end.

%% -> {ok, Module, Data} | throw(Error)
scan_beam1(File, What) ->
    FD = open_file(File),
    case catch scan_beam2(FD, What) of
	Error when error =:= element(1, Error) ->
	    throw(Error);
	R ->
	    R
    end.

scan_beam2(FD, What) ->
    case pread(FD, 0, 12) of
	{NFD, {ok, <<"FOR1", _Size:32, "BEAM">>}} ->
	    Start = 12,
	    scan_beam(NFD, Start, What, 17, []);
	_Error -> 
	    error({not_a_beam_file, filename(FD)})
    end.

scan_beam(_FD, _Pos, [], Mod, Data) when Mod =/= 17 ->
    {ok, Mod, Data};    
scan_beam(FD, Pos, What, Mod, Data) ->
    case pread(FD, Pos, 8) of
	{_NFD, eof} when Mod =:= 17 ->
	    error({missing_chunk, filename(FD), "Atom"});	    
	{_NFD, eof} when What =:= info ->
	    {ok, Mod, reverse(Data)};
	{NFD, eof} ->
	    {missing, NFD, Mod, Data, What};
	{NFD, {ok, <<IdL:4/binary, Sz:32>>}} ->
	    Id = binary_to_list(IdL),
	    Pos1 = Pos + 8,
	    Pos2 = (4 * trunc((Sz+3) / 4)) + Pos1,
	    get_data(What, Id, NFD, Sz, Pos1, Pos2, Mod, Data);
	{_NFD, {ok, _ChunkHead}} ->
	    error({invalid_beam_file, filename(FD), Pos})
    end.

get_data(Cs, "Atom"=Id, FD, Size, Pos, Pos2, _Mod, Data) ->
    NewCs = del_chunk(Id, Cs),
    {NFD, Chunk} = get_chunk(Id, Pos, Size, FD),
    <<_Num:32, Chunk2/binary>> = Chunk,
    {Module, _} = extract_atom(Chunk2),
    C = case Cs of
	    info -> 
		{Id, Pos, Size};
	    _ -> 
		{Id, Chunk}
	end,
    scan_beam(NFD, Pos2, NewCs, Module, [C | Data]);
get_data(info, Id, FD, Size, Pos, Pos2, Mod, Data) ->
    scan_beam(FD, Pos2, info, Mod, [{Id, Pos, Size} | Data]);
get_data(Chunks, Id, FD, Size, Pos, Pos2, Mod, Data) ->
    {NFD, NewData} = case member(Id, Chunks) of
			 true ->
			     {FD1, Chunk} = get_chunk(Id, Pos, Size, FD),
			     {FD1, [{Id, Chunk} | Data]};
			 false ->
			     {FD, Data}
	      end,
    NewChunks = del_chunk(Id, Chunks),
    scan_beam(NFD, Pos2, NewChunks, Mod, NewData).
     
del_chunk(_Id, info) ->
    info;
del_chunk(Id, Chunks) ->
    delete(Id, Chunks).

%% -> {NFD, binary()} | throw(Error)
get_chunk(Id, Pos, Size, FD) ->
    case pread(FD, Pos, Size) of
	{NFD, eof} when Size =:= 0 -> % cannot happen
	    {NFD, <<>>};
	{_NFD, eof} when Size > 0 ->
	    error({chunk_too_big, filename(FD), Id, Size, 0});
	{_NFD, {ok, Chunk}} when Size > byte_size(Chunk) ->
	    error({chunk_too_big, filename(FD), Id, Size, byte_size(Chunk)});
	{NFD, {ok, Chunk}} -> % when Size =:= size(Chunk)
	    {NFD, Chunk}
    end.

chunks_to_data([{Id, Name} | CNs], Chunks, File, Cs, Module, Atoms, L) ->
    {value, {_Id, Chunk}} = keysearch(Id, 1, Chunks),
    {NewAtoms, Ret} = chunk_to_data(Name, Chunk, File, Cs, Atoms, Module),
    chunks_to_data(CNs, Chunks, File, Cs, Module, NewAtoms, [Ret | L]);
chunks_to_data([], _Chunks, _File, _Cs, Module, _Atoms, L) ->
    {ok, {Module, reverse(L)}}.

chunk_to_data(attributes=Id, Chunk, File, _Cs, AtomTable, _Mod) ->
    try
	Term = binary_to_term(Chunk),
	{AtomTable, {Id, attributes(Term)}}
    catch
	error:badarg ->
	    error({invalid_chunk, File, chunk_name_to_id(Id, File)})
    end;
chunk_to_data(compile_info=Id, Chunk, File, _Cs, AtomTable, _Mod) ->
    try
	{AtomTable, {Id, binary_to_term(Chunk)}}
    catch
	error:badarg ->
	    error({invalid_chunk, File, chunk_name_to_id(Id, File)})
    end;
chunk_to_data(abstract_code=Id, Chunk, File, _Cs, AtomTable, Mod) ->
    case Chunk of
	<<>> ->
	    {AtomTable, {Id, no_abstract_code}};
	<<0:8,N:8,Mode0:N/binary,Rest/binary>> ->
	    Mode = list_to_atom(binary_to_list(Mode0)),
	    decrypt_abst(Mode, Mod, File, Id, AtomTable, Rest);
	_ ->
	    case catch binary_to_term(Chunk) of
		{'EXIT', _} ->
		    error({invalid_chunk, File, chunk_name_to_id(Id, File)});
		Term ->
		    {AtomTable, {Id, Term}}
	    end
    end;
chunk_to_data(atoms=Id, _Chunk, _File, Cs, AtomTable0, _Mod) ->
    AtomTable = ensure_atoms(AtomTable0, Cs),
    Atoms = ets:tab2list(AtomTable),
    {AtomTable, {Id, lists:sort(Atoms)}};
chunk_to_data(ChunkName, Chunk, File,
	      Cs, AtomTable, _Mod) when is_atom(ChunkName) ->
    case catch symbols(Chunk, AtomTable, Cs, ChunkName) of
	{ok, NewAtomTable, S} ->
	    {NewAtomTable, {ChunkName, S}};
	{'EXIT', _} ->
	    error({invalid_chunk, File, chunk_name_to_id(ChunkName, File)})
    end;
chunk_to_data(ChunkId, Chunk, _File, 
	      _Cs, AtomTable, _Module) when is_list(ChunkId) ->
    {AtomTable, {ChunkId, Chunk}}. % Chunk is a binary

chunk_name_to_id(atoms, _)           -> "Atom";
chunk_name_to_id(indexed_imports, _) -> "ImpT";
chunk_name_to_id(imports, _)         -> "ImpT";
chunk_name_to_id(exports, _)         -> "ExpT";
chunk_name_to_id(labeled_exports, _) -> "ExpT";
chunk_name_to_id(locals, _)          -> "LocT";
chunk_name_to_id(labeled_locals, _)  -> "LocT";
chunk_name_to_id(attributes, _)      -> "Attr";
chunk_name_to_id(abstract_code, _)   -> "Abst";
chunk_name_to_id(compile_info, _)    -> "CInf";
chunk_name_to_id(Other, File) -> 
    error({unknown_chunk, File, Other}).

%% Extract attributes

attributes(Attrs) ->
    attributes(keysort(1, Attrs), []).

attributes([], R) ->
    reverse(R);
attributes(L, R) ->
    K = element(1, hd(L)),
    {L1, L2} = splitwith(fun(T) -> element(1, T) =:= K end, L),
    V = append([A || {_, A} <- L1]),
    attributes(L2, [{K, V} | R]).

%% Extract symbols

symbols(<<_Num:32, B/binary>>, AT0, Cs, Name) ->
    AT = ensure_atoms(AT0, Cs),
    symbols1(B, AT, Name, [], 1).

symbols1(<<I1:32, I2:32, I3:32, B/binary>>, AT, Name, S, Cnt) ->
    Symbol = symbol(Name, AT, I1, I2, I3, Cnt),
    symbols1(B, AT, Name, [Symbol|S], Cnt+1);
symbols1(<<>>, AT, _Name, S, _Cnt) ->
    {ok, AT, sort(S)}.

symbol(indexed_imports, AT, I1, I2, I3, Cnt) ->
    {Cnt, atm(AT, I1), atm(AT, I2), I3};
symbol(imports, AT, I1, I2, I3, _Cnt) ->
    {atm(AT, I1), atm(AT, I2), I3};
symbol(labeled_exports, AT, I1, I2, I3, _Cnt) ->
    {atm(AT, I1), I2, I3};
symbol(labeled_locals, AT, I1, I2, I3, _Cnt) ->
    {atm(AT, I1), I2, I3};
symbol(_, AT, I1, I2, _I3, _Cnt) ->
    {atm(AT, I1), I2}.

atm(AT, N) ->
    [{_N, S}] = ets:lookup(AT, N),
    S.

%% AT is updated.
ensure_atoms({empty, AT}, Cs) ->
    {value, {_Id, AtomChunk}} =  keysearch("Atom", 1, Cs),
    extract_atoms(AtomChunk, AT),
    AT;
ensure_atoms(AT, _Cs) ->
    AT.

extract_atoms(<<_Num:32, B/binary>>, AT) ->
    extract_atoms(B, 1, AT).

extract_atoms(<<>>, _I, _AT) ->
    true;
extract_atoms(B, I, AT) ->
    {Atom, B1} = extract_atom(B),
    true = ets:insert(AT, {I, Atom}),
    extract_atoms(B1, I+1, AT).

extract_atom(<<Len, B/binary>>) ->
    <<SB:Len/binary, Tail/binary>> = B,
    {list_to_atom(binary_to_list(SB)), Tail}.

%%% Utils.

-record(bb, {pos = 0 :: integer(),
	     bin :: binary(),
	     source :: binary() | string()}).

open_file(<<"FOR1",_/binary>>=Binary) ->
    #bb{bin = Binary, source = Binary};
open_file(Binary0) when is_binary(Binary0) ->
    Binary = uncompress(Binary0),
    #bb{bin = Binary, source = Binary};
open_file(FileName) ->
    case file:open(FileName, [read, raw, binary]) of
	{ok, Fd} ->
	    read_all(Fd, FileName, []);
	Error ->
	    file_error(FileName, Error)
    end.

read_all(Fd, FileName, Bins) ->
    case file:read(Fd, 1 bsl 18) of
	{ok, Bin} ->
	    read_all(Fd, FileName, [Bin | Bins]);
	eof ->
	    file:close(Fd),
	    #bb{bin = uncompress(reverse(Bins)), source = FileName};
	Error ->
	    file:close(Fd),
	    file_error(FileName, Error)
    end.

pread(FD, AtPos, Size) ->
    #bb{pos = Pos, bin = Binary} = FD,
    Skip = AtPos-Pos,
    case Binary of
	<<_:Skip/binary, B:Size/binary, Bin/binary>> ->
	    NFD = FD#bb{pos = AtPos+Size, bin = Bin},
	    {NFD, {ok, B}};
	<<_:Skip/binary, Bin/binary>> when byte_size(Bin) > 0 ->
	    NFD = FD#bb{pos = AtPos+byte_size(Bin), bin = <<>>},
	    {NFD, {ok, Bin}};
        _ ->
            {FD, eof}
    end.

filename(BB) when is_binary(BB#bb.source) ->
    BB#bb.source;
filename(BB) -> 
    list_to_atom(BB#bb.source).    

beam_filename(Bin) when is_binary(Bin) ->
    Bin;
beam_filename(File) ->
    filename:rootname(File, ".beam") ++ ".beam".


uncompress(Binary0) ->
    {ok, Fd} = ram_file:open(Binary0, [write, binary]),
    {ok, _} = ram_file:uncompress(Fd),
    {ok, Binary} = ram_file:get_file(Fd),
    ok = ram_file:close(Fd),
    Binary.

compress(Binary0) ->
    {ok, Fd} = ram_file:open(Binary0, [write, binary]),
    {ok, _} = ram_file:compress(Fd),
    {ok, Binary} = ram_file:get_file(Fd),
    ok = ram_file:close(Fd),
    Binary.

%% -> ok | throw(Error)
assert_directory(FileName) ->
    case filelib:is_dir(FileName) of
	true ->
	    ok;
	false ->
	    error({not_a_directory, FileName})
    end.

-spec(file_error/2 :: ([char(),...], {'error',atom()}) -> no_return()).

file_error(FileName, {error, Reason}) ->
    error({file_error, FileName, Reason}).

-spec(error/1 :: (_) -> no_return()).

error(Reason) ->
    throw({error, ?MODULE, Reason}).


%% The following chunks are significant when calculating the MD5 for a module,
%% and also the modules that must be retained when stripping a file.
%% They are listed in the order that they should be MD5:ed.

significant_chunks() ->
    ["Atom", "Code", "StrT", "ImpT", "ExpT", "FunT", "LitT"].

%% The following chunks are mandatory in every Beam file.

mandatory_chunks() ->
    ["Code", "ExpT", "ImpT", "StrT", "Atom"].

%%% ====================================================================
%%% The rest of the file handles encrypted debug info.
%%%
%%% Encrypting the debug info is only useful if you want to
%%% have the debug info available all the time (maybe even in a live
%%% system), but don't want to risk that anyone else but yourself
%%% can use it.
%%% ====================================================================

-record(state, {crypto_key_f :: fun((_) -> _)}).

-define(CRYPTO_KEY_SERVER, beam_lib__crypto_key_server).

decrypt_abst(Mode, Module, File, Id, AtomTable, Bin) ->
    try
	KeyString = get_crypto_key({debug_info, Mode, Module, File}),
	Key = make_crypto_key(des3_cbc, KeyString),
	Term = decrypt_abst_1(Mode, Key, Bin),
	{AtomTable, {Id, Term}}
    catch
	_:_ ->
	    error({key_missing_or_invalid, File, Id})
    end.

decrypt_abst_1(des3_cbc, {K1, K2, K3, IVec}, Bin) ->
    ok = start_crypto(),
    NewBin = crypto:des3_cbc_decrypt(K1, K2, K3, IVec, Bin),
    binary_to_term(NewBin).

start_crypto() ->
    case crypto:start() of
	{error, {already_started, _}} ->
	    ok;
	ok ->
	    ok
    end.

get_crypto_key(What) ->
    call_crypto_server({get_crypto_key, What}).

call_crypto_server(Req) ->
    try 
	gen_server:call(?CRYPTO_KEY_SERVER, Req, infinity)
    catch
	exit:{noproc,_} ->
	    start_crypto_server(),
	    erlang:yield(),
	    call_crypto_server(Req)
    end.

start_crypto_server() ->
    gen_server:start({local,?CRYPTO_KEY_SERVER}, ?MODULE, [], []).

init([]) ->
    {ok, #state{}}.

handle_call({get_crypto_key, _}=R, From, #state{crypto_key_f=undefined}=S) ->
    case crypto_key_fun_from_file() of
	error ->
	    {reply, error, S};
	F when is_function(F) ->
	    %% The init function for the fun has already been called.
	    handle_call(R, From, S#state{crypto_key_f=F})
    end;
handle_call({get_crypto_key, What}, From, #state{crypto_key_f=F}=S) ->
    try
	Result = F(What),
	%% The result may hold information that we don't want 
	%% lying around. Reply first, then GC, then noreply.
	gen_server:reply(From, Result),
	erlang:garbage_collect(),
	{noreply, S}
    catch
	_:_ ->
	    {reply, error, S}
    end;
handle_call({crypto_key_fun, F}, {_,_} = From, S) ->
    case S#state.crypto_key_f of
	undefined ->
	    %% Don't allow tuple funs here. (They weren't allowed before,
	    %% so there is no reason to allow them now.)
	    if is_function(F), is_function(F, 1) ->
		    {Result, Fun, Reply} = 
			case catch F(init) of
			    ok ->
				{true, F, ok};
			    {ok, F1} when is_function(F1) ->
				if
				    is_function(F1, 1) ->
					{true, F1, ok};
				    true ->
					{false, undefined, 
					 {error, badfun}}
				end;
			    {error, Reason} ->
				{false, undefined, {error, Reason}};
			    {'EXIT', Reason} ->
				{false, undefined, {error, Reason}}
			end,
		    gen_server:reply(From, Reply),
		    erlang:garbage_collect(),
		    NewS = case Result of
			       true ->
				   S#state{crypto_key_f = Fun};
			       false ->
				   S
			   end,
		    {noreply, NewS};
	       true ->
		    {reply, {error, badfun}, S}
	    end;
	OtherF when is_function(OtherF) ->
	    {reply, {error, exists}, S}
    end;
handle_call(clear_crypto_key_fun, _From, S) ->
    case S#state.crypto_key_f of
	undefined ->
	    {stop,normal,undefined,S};
	F ->
	    Result = (catch F(clear)),
	    {stop,normal,{ok,Result},S}
    end.

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
    
terminate(_Reason, _State) ->
    ok.

crypto_key_fun_from_file() ->
    case init:get_argument(home) of
	{ok,[[Home]]} ->
	    crypto_key_fun_from_file_1([".",Home]);
	_ ->
	    crypto_key_fun_from_file_1(["."])
    end.

crypto_key_fun_from_file_1(Path) ->
    case f_p_s(Path, ".erlang.crypt") of
	{ok, KeyInfo, _} ->
	    try_load_crypto_fun(KeyInfo);
	_ ->
	    error
    end.

f_p_s(P, F) ->
    case file:path_script(P, F) of
	{error, enoent} ->
	    {error, enoent};
	{error, {Line, _Mod, _Term}=E} ->
	    error("file:path_script(~p,~p): error on line ~p: ~s~n",
		  [P, F, Line, file:format_error(E)]),
	    ok;
	{error, E} when is_atom(E) ->
	    error("file:path_script(~p,~p): ~s~n",
		  [P, F, file:format_error(E)]),
	    ok;
	Other ->
	    Other
    end.

try_load_crypto_fun(KeyInfo) when is_list(KeyInfo) ->
    T = ets:new(keys, [private, set]),
    foreach(
      fun({debug_info, Mode, M, Key}) when is_atom(M) ->
	      ets:insert(T, {{debug_info,Mode,M,[]}, Key});
	 ({debug_info, Mode, [], Key}) ->
	      ets:insert(T, {{debug_info, Mode, [], []}, Key});
	 (Other) ->
	      error("unknown key: ~p~n", [Other])
      end, KeyInfo),
    fun({debug_info, Mode, M, F}) ->
	    alt_lookup_key(
	      [{debug_info,Mode,M,F},
	       {debug_info,Mode,M,[]},
	       {debug_info,Mode,[],[]}], T);
       (clear) ->
	    ets:delete(T);
       (_) ->
	    error
    end;
try_load_crypto_fun(KeyInfo) ->
    error("unrecognized crypto key info: ~p\n", [KeyInfo]).

alt_lookup_key([H|T], Tab) ->
    case ets:lookup(Tab, H) of
	[] ->
	    alt_lookup_key(T, Tab);
	[{_, Val}] ->
	    Val
    end;
alt_lookup_key([], _) ->
    error.

error(Fmt, Args) ->
    error_logger:error_msg(Fmt, Args),
    error.
