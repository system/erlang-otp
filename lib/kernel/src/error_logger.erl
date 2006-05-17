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
-module(error_logger).

-export([start/0,start_link/0,format/2,error_msg/1,error_msg/2,error_report/1,
	 error_report/2,info_report/1,info_report/2,warning_report/1,
	 warning_report/2,error_info/1,
	 info_msg/1,info_msg/2,warning_msg/1,warning_msg/2, 
	 logfile/1,tty/1,swap_handler/1,
	 simple_logger/0,simple_logger/1,add_report_handler/1,
	 add_report_handler/2,delete_report_handler/1]).

-export([init/1,
	 handle_event/2, handle_call/2, handle_info/2,
	 terminate/2]).

-define(buffer_size, 10).

start() ->
    case gen_event:start({local, error_logger}) of
	{ok, Pid} ->
	    simple_logger(?buffer_size),
	    {ok, Pid};
	Error -> Error
    end.

start_link() ->
    case gen_event:start_link({local, error_logger}) of
	{ok, Pid} ->
	    simple_logger(?buffer_size),
	    {ok, Pid};
	Error -> Error
    end.

%%-----------------------------------------------------------------
%% These two simple old functions generate events tagged 'error'
%% Used for simple messages; error or information.
%%-----------------------------------------------------------------
error_msg(Format) ->
    error_msg(Format,[]).
error_msg(Format, Args) ->
    notify({error, group_leader(), {self(), Format, Args}}).

format(Format, Args) ->
    notify({error, group_leader(), {self(), Format, Args}}).

%%-----------------------------------------------------------------
%% This functions should be used for error reports.  Events
%% are tagged 'error_report'.
%% The 'std_error' error_report type can always be used.
%%-----------------------------------------------------------------
error_report(Report) -> error_report(std_error, Report).
error_report(Type, Report) ->
    notify({error_report, group_leader(), {self(), Type, Report}}).

%%-----------------------------------------------------------------
%% This function should be used for warning reports.  
%% These might be mapped to error reports or info reports, 
%% depending on emulator flags. Events that ore not mapped
%% are tagged 'info_report'.
%% The 'std_warning' info_report type can always be used and is 
%% mapped to std_info or std_error accordingly.
%%-----------------------------------------------------------------
warning_report(Report) -> warning_report(std_warning, Report).
warning_report(Type, Report) ->
    {Tag, NType} = case  (catch error_logger:warning_map()) of
		       info ->
			   if 
			       Type =:= std_warning ->
				   {info_report,std_info};
			       true ->
				   {info_report,Type}
			   end;
		       warning ->
			   {warning_report,Type};
		       _Else ->
			   if
			       Type =:= std_warning ->
				   {error_report, std_error};
			       true ->
				   {error_report, Type}
			   end
		   end,
			   
    notify({Tag, group_leader(), {self(), NType, Report}}).

%%-----------------------------------------------------------------
%% This function provides similar functions as error_msg for
%% warning messages, like warning report it might get mapped to
%% other types of reports.
%%-----------------------------------------------------------------
warning_msg(Format) ->
    warning_msg(Format,[]).
warning_msg(Format, Args) ->
    Tag = case (catch error_logger:warning_map()) of
	      warning ->
		  warning_msg;
	      info ->
		  info_msg;
	      _Else ->
		  error
	  end,
    notify({Tag, group_leader(), {self(), Format, Args}}).

%%-----------------------------------------------------------------
%% This function should be used for information reports.  Events
%% are tagged 'info_report'.
%% The 'std_info' info_report type can always be used.
%%-----------------------------------------------------------------
info_report(Report) -> info_report(std_info, Report).
info_report(Type, Report) ->
    notify({info_report, group_leader(), {self(), Type, Report}}).

%%-----------------------------------------------------------------
%% This function provides similar functions as error_msg for
%% information messages.
%%-----------------------------------------------------------------
info_msg(Format) ->
    info_msg(Format,[]).
info_msg(Format, Args) ->
    notify({info_msg, group_leader(), {self(), Format, Args}}).

%%-----------------------------------------------------------------
%% Used by the init process.  Events are tagged 'info'.
%%-----------------------------------------------------------------
error_info(Error) ->
    notify({info, group_leader(), {self(), Error, []}}).

notify(Msg) ->
    gen_event:notify(error_logger, Msg).

swap_handler({logfile, File}) ->
    gen_event:swap_handler(error_logger, {error_logger, swap},
			   {error_logger_file_h, File}),
    simple_logger();
swap_handler(tty) ->
    gen_event:swap_handler(error_logger, {error_logger, swap},
			   {error_logger_tty_h, []}),
    simple_logger().

add_report_handler(Module) when is_atom(Module) ->
    gen_event:add_handler(error_logger, Module, []).

add_report_handler(Module, Args) when is_atom(Module) ->
    gen_event:add_handler(error_logger, Module, Args).

delete_report_handler(Module) when is_atom(Module) ->
    gen_event:delete_handler(error_logger, Module, []).

%% Start the lowest level error_logger handler with Buffer.
simple_logger(Buffer_size) when is_integer(Buffer_size) ->
    gen_event:add_handler(error_logger, error_logger, Buffer_size).

%% Start the lowest level error_logger handler without Buffer.
simple_logger() -> 
    gen_event:add_handler(error_logger, error_logger, []).

%% Log all errors to File for all eternity
logfile({open, File}) ->
    case lists:member(error_logger_file_h,
		      gen_event:which_handlers(error_logger)) of
	true ->
	    {error, allready_have_logfile};
	_ ->
	    gen_event:add_handler(error_logger, error_logger_file_h, File)
    end;
logfile(close) ->
    case gen_event:delete_handler(error_logger, error_logger_file_h, normal) of
	{error,Reason} ->
	    {error,Reason};
	_ ->
	    ok
    end;
logfile(filename) ->
    case gen_event:call(error_logger, error_logger_file_h, filename) of
	{error,_} ->
	    {error, no_log_file};
	Val ->
	    Val
    end.

%% Possibly turn off all tty printouts, maybe we only want the errors
%% to go to a file
%% Flag = true | false

tty(true) ->
    gen_event:add_handler(error_logger, error_logger_tty_h, []),
    ok;
tty(false) ->
    gen_event:delete_handler(error_logger, error_logger_tty_h, []),
    ok.


%%% ---------------------------------------------------
%%% This is the default error_logger handler.
%%% ---------------------------------------------------

init(Max) when is_integer(Max) ->
    {ok, {Max, 0, []}};
%% This one is called if someone took over from us, and now wants to
%% go back.
init({go_back, _PostState}) ->  
    {ok, {?buffer_size, 0, []}};
init(_) ->  %% Start and just relay to other
    {ok, []}.             %% node if node(GLeader) /= node().
    
handle_event({Type, GL, Msg}, State) when node(GL) /= node() ->
    gen_event:notify({error_logger, node(GL)},{Type, GL, Msg}),
%    handle_event2({Type, GL, Msg}, State);  %% Shall we do something at this
    {ok, State};                                  %% node too ???
handle_event({info_report, _, {_, Type, _}}, State) when Type /= std_info ->
    {ok, State};   %% Ignore other info reports here
handle_event(Event, State) ->
    handle_event2(Event, State).

handle_info({emulator, GL, Chars}, State) when node(GL) /= node() ->
    {error_logger, node(GL)} ! {emulator, GL, add_node(Chars,self())},
    {ok, State};
handle_info({emulator, GL, Chars}, State) ->
    handle_event2({emulator, GL, Chars}, State);
handle_info(_, State) ->
    {ok, State}.

handle_call(_Query, State) -> {ok, {error, bad_query}, State}.


terminate(swap, {_, 0, Buff}) ->
    {error_logger, Buff};
terminate(swap, {_, Lost, Buff}) ->
    Myevent = {info, group_leader(), {self(), {lost_messages, Lost}, []}},
    {error_logger, [tag_event(Myevent)|Buff]};
terminate(_, _) ->
    {error_logger, []}.


handle_event2(Event, {1, Lost, Buff}) ->
    display(tag_event(Event)),
    {ok, {1, Lost+1, Buff}};
handle_event2(Event, {N, Lost, Buff}) ->
    Tagged = tag_event(Event),
    display(Tagged),
    {ok, {N-1, Lost, [Tagged|Buff]}};
handle_event2(_, State) ->
    {ok, State}.

tag_event(Event) ->    
    {erlang:localtime(), Event}.

display({Tag,{error,_,{_,Format,Args}}}) ->
    display2(Tag,Format,Args);
display({Tag,{error_report,_,{_,Type,Report}}}) ->
    display2(Tag,Type,Report);
display({Tag,{info_report,_,{_,Type,Report}}}) ->
    display2(Tag,Type,Report);
display({Tag,{info,_,{_,Error,_}}}) ->
    display2(Tag,Error,[]);
display({Tag,{info_msg,_,{_,Format,Args}}}) ->
    display2(Tag,Format,Args);
display({Tag,{warning_report,_,{_,Type,Report}}}) ->
    display2(Tag,Type,Report);
display({Tag,{warning_msg,_,{_,Format,Args}}}) ->
    display2(Tag,Format,Args);
display({Tag,{emulator,_,Chars}}) ->
    display2(Tag,Chars,[]).

add_node(X, Pid) when is_atom(X) ->
    add_node(atom_to_list(X), Pid);
add_node(X, Pid) ->
    lists:concat([X,"** at node ",node(Pid)," **~n"]).

%% Can't do io_lib:format

display2(Tag,F,A) ->
    erlang:display({error_logger,Tag,F,A}).
