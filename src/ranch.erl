%% Copyright (c) 2011-2014, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(ranch).

-export([start_listener/6]).
-export([stop_listener/1]).
-export([child_spec/6]).
-export([accept_ack/1]).
-export([remove_connection/1]).
-export([get_port/1]).
-export([get_max_connections/1]).
-export([set_max_connections/2]).
-export([get_protocol_options/1]).
-export([set_protocol_options/2]).
-export([filter_options/3]).
-export([set_option_default/3]).
-export([require/1]).

% --------------------------------------------------------------------------
% copied from ranch2
% --------------------------------------------------------------------------
-export([info/0]).
-export([info/1]).
-export([procs/2]).
-export([get_status/1]).
-export([get_addr/1]).
% --------------------------------------------------------------------------


-type max_conns() :: non_neg_integer() | infinity.
-export_type([max_conns/0]).

-type ref() :: any().
-export_type([ref/0]).

-spec start_listener(ref(), non_neg_integer(), module(), any(), module(), any())
	-> {ok, pid()} | {error, badarg}.
start_listener(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts)
		when is_integer(NbAcceptors) andalso is_atom(Transport)
		andalso is_atom(Protocol) ->
	_ = code:ensure_loaded(Transport),
	case erlang:function_exported(Transport, name, 0) of
		false ->
			{error, badarg};
		true ->
            supervisor:start_child(ranch_sup, child_spec(Ref, NbAcceptors,
			    Transport, TransOpts, Protocol, ProtoOpts))
	end.

-spec stop_listener(ref()) -> ok | {error, not_found}.
stop_listener(Ref) ->
	case supervisor:terminate_child(ranch_sup, {ranch_listener_sup, Ref}) of
		ok ->
			_ = supervisor:delete_child(ranch_sup, {ranch_listener_sup, Ref}),
			ranch_server:cleanup_listener_opts(Ref);
		{error, Reason} ->
			{error, Reason}
	end.

-spec child_spec(ref(), non_neg_integer(), module(), any(), module(), any())
	-> supervisor:child_spec().
child_spec(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts)
		when is_integer(NbAcceptors) andalso is_atom(Transport)
		andalso is_atom(Protocol) ->
	{{ranch_listener_sup, Ref}, {ranch_listener_sup, start_link, [
		Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts
	]}, permanent, infinity, supervisor, [ranch_listener_sup]}.

-spec accept_ack(ref()) -> ok.
accept_ack(Ref) ->
	receive {shoot, Ref, Transport, Socket, AckTimeout} ->
		Transport:accept_ack(Socket, AckTimeout)
	end.

-spec remove_connection(ref()) -> ok.
remove_connection(Ref) ->
	ConnsSup = ranch_server:get_connections_sup(Ref),
	ConnsSup ! {remove_connection, Ref},
	ok.

-spec get_max_connections(ref()) -> max_conns().
get_max_connections(Ref) ->
	ranch_server:get_max_connections(Ref).

-spec set_max_connections(ref(), max_conns()) -> ok.
set_max_connections(Ref, MaxConnections) ->
	ranch_server:set_max_connections(Ref, MaxConnections).

-spec get_protocol_options(ref()) -> any().
get_protocol_options(Ref) ->
	ranch_server:get_protocol_options(Ref).

-spec set_protocol_options(ref(), any()) -> ok.
set_protocol_options(Ref, Opts) ->
	ranch_server:set_protocol_options(Ref, Opts).

-spec filter_options([{atom(), any()} | {raw, any(), any(), any()}],
	[atom()], Acc) -> Acc when Acc :: [any()].
filter_options(UserOptions, AllowedKeys, DefaultOptions) ->
	AllowedOptions = filter_user_options(UserOptions, AllowedKeys),
	lists:foldl(fun merge_options/2, DefaultOptions, AllowedOptions).

filter_user_options([Opt = {Key, _}|Tail], AllowedKeys) ->
	case lists:member(Key, AllowedKeys) of
		true -> [Opt|filter_user_options(Tail, AllowedKeys)];
		false -> filter_user_options(Tail, AllowedKeys)
	end;
filter_user_options([Opt = {raw, _, _, _}|Tail], AllowedKeys) ->
	case lists:member(raw, AllowedKeys) of
		true -> [Opt|filter_user_options(Tail, AllowedKeys)];
		false -> filter_user_options(Tail, AllowedKeys)
	end;
filter_user_options([], _) ->
	[].

merge_options({Key, _} = Option, OptionList) ->
	lists:keystore(Key, 1, OptionList, Option);
merge_options(Option, OptionList) ->
	[Option|OptionList].

-spec set_option_default(Opts, atom(), any())
	-> Opts when Opts :: [{atom(), any()}].
set_option_default(Opts, Key, Value) ->
	case lists:keymember(Key, 1, Opts) of
		true -> Opts;
		false -> [{Key, Value}|Opts]
	end.

-spec require([atom()]) -> ok.
require([]) ->
	ok;
require([App|Tail]) ->
	case application:start(App) of
		ok -> ok;
		{error, {already_started, App}} -> ok
	end,
	require(Tail).


% --------------------------------------------------------------------------
% copied from ranch2
% --------------------------------------------------------------------------

-spec info() -> #{ref() := #{atom() := term()}}.
info() ->
	% {?MODULE, ?FUNCTION_NAME}.
	lists:foldl(
		fun ({Ref, Pid}, Acc) ->
			Acc#{Ref => listener_info(Ref, Pid)}
		end,
		#{},
		ranch_server:get_listener_sups()
	).

-spec info(ref()) -> #{atom() := term()}.
info(Ref) ->
	Pid = ranch_server:get_listener_sup(Ref),
	listener_info(Ref, Pid).

listener_info(Ref, Pid) ->
	[_, Transport, _, _, Protocol, _] = ranch_server:get_listener_start_args(Ref),
	Status = get_status(Ref),
	{IP, Port} = case get_addr(Ref) of
		Addr = {local, _} ->
			{Addr, undefined};
		Addr ->
			Addr
	end,
	MaxConns = get_max_connections(Ref),
	TransOpts = ranch_server:get_transport_options(Ref),
	ProtoOpts = get_protocol_options(Ref),
	#{
		pid => Pid,
		status => Status,
		ip => IP,
		port => Port,
		max_connections => MaxConns,
		active_connections => get_connections(Ref, active),
		all_connections => get_connections(Ref, all),
		transport => Transport,
		transport_options => TransOpts,
		protocol => Protocol,
		protocol_options => ProtoOpts,
		metrics => metrics(Ref)
	}.

-spec procs(ref(), acceptors | connections) -> [pid()].
procs(Ref, Type) ->
	ListenerSup = ranch_server:get_listener_sup(Ref),
	procs1(ListenerSup, Type).

procs1(ListenerSup, acceptors) ->
	{_, SupPid, _, _} = lists:keyfind(ranch_acceptors_sup, 1,
		supervisor:which_children(ListenerSup)),
	try
		[Pid || {_, Pid, _, _} <- supervisor:which_children(SupPid)]
	catch exit:{noproc, _} ->
		[]
	end;
procs1(ListenerSup, connections) ->
	{_, SupSupPid, _, _} = lists:keyfind(ranch_conns_sup_sup, 1,
		supervisor:which_children(ListenerSup)),
	Conns=
	lists:map(fun ({_, SupPid, _, _}) ->
			[Pid || {_, Pid, _, _} <- supervisor:which_children(SupPid)]
		end,
		supervisor:which_children(SupSupPid)
	),
	lists:flatten(Conns).

-spec metrics(ref()) -> #{}.
metrics(Ref) ->
	#{}.
	% Counters = ranch_server:get_stats_counters(Ref),
	% CounterInfo = counters:info(Counters),
	% NumCounters = maps:get(size, CounterInfo),
	% NumConnsSups = NumCounters div 2,
	% lists:foldl(
	% 	fun (Id, Acc) ->
	% 		Acc#{
	% 			{conns_sup, Id, accept} => counters:get(Counters, 2*Id-1),
	% 			{conns_sup, Id, terminate} => counters:get(Counters, 2*Id)
	% 		}
	% 	end,
	% 	#{},
	% 	lists:seq(1, NumConnsSups)
	% ).

-spec get_status(ref()) -> running | suspended.
get_status(Ref) ->
	ListenerSup = ranch_server:get_listener_sup(Ref),
	Children = supervisor:which_children(ListenerSup),
	case lists:keyfind(ranch_acceptors_sup, 1, Children) of
		{_, undefined, _, _} ->
			suspended;
		_ ->
			running
	end.

-spec get_addr(ref()) -> {inet:ip_address(), inet:port_number()} |
	{local, binary()} | {undefined, undefined}.
get_addr(Ref) ->
	ranch_server:get_addr(Ref).

-spec get_port(ref()) -> inet:port_number() | undefined.
get_port(Ref) ->
	case get_addr(Ref) of
		{local, _} ->
			undefined;
		{_, Port} ->
			Port
	end.

-spec get_connections(ref(), active|all) -> non_neg_integer().
get_connections(Ref, active) ->
	SupCounts = [ranch_conns_sup:active_connections(ConnsSup) ||
		{_, ConnsSup} <- ranch_server:get_connections_sups(Ref)],
	lists:sum(SupCounts);
get_connections(Ref, all) ->
	SupCounts = [proplists:get_value(active, supervisor:count_children(ConnsSup)) ||
		{_, ConnsSup} <- ranch_server:get_connections_sups(Ref)],
	lists:sum(SupCounts).

% --------------------------------------------------------------------------
% curl -i http://localhost:8080
% 
% ets:tab2list(ranch_server).
% ranch_server:info(acceptors,http).
% ranch_server:info(connections,http).
% ranch:info().
%  io:format("~p~n",[ranch_server:info(connections)]).
% lists:sort(fun(X, Y) -> element(2, element(2, X)) > element(2, element(2, Y)) end, [ C || C <- ranch_server:info(connections), is_tuple(element(2, C))]).
% lists:map(fun(X) -> element(2, element(2, X))  end, [ C || C <- ranch_server:info(connections), is_tuple(element(2, C))]).
% 
% begin f(L), L = lists:map(fun(X) -> element(2, element(2, X))  end, [ C || C <- ranch_server:info(connections), is_tuple(element(2, C))]), 
% 	{lists:sum(L) /length(L), lists:max(L), lists:min(L)} end.
% MEDIAN = fun(Lst) ->
%     S = lists:sort(Lst),
%     L = length(S),
%     M = L div 2,
%     case L rem 2 of
%         1 -> lists:nth(M+1, S);
%         0 -> (lists:nth(M, S) + lists:nth(M+1, S))/2
%     end
% end.
% QINFO = fun() -> LQ = lists:map(fun(X) -> element(2, element(2, X))  end, [ C || C <- ranch_server:info(connections), is_tuple(element(2, C))]), 
% 	{lists:sum(LQ) /length(LQ), MEDIAN(LQ), lists:max(LQ), lists:min(LQ)} end.
% ranch_server:get_queue_stat(acceptors, http).

% [{inet:peername(S),inet:socknames(S), inet:getstat(S)} || S <- gen_tcp_socket:which_sockets()].
% --------------------------------------------------------------------------
