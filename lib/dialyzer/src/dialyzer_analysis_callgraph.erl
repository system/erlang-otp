%% -*- erlang-indent-level: 2 -*-
%%--------------------------------------------------------------------
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
%% Copyright 2006, 2007 Tobias Lindahl and Kostis Sagonas
%% 
%% $Id$
%%

%%%-------------------------------------------------------------------
%%% File    : dialyzer_analysis_callgraph.erl
%%% Author  : Tobias Lindahl <tobiasl@it.uu.se>
%%% Description : 
%%%
%%% Created :  5 Apr 2005 by Tobias Lindahl <tobiasl@it.uu.se>
%%%-------------------------------------------------------------------
-module(dialyzer_analysis_callgraph).

-export([start/3]).

-include("dialyzer.hrl").

-record(analysis_state, 
	{  
	  codeserver,
	  analysis_type,
	  defines,
	  doc_plt,
	  include_dirs,
	  no_warn_unused,
	  options,
	  parent,
	  plt,
	  start_from,
	  supress_inline
	 }).

-record(state, {parent, legal_warnings}).

-define(HIPE_COMPILE_OPTS, [dialyzer|?HIPE_DEF_OPTS]).

%%____________________________________________________________
%%
%% Main
%%

start(Parent, LegalWarnings, Analysis) ->
  NewAnalysis1 = expand_files(Analysis),
  init_plt(NewAnalysis1),
  NewAnalysis2 = run_analysis(NewAnalysis1),
  State = #state{parent=Parent, legal_warnings=LegalWarnings},
  loop(State, NewAnalysis2, none).

run_analysis(Analysis) ->
  Self = self(),
  Fun = fun() -> analysis_start(Self, Analysis) end,
  Analysis#analysis{analysis_pid=spawn_link(Fun)}.

loop(State, Analysis = #analysis{}, ExtCalls) ->
  AnalPid = Analysis#analysis.analysis_pid,
  Parent = State#state.parent,
  receive
    {AnalPid, log, LogMsg} ->
      send_log(Parent, LogMsg),
      loop(State, Analysis, ExtCalls);
    {AnalPid, warnings, Warnings} ->
      case filter_warnings(State#state.legal_warnings, Warnings) of
	[] -> ok;
	SendWarnings ->
	  send_warnings(Parent, SendWarnings)
      end,
      loop(State, Analysis, ExtCalls);
    {AnalPid, error, Msg} ->
      send_error(Parent, Msg),
      loop(State, Analysis, ExtCalls);
    {AnalPid, done} ->      
      case ExtCalls =:= none of
	true ->
	  send_analysis_done(Parent);
	false ->
	  send_ext_calls(Parent, ExtCalls),
	  send_analysis_done(Parent)
      end;
    {AnalPid, ext_calls, NewExtCalls} ->
      loop(State, Analysis, NewExtCalls);
    {Parent, stop} ->
      exit(AnalPid, kill),
      ok
  end.

%%____________________________________________________________
%%
%% The Analysis
%%

analysis_start(Parent, Analysis) ->
  %%XXX: Until we move the icode analysis out of HiPE
  put(hipe_target_arch, x86), 
  
  CServer = dialyzer_codeserver:new(),

  Plt = Analysis#analysis.user_plt,
  State = #analysis_state{codeserver=CServer,
			  analysis_type=Analysis#analysis.type,
			  defines=Analysis#analysis.defines,
			  doc_plt=Analysis#analysis.doc_plt,
			  include_dirs=Analysis#analysis.include_dirs,
			  plt=Plt,
			  parent=Parent,
			  start_from=Analysis#analysis.start_from,
			  supress_inline=Analysis#analysis.supress_inline
			 },
  Files = ordsets:from_list(Analysis#analysis.files),
  {Callgraph, NoWarn, NewCServer} = compile_and_store(Files, State),
  State1 = State#analysis_state{codeserver=NewCServer},
  State2 = State1#analysis_state{no_warn_unused=NoWarn},
  %% Remove all old versions of the files being analyzed
  dialyzer_plt:delete_list(Plt, dialyzer_callgraph:all_nodes(Callgraph)),
  analyze_callgraph(Callgraph, State2),
  dialyzer_callgraph:delete(Callgraph),
  Exports = dialyzer_codeserver:all_exports(NewCServer),
  dialyzer_plt:strip_non_member_mfas(Plt, Exports),
  dialyzer_codeserver:delete(NewCServer),
  send_analysis_done(Parent).
  
analyze_callgraph(Callgraph, State) ->
  Plt = State#analysis_state.plt,
  Codeserver = State#analysis_state.codeserver,
  case State#analysis_state.analysis_type of
    plt_build ->
      Callgraph1 = dialyzer_callgraph:finalize(Callgraph),
      dialyzer_succ_typings:analyze_callgraph(Callgraph1, Plt, Codeserver);
    old_style ->
      case erlang:system_info(schedulers) of
	1 -> 
	  Callgraph1 = dialyzer_callgraph:finalize(Callgraph),
	  analyze_callgraph_single_threaded(Callgraph1, State);
	N when is_integer(N), N > 1 -> 
	  analyze_callgraph_in_parallel(Callgraph, State, N)
      end;
    Type when Type =:= dataflow; Type =:= succ_typings ->
      NoWarn = State#analysis_state.no_warn_unused,
      DocPlt = State#analysis_state.doc_plt,
      Callgraph1 = dialyzer_callgraph:finalize(Callgraph),
      Warnings = dialyzer_succ_typings:get_warnings(Callgraph1, Plt, DocPlt,
						    Codeserver, NoWarn, Type),
      send_warnings(State#analysis_state.parent, Warnings),
      ok
  end.

analyze_callgraph_in_parallel(Callgraph, State, N) ->
  CallgraphList1 = dialyzer_callgraph:split_into_components(Callgraph),
  CallgraphList2 = [dialyzer_callgraph:finalize(CG) || CG <- CallgraphList1],
  parallel_analysis_loop(CallgraphList2, State, 0, N).

parallel_analysis_loop([], #analysis_state{parent=Parent}, 0, _MaxProc) ->
  send_analysis_done(Parent),
  ok;
parallel_analysis_loop([CG|CGs], State, Running, MaxProc) 
  when Running < MaxProc ->
  Pid = self(),
  spawn_link(fun()->
		 %%XXX: Until we move the icode analysis out of HiPE
		 put(hipe_target_arch, x86), 
		 %%io:format("Starting with nodes: ~p\n",
		 %%          [dialyzer_callgraph:all_nodes(CG)]),
		 %% Hijack our parents messages.
		 State1 = State#analysis_state{parent=Pid},
		 analyze_callgraph_single_threaded(CG, State1),
		 Pid ! done
	     end),
  parallel_analysis_loop(CGs, State, Running+1, MaxProc);
parallel_analysis_loop(CGs, State, Running, MaxProc) ->
  Parent =  State#analysis_state.parent,
  receive
    {_Pid, log, LogMsg} ->
      Parent ! {self(), log, LogMsg},
      parallel_analysis_loop(CGs, State, Running, MaxProc);
    {_Pid, warnings, Warnings} -> 
      Parent ! {self(), warnings, Warnings},
      parallel_analysis_loop(CGs, State, Running, MaxProc);
    {_Pid, error, Msg} ->
      Parent ! {self(), error, Msg},
      parallel_analysis_loop(CGs, State, Running, MaxProc);
    done ->
      parallel_analysis_loop(CGs, State, Running - 1, MaxProc)
  end.

analyze_callgraph_single_threaded(Callgraph, State) ->
  case dialyzer_callgraph:take_scc(Callgraph) of
    {ok, SCC, NewCallgraph} ->
      analyze_scc_warnings(SCC, Callgraph, State),
      analyze_callgraph_single_threaded(NewCallgraph, State);
    none ->
      ok
  end.

analyze_scc_warnings([Fun], Callgraph, State=#analysis_state{parent=Parent}) ->
  Msg = io_lib:format("Analyzing Fun: ~p\n", [Fun]),
  send_log(Parent, Msg),  
  case dialyzer_callgraph:is_self_rec(Fun, Callgraph) of
    true -> analyze_scc_icode([Fun], State);
    false -> 
      {_, Warnings} = analyze_fun_icode(Fun, State),
      send_warnings(Parent, Warnings)
  end;
analyze_scc_warnings(SCC, _Callgraph, State = #analysis_state{parent=Parent}) ->
  %%io:format("Analyzing scc: ~p\n", [SCC]),
  Msg = io_lib:format("Analyzing SCC: ~p\n", [SCC]),
  send_log(Parent, Msg),
  analyze_scc_icode(SCC, State).

analyze_scc_icode(SCC, State = #analysis_state{parent=Parent}) ->
  Res = [analyze_fun_icode(MFA, State) || MFA <- SCC],
  case lists:any(fun({X, _}) -> X =:= not_fixpoint end, Res) of
    true -> 
      analyze_scc_icode(SCC, State);
    false -> 
      send_log(Parent, "Reached fixpoint for SCC\n"),
      Warnings = lists:foldl(fun({_, W}, Acc) -> W ++ Acc end, [], Res),
      send_warnings(Parent, Warnings)
  end.

analyze_fun_icode(MFA, #analysis_state{codeserver=CServer, doc_plt=DocPlt,
				       no_warn_unused=NoWarn,
				       parent=Parent, plt=Plt}) ->
  %%io:format("Analyzing icode for: ~p\n", [MFA]),
  case dialyzer_codeserver:lookup(MFA, icode, CServer) of
    {ok, CFG} ->
      Msg1 = io_lib:format("  Analyzing icode for: ~p ...", [MFA]),
      send_log(Parent, Msg1),
      {T1, _} = statistics(runtime),
      Res = dialyzer_icode:run_analysis(CFG, MFA, Plt, NoWarn, true),
      {T2, _} = statistics(runtime),
      Msg2 = io_lib:format("done in ~.2f secs\n", [(T2-T1)/1000]),
      send_log(Parent, Msg2),
      case Res of
	{not_fixpoint, UpdateInfo, Warnings} ->
	  if DocPlt =:= undefined -> ok;
	     true -> dialyzer_plt:insert(DocPlt, [UpdateInfo])
	  end,
	  dialyzer_plt:insert(Plt, [UpdateInfo]),
	  {not_fixpoint, Warnings};
	{fixpoint, UpdateInfo, Warnings} ->
	  if DocPlt =:= undefined -> ok;
	     true -> dialyzer_plt:insert(DocPlt, [UpdateInfo])
	  end,
	  dialyzer_plt:insert(Plt, [UpdateInfo]),
	  {fixpoint, Warnings}
      end;
    error ->
      %% Since HiPE removes module_info it is ok to not find the code
      %% for it. The only time this happens is when we start from
      %% byte_code and there is no abstract code.
      case MFA of
	{_, module_info, 0} -> ok;
	{_, module_info, 1} -> ok;
	_ ->
	  Msg = io_lib:format("  Could not find icode for ~w\n", [MFA]),
	  send_error(Parent, Msg)
      end,
      {fixpoint, []}
  end.

%%____________________________________________________________
%%
%% Build the callgraph and fill the codeserver.
%%

compile_and_store(Files, State = #analysis_state{}) ->
  send_log(State#analysis_state.parent, 
	   "Reading files and computing callgraph... "),
  {T1, _} = statistics(runtime),
  Includes = [{i, X} || X <- State#analysis_state.include_dirs],
  Defines = [{d, Macro, Val} || {Macro, Val} <- State#analysis_state.defines],
  Callgraph = dialyzer_callgraph:new(),
  AnalType = State#analysis_state.analysis_type,
  Plt = State#analysis_state.plt,
  case State#analysis_state.start_from of
    src_code -> 
      Fun = fun(File, {TmpCG, TmpCServer, TmpFailed, TmpNoWarn}) ->
		case compile_src(File, Includes, Defines, 
				 TmpCG, TmpCServer, AnalType, Plt) of
		  {error, Reason} -> 
		    {TmpCG, TmpCServer, [{File, Reason}|TmpFailed], TmpNoWarn};
		  {ok, NewCG, NoWarn, NewCServer} -> 
		    {NewCG, NewCServer, TmpFailed, NoWarn++TmpNoWarn}
		end
	    end;
    byte_code ->
      Fun = fun(File, {TmpCG, TmpCServer, TmpFailed, TmpNoWarn}) -> 
		case compile_byte(File, TmpCG, TmpCServer, AnalType, Plt) of
		  {error, Reason} -> 
		    {TmpCG, TmpCServer, [{File, Reason}|TmpFailed], TmpNoWarn};
		  {ok, NewCG, NoWarn, NewCServer} -> 
		    {NewCG, NewCServer, TmpFailed, NoWarn++TmpNoWarn}
		end
	    end
  end,
  CServer = State#analysis_state.codeserver,
  {NewCallgraph1, NewCServer, Failed, NoWarn} = 
    lists:foldl(Fun, {Callgraph, CServer, [], []}, Files),
  {T2, _} = statistics(runtime),
  Msg1 = io_lib:format("done in ~.2f secs\n"
		       "Removing edges... ", 
		       [(T2-T1)/1000]),
  send_log(State#analysis_state.parent, Msg1),

  %%io:format("All exports: ~p\n", [dialyzer_codeserver:all_exports(NewCServer)]),
  
  NewCallgraph2 = cleanup_callgraph(State, NewCServer, NewCallgraph1, Files),
  send_scan_fail(State#analysis_state.parent, Failed),
  {T3, _} = statistics(runtime),
  Msg2 = io_lib:format("done in ~.2f secs\n", [(T3-T2)/1000]),
  send_log(State#analysis_state.parent, Msg2),  
  {NewCallgraph2, sets:from_list(NoWarn), NewCServer}.

cleanup_callgraph(#analysis_state{plt=InitPlt, parent=Parent, 
				  start_from=StartFrom, 
				  analysis_type=AnalType,
				  codeserver=CodeServer}, 
		  CServer, Callgraph, Files) ->
  {Callgraph1, ExtCalls} = dialyzer_callgraph:remove_external(Callgraph),
  ExtCalls1 = lists:filter(fun({_From, To}) -> 
			       not dialyzer_plt:contains_mfa(InitPlt, To)
			   end, ExtCalls),
  {BadCalls1, RealExtCalls} =
    if ExtCalls1 =:= [] -> {[], []};
       true -> 
	Modules = 
	  case StartFrom of
	    byte_code -> 
	      [list_to_atom(filename:basename(F, ".beam")) || F <- Files];
	    src_code -> 
	      [list_to_atom(filename:basename(F, ".erl")) || F <- Files]
	  end,
	ModuleSet = sets:from_list(Modules),
	lists:partition(fun({_From, {M, _F, _A}}) -> 
			    sets:is_element(M, ModuleSet)
			end, ExtCalls1)
    end,
  NonLocalCalls = dialyzer_callgraph:non_local_calls(Callgraph1),
  BadCalls2 = lists:filter(fun({_From, To}) ->
			       not dialyzer_codeserver:is_exported(To, CServer)
			   end, NonLocalCalls),
  case BadCalls1 ++ BadCalls2 of
    [] -> ok;
    BadCalls -> send_bad_calls(Parent, BadCalls, AnalType, CodeServer)
  end,
  if RealExtCalls =:= [] -> ok;
     true ->
      send_ext_calls(Parent, lists:usort([To || {_From, To} <- RealExtCalls]))
  end,
  Callgraph1.

compile_src(File, Includes, Defines, Callgraph, CServer, AnalType, Plt) ->
  DefaultIncludes = default_includes(filename:dirname(File)),
  DefCompOpts = ?SRC_COMPILE_OPTS ++ Includes++Defines++DefaultIncludes,
  CompOpts = if AnalType =:= old_style -> DefCompOpts;
		true -> [no_copt|DefCompOpts]
	     end,
  Mod = list_to_atom(filename:basename(File, ".erl")),
  case dialyzer_utils:get_abstract_code_from_src(File, CompOpts) of
    {error, Msg} -> {error, Msg};
    AbstrCode ->
      case dialyzer_utils:get_core_from_abstract_code(AbstrCode, CompOpts) of
	error -> {error, "  Could not find abstract code for: "++File};
	Core ->
	  NoWarn = abs_get_nowarn(AbstrCode, Mod),
	  case dialyzer_utils:get_record_info(AbstrCode) of
	    {error, _} = Error -> Error;
	    {ok, RecInfo} ->
	      CServer2 = 
		dialyzer_codeserver:store_records(Mod, RecInfo, CServer),
	      compile_core(Mod, Core, NoWarn, Callgraph, 
			   CServer2, AnalType, Plt)
	  end
      end
  end.

compile_byte(File, Callgraph, CServer, AnalType, Plt) ->
  %% We must always set the code path, because the HiPE compiler
  %% does a M:module_info() call!
  OldPath = code:get_path(),
  Mod = list_to_atom(filename:basename(File, ".beam")),
  Dir = filename:dirname(File),
  case code:add_patha(Dir) of
    true ->            
      Opts = if AnalType =:= old_style -> [];
		true -> [no_copt]
	     end,
      Res = 
	case dialyzer_utils:get_abstract_code_from_beam(File) of
	  error ->	  
	    case AnalType of
	      dataflow -> 
		{error, "  Could not get abstract code for "++File++
		 "\n  Use option --old_style or recompile with"
		 " +debug_info (preferred)."};
	      plt_build ->
		{error, "  Could not get abstract code for "++File};
	      old_style ->
		case (catch hipe:c(Mod, ?HIPE_COMPILE_OPTS)) of
		  {'EXIT', Why} -> {error, io_lib:format("~p", [Why])};
		  {error, Why} -> {error, io_lib:format("~p", [Why])};
		  {ok, Icode} ->
		    CS1 = dialyzer_codeserver:insert(Icode, icode, CServer),
		    Exp = beam_get_exports(File),
		    CS2 = dialyzer_codeserver:insert_exports(Exp, CS1),
		    NewCG = dialyzer_callgraph:scan_icode(Icode, Callgraph),
		    NoWarn = beam_get_nowarn(File),
		    {ok, NewCG, NoWarn, CS2}
		end
	    end;
	  AbstrCode ->
	    NoWarn = abs_get_nowarn(AbstrCode, Mod),
	    case dialyzer_utils:get_core_from_abstract_code(AbstrCode, Opts) of
	      error -> {error, "  Could not get core for "++File};
	      Core ->
		case dialyzer_utils:get_record_info(AbstrCode) of
		  {error, _} = Error -> Error;
		  {ok, RecInfo} ->
		    CServer1 = 
		      dialyzer_codeserver:store_records(Mod, RecInfo, CServer),
		    compile_core(Mod, Core, NoWarn, Callgraph, 
				 CServer1, AnalType, Plt)
		end
	    end
	end,
      true = code:set_path(OldPath),
      Res;
    false ->
      {error, "  Could not add path: "++Dir}
  end.

compile_core(Mod, Core, NoWarn, Callgraph, CServer, AnalType, Plt) ->
  Exp = core_get_exports(Core),
  CServer1 = dialyzer_codeserver:insert_exports(Exp, CServer),
  {LabeledCore, CServer2} = label_core(Core, CServer1),
  if AnalType =:= old_style -> 
      compile_core_old(Mod, LabeledCore, NoWarn, Callgraph, CServer2, 
		       AnalType, Plt);
     true -> 
      store_code_and_build_callgraph(Mod, LabeledCore, none, Callgraph, 
				     CServer2, AnalType, NoWarn)
  end.

compile_core_old(Mod, LabeledCore, NoWarn, Callgraph, CServer, AnalType, Plt) ->
  try 
    AnnCore = dialyzer_dataflow:annotate_module(LabeledCore, Plt),
    TransCore = cerl:to_records(AnnCore),
    case hipe:compile_core(Mod, TransCore, [], ?HIPE_COMPILE_OPTS) of
      {error, Why} -> {error, io_lib:format("~p", [Why])};
      {ok, Icode} ->
	store_code_and_build_callgraph(Mod, TransCore, Icode, Callgraph, 
				       CServer, AnalType, NoWarn)
    end
  catch
    _:What -> 
      {error, io_lib:format("~p", [{What, erlang:get_stacktrace()}])}
  end.

  
abs_get_nowarn(Abs, M) ->
  [{M, F, A} 
   || {attribute, _, compile, {nowarn_unused_function, {F, A}}} <- Abs].

beam_get_exports(File) ->
  case beam_lib:chunks(File, [exports]) of
    {ok,{_,[{exports, List}]}} ->
      M = list_to_atom(filename:basename(File, ".beam")),
      [{M, F, A} || {F, A} <- List];
    error ->
      []
  end.

beam_get_nowarn(File) ->
  case beam_lib:chunks(File, [compile_info]) of
    {ok,{_,[{compile_info, List}]}} ->
      M = list_to_atom(filename:basename(File, ".beam")),
      [{M, F, A} || {nowarn_unused_function, {F, A}} <- List];
    error ->
      []
  end.

core_get_exports(Core) ->
  Tree = cerl:from_records(Core),
  Exports1 = cerl:module_exports(Tree),  
  Exports2 = [cerl:var_name(V) || V <- Exports1],
  M = cerl:atom_val(cerl:module_name(Tree)),
  [{M, F, A} || {F, A} <- Exports2].

label_core(Core, CServer) ->
  NextLabel = dialyzer_codeserver:next_core_label(CServer),
  CoreTree = cerl:from_records(Core),
  {LabeledTree, NewNextLabel} = cerl_trees:label(CoreTree, NextLabel),
  {cerl:to_records(LabeledTree), 
   dialyzer_codeserver:update_next_core_label(NewNextLabel, CServer)}.

store_code_and_build_callgraph(Mod, Core, Icode, Callgraph, CServer, 
			       AnalType, NoWarn) ->
  if AnalType =:= old_style ->
      %% When building the callgraph from core that is not lambda
      %% lifted, we lose the lifted functions. We solve this for now
      %% by scanning the icode instead of the core code. I can't wait
      %% to get rid of the icode.
      CServer1 = dialyzer_codeserver:insert(Icode, icode, CServer),
      NewCallgraph = dialyzer_callgraph:scan_icode(Icode, Callgraph),
      {ok, NewCallgraph, NoWarn, CServer1};
     true ->
      CoreTree = cerl:from_records(Core),
      NewCallgraph = dialyzer_callgraph:scan_core_tree(CoreTree, Callgraph),
      CServer2 = dialyzer_codeserver:insert([{Mod, CoreTree}], core, CServer),
      {ok, NewCallgraph, NoWarn, CServer2}
  end.

%%____________________________________________________________
%%
%% Utilities
%%

expand_files(Analysis) ->
  Files = Analysis#analysis.files,
  Ext = 
    case Analysis#analysis.start_from of
      byte_code -> ".beam";
      src_code -> ".erl"
    end,
  case expand_files(Files, Ext, []) of
    [] ->
      exit({error, "No files to analyze. Check analysis type."});
    NewFiles ->
      Analysis#analysis{files=NewFiles}
  end.

expand_files([File|Left], Ext, Acc) ->
  case filelib:is_dir(File) of
    true ->
      {ok, List} = file:list_dir(File),
      NewFiles = [filename:join(File, X)
		  || X <- List, filename:extension(X) =:= Ext],
      expand_files(Left, Ext, NewFiles++Acc);
    false ->
      expand_files(Left, Ext, [File|Acc])
  end;
expand_files([], _Ext, Acc) ->
  ordsets:from_list(Acc).

default_includes(Dir) ->
  L1 = ["..", "../incl", "../inc", "../include"],
  [{i, filename:join(Dir, X)}||X<-L1].
  
%%____________________________________________________________
%%
%% Handle Messages
%%

send_log(Parent, Msg) ->
  Parent ! {self(), log, Msg}.

send_warnings(_Parent, []) ->
  ok;
send_warnings(Parent, Warnings) ->
  Parent ! {self(), warnings, Warnings}.

filter_warnings(LegalWarnings, Warnings) ->
  [Warning || {Tag, Warning} <- Warnings, lists:member(Tag, LegalWarnings)].

send_analysis_done(Parent) ->
  Parent ! {self(), done}.

send_error(Parent, Msg) ->
  Parent ! {self(), error, Msg}.

send_scan_fail(_Parent, []) ->
  ok;
send_scan_fail(Parent, [{FailFile, Reason}|Left]) ->
  Msg = io_lib:format("Error scanning file: ~p\n~s\n", 
		      [FailFile, Reason]),
  send_error(Parent, Msg),
  send_scan_fail(Parent, Left).
  
send_ext_calls(Parent, ExtCalls) ->
  Parent ! {self(), ext_calls, ExtCalls}.

send_bad_calls(Parent, BadCalls, old_style, _CodeServer) ->
  Warnings = 
    [{?WARN_CALLGRAPH, 
      {From, io_lib:format("Call to missing or unexported function ~w\n", 
			   [To])}}
     || {From, {_,F,A} = To} <- BadCalls,
	not(F =:= module_info andalso (A =:= 0 orelse A =:= 1))],
  send_warnings(Parent, Warnings);
send_bad_calls(Parent, BadCalls, _AnalType, CodeServer) ->
  send_warnings(Parent, format_bad_calls(BadCalls, CodeServer, [])).



format_bad_calls([{{_, _, _}, {_, module_info, A}}|Left], CodeServer, Acc) 
  when A =:= 0; A =:= 1 ->
  format_bad_calls(Left, CodeServer, Acc);
format_bad_calls([{From, To}|Left], 
		 CodeServer, Acc) ->
  {ok, Tree} = dialyzer_codeserver:lookup(From, core, CodeServer),
  Msg = io_lib:format("Call to missing or unexported function ~w\n", 
		      [To]),
  FileLine = find_call_file_and_line(Tree, To),
  NewAcc = [{?WARN_CALLGRAPH, {FileLine, Msg}}|Acc],
  format_bad_calls(Left, CodeServer, NewAcc);
format_bad_calls([], _CodeServer, Acc) ->
  Acc.

find_call_file_and_line({_Var, Tree}, MFA) ->
  Fun = 
    fun(SubTree, Acc) ->
	case cerl:is_c_call(SubTree) of
	  true ->
	    M = cerl:call_module(SubTree),
	    F = cerl:call_name(SubTree),
	    A = cerl:call_arity(SubTree),
	    case cerl:is_c_atom(M) andalso cerl:is_c_atom(F) of
	      true ->
		case {cerl:concrete(M), cerl:concrete(F), A} of
		  MFA ->
		    Ann = cerl:get_ann(SubTree),
		    [{get_file(Ann), get_line(Ann)}|Acc];
		  _ -> Acc
		end;
	      false -> Acc
	    end;
	  false -> Acc
	end
    end,
  hd(cerl_trees:fold(Fun, [], Tree)).

get_line([Line|_]) when is_integer(Line) -> Line;
get_line([_|Tail]) -> get_line(Tail);
get_line([]) -> -1.

get_file([{file, File}|_]) -> File;
get_file([_|Tail]) -> get_file(Tail).

%%____________________________________________________________
%%
%% Handle the PLT
%%

init_plt(#analysis{init_plt=InitPlt, user_plt=Plt, plt_info=Info}) ->
  dialyzer_plt:copy(InitPlt, Plt),
  case Info of
    none -> ok;
    {MD5, Libs} -> 
      dialyzer_plt:insert(Plt, {md5, MD5}),
      dialyzer_plt:insert(Plt, {libs, Libs}),
      ok
  end.