%%% -*- erlang-indent-level: 2 -*-
%%% $Id$

-module(hipe_amd64_specific_sse2).

-export([number_of_temporaries/1]).

% The following exports are used as M:F(...) calls from other modules;
%% e.g. hipe_amd64_ra_ls.
-export([analyze/1,
         bb/2,
         args/1,
         labels/1,
         livein/2,
         liveout/2,
         succ_map/1,
         uses/1,
         defines/1,
	 def_use/1,
	 is_arg/1,	%% used by hipe_ls_regalloc
	 is_move/1,
	 is_fixed/1,	%% used by hipe_graph_coloring_regalloc
         is_global/1,
	 is_precoloured/1,
         reg_nr/1,
	 non_alloc/1,
	 allocatable/0,
         physical_name/1,
	 all_precoloured/0,
	 new_spill_index/1,	%% used by hipe_ls_regalloc
	 var_range/1,
         breadthorder/1,
         postorder/1,
         reverse_postorder/1]).

%% callbacks for hipe_regalloc_loop
-export([defun_to_cfg/1,
	 check_and_rewrite/2]).

defun_to_cfg(Defun) ->
  hipe_amd64_cfg:init(Defun).

check_and_rewrite(Defun, Coloring) ->
  {NewDefun, _, NewSpillIndex} =
    hipe_amd64_ra_sse2_postconditions:check_and_rewrite(Defun, Coloring, [], []),
  {NewDefun, NewSpillIndex}.

reverse_postorder(CFG) ->
  hipe_amd64_cfg:reverse_postorder(CFG).

breadthorder(CFG) ->
  hipe_amd64_cfg:breadthorder(CFG).

postorder(CFG) ->
  hipe_amd64_cfg:postorder(CFG).

is_global(_Reg) ->
  false.
 
is_fixed(_Reg) ->
  false.

is_arg(_Reg) ->
  false.

args(_CFG) ->
  [].
 
non_alloc(_) ->
  [].

%% Liveness stuff

analyze(CFG) ->
  hipe_amd64_liveness:analyze(CFG).

livein(Liveness,L) ->
  [X || X <- hipe_amd64_liveness:livein(Liveness,L),
 	     hipe_x86:temp_is_allocatable(X),
	     hipe_x86:temp_type(X) == 'double'].

liveout(BB_in_out_liveness,Label) ->
  [X || X <- hipe_amd64_liveness:liveout(BB_in_out_liveness,Label),
 	     hipe_x86:temp_is_allocatable(X),
	     hipe_x86:temp_type(X) == 'double'].

%% Registers stuff

allocatable() ->
  hipe_amd64_registers:allocatable_sse2().

all_precoloured() ->
  allocatable().

is_precoloured(Reg) ->
  lists:member(Reg,all_precoloured()).

physical_name(Reg) ->
  Reg.

%% CFG stuff

succ_map(CFG) ->
  hipe_amd64_cfg:succ_map(CFG).

labels(CFG) ->
  hipe_amd64_cfg:labels(CFG).

var_range(_CFG) ->
  hipe_gensym:var_range(x86).

number_of_temporaries(_CFG) ->
  Highest_temporary = hipe_gensym:get_var(x86),
  %% Since we can have temps from 0 to Max adjust by +1.
  Highest_temporary + 1.

bb(CFG,L) ->
  hipe_amd64_cfg:bb(CFG,L).

%% AMD64 stuff

def_use(Instruction) ->
  {[X || X <- hipe_amd64_defuse:insn_def(Instruction), 
 	   hipe_x86:temp_is_allocatable(X),
 	   hipe_x86:temp_type(X) == 'double'],
   [X || X <- hipe_amd64_defuse:insn_use(Instruction), 
 	   hipe_x86:temp_is_allocatable(X),
	   hipe_x86:temp_type(X) == 'double']
  }.

uses(I) ->
  [X || X <- hipe_amd64_defuse:insn_use(I),
 	     hipe_x86:temp_is_allocatable(X),
 	     hipe_x86:temp_type(X) == 'double'].

defines(I) ->
  [X || X <- hipe_amd64_defuse:insn_def(I),
	     hipe_x86:temp_is_allocatable(X),
	     hipe_x86:temp_type(X) == 'double'].

is_move(Instruction) ->
  case hipe_x86:is_fmove(Instruction) of
    true ->
      Src = hipe_x86:fmove_src(Instruction),
      Dst = hipe_x86:fmove_dst(Instruction),
      case hipe_x86:is_temp(Src) of
 	true ->
 	  case hipe_x86:temp_is_allocatable(Src) of
 	    true ->
 	      case hipe_x86:is_temp(Dst) of
 		true ->
 		  hipe_x86:temp_is_allocatable(Dst);
 		false -> false
 	      end;
 	    false -> false
 	  end;
 	false -> false
      end;
    false -> false
  end.
 
reg_nr(Reg) ->
  hipe_x86:temp_reg(Reg).

new_spill_index(SpillIndex)->
  SpillIndex+1.