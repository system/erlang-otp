%%<copyright>
%% <year>1998-2008</year>
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
-module(mod_auth_dets).

%% dets authentication storage

-export([get_user/2,
	 list_group_members/2,
	 add_user/2,
	 add_group_member/3,
	 list_users/1,
	 delete_user/2,
	 list_groups/1,
	 delete_group_member/3,
	 delete_group/2,
	 remove/1]).

-export([store_directory_data/2]).

-include("httpd.hrl").
-include("mod_auth.hrl").

store_directory_data(_Directory, DirData) ->
    ?CDEBUG("store_directory_data -> ~n"
	    "     Directory: ~p~n"
	    "     DirData:   ~p",
	    [_Directory, DirData]),

    PWFile = proplists:get_value(auth_user_file, DirData),
    GroupFile = proplists:get_value(auth_group_file, DirData),
    Addr = proplists:get_value(bind_address, DirData),
    Port = proplists:get_value(port, DirData),

    PWName  = httpd_util:make_name("httpd_dets_pwdb",Addr,Port),
    case dets:open_file(PWName,[{type,set},{file,PWFile},{repair,true}]) of
	{ok, PWDB} ->
	    GDBName = httpd_util:make_name("httpd_dets_groupdb",Addr,Port),
	    case dets:open_file(GDBName,[{type,set},{file,GroupFile},{repair,true}]) of
		{ok, GDB} ->
		    NDD1 = lists:keyreplace(auth_user_file, 1, DirData, 
					    {auth_user_file, PWDB}),
		    NDD2 = lists:keyreplace(auth_group_file, 1, NDD1, 
					    {auth_group_file, GDB}),
		    {ok, NDD2};
		{error, Err}->
		    {error, {{file, GroupFile},Err}}
	    end;
	{error, Err2} ->
	    {error, {{file, PWFile},Err2}} 
    end.

%%
%% Storage format of users in the dets table:
%% {{UserName, Addr, Port, Dir}, Password, UserData}
%%

add_user(DirData, UStruct) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    PWDB = proplists:get_value(auth_user_file, DirData),
    Record = {{UStruct#httpd_user.username, Addr, Port, Dir},
	      UStruct#httpd_user.password, UStruct#httpd_user.user_data}, 
    case dets:lookup(PWDB, UStruct#httpd_user.username) of
	[Record] ->
	    {error, user_already_in_db};
	_ ->
	    dets:insert(PWDB, Record),
	    true
    end.

get_user(DirData, UserName) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    PWDB = proplists:get_value(auth_user_file, DirData),
    User = {UserName, Addr, Port, Dir},
    case dets:lookup(PWDB, User) of
	[{User, Password, UserData}] ->
	    {ok, #httpd_user{username=UserName, password=Password, user_data=UserData}};
	_ ->
	    {error, no_such_user}
    end.

list_users(DirData) ->
    ?DEBUG("list_users -> ~n"
	   "     DirData: ~p", [DirData]),
    {Addr, Port, Dir} = lookup_common(DirData),
    PWDB = proplists:get_value(auth_user_file, DirData),
    case dets:traverse(PWDB, fun(X) -> {continue, X} end) of    %% SOOOO Ugly !
	Records when list(Records) ->
	    ?DEBUG("list_users -> ~n"
		   "     Records: ~p", [Records]),
	    {ok, [UserName || {{UserName, AnyAddr, AnyPort, AnyDir}, 
			       _Password, _Data} <- Records,
			      AnyAddr == Addr, AnyPort == Port, 
			      AnyDir == Dir]};
	_O ->
	    ?DEBUG("list_users -> ~n"
		   "     O: ~p", [_O]),
	    {ok, []}
    end.

delete_user(DirData, UserName) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    PWDB = proplists:get_value(auth_user_file, DirData),
    User = {UserName, Addr, Port, Dir},
    case dets:lookup(PWDB, User) of
	[{User, _SomePassword, _UserData}] ->
	    dets:delete(PWDB, User),
	    {ok, Groups} = list_groups(DirData),
	    lists:foreach(fun(Group) -> 
				  delete_group_member(DirData, 
						      Group, UserName) end, 
			  Groups),
	    true;
	_ ->
	    {error, no_such_user}
    end.

%%
%% Storage of groups in the dets table:
%% {Group, UserList} where UserList is a list of strings.
%%
add_group_member(DirData, GroupName, UserName) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    GDB = proplists:get_value(auth_group_file, DirData),
    Group = {GroupName, Addr, Port, Dir},
    case dets:lookup(GDB, Group) of
	[{Group, Users}] ->
	    case lists:member(UserName, Users) of
		true ->
		    true;
		false ->
		    dets:insert(GDB, {Group, [UserName|Users]}),
		    true
	    end;
	[] ->
	    dets:insert(GDB, {Group, [UserName]}),
	    true;
	Other ->
	    {error, Other}
    end.

list_group_members(DirData, GroupName) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    GDB = proplists:get_value(auth_group_file, DirData),
    Group = {GroupName, Addr, Port, Dir},
    case dets:lookup(GDB, Group) of
	[{Group, Users}] ->
	    {ok, Users};
	_ ->
	    {error, no_such_group}
    end.

list_groups(DirData) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    GDB  = proplists:get_value(auth_group_file, DirData),
    case dets:match(GDB, {'$1', '_'}) of
	[] ->
	    {ok, []};
	List when list(List) ->
	    Groups = lists:flatten(List),
	    {ok, [GroupName || 
		     {GroupName, AnyAddr, AnyPort, AnyDir} <- Groups,
		     AnyAddr == Addr, AnyPort == Port, AnyDir == Dir]};
	_ ->
	    {ok, []}
    end.

delete_group_member(DirData, GroupName, UserName) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    GDB = proplists:get_value(auth_group_file, DirData),
    Group = {GroupName, Addr, Port, Dir},
    case dets:lookup(GDB, GroupName) of
	[{Group, Users}] ->
	    case lists:member(UserName, Users) of
		true ->
		    dets:delete(GDB, Group),
		    dets:insert(GDB, {Group,
				      lists:delete(UserName, Users)}),
		    true;
		false ->
		    {error, no_such_group_member}
	    end;
	_ ->
	    {error, no_such_group}
    end.

delete_group(DirData, GroupName) ->
    {Addr, Port, Dir} = lookup_common(DirData),
    GDB = proplists:get_value(auth_group_file, DirData),
    Group = {GroupName, Addr, Port, Dir},
    case dets:lookup(GDB, Group) of
	[{Group, _Users}] ->
	    dets:delete(GDB, Group),
	    true;
	_ ->
	    {error, no_such_group}
    end.

lookup_common(DirData) ->
    Dir  = proplists:get_value(path, DirData),
    Port = proplists:get_value(port, DirData),
    Addr = proplists:get_value(bind_address, DirData),
    {Addr, Port, Dir}.

%% remove/1
%%
%% Closes dets tables used by this auth mod.
%%
remove(DirData) ->
    PWDB = proplists:get_value(auth_user_file, DirData),
    GDB = proplists:get_value(auth_group_file, DirData),
    dets:close(GDB),
    dets:close(PWDB),
    ok.
