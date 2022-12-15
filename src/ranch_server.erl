%% Copyright (c) 2012-2021, Loïc Hoguin <essen@ninenines.eu>
%% Copyright (c) 2020-2021, Jan Uhlig <juhlig@hnc-agency.org>
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

-module(ranch_server).
-behaviour(gen_server).


%% API.
-export([start_link/0]).
-export([set_new_listener_opts/5]).
-export([cleanup_listener_opts/1]).
-export([cleanup_connections_sups/1]).
-export([set_connections_sup/3]).
-export([get_connections_sup/2]).
-export([get_connections_sups/1]).
-export([get_connections_sups/0]).
-export([set_listener_sup/2]).
-export([get_listener_sup/1]).
-export([get_listener_sups/0]).
-export([set_addr/2]).
-export([get_addr/1]).
-export([set_max_connections/2]).
-export([get_max_connections/1]).
-export([set_stats_counters/2]).
-export([get_stats_counters/1]).
-export([set_transport_options/2]).
-export([get_transport_options/1]).
-export([set_protocol_options/2]).
-export([get_protocol_options/1]).
-export([get_listener_start_args/1]).
-export([count_connections/1]).

% ------------------------------------------------------------------------------------------
% added AR
% ------------------------------------------------------------------------------------------
-export([add_acceptor/3]).
-export([add_connection/3]).
-export([get_acceptors/1]).
-export([get_connections/1]).
-export([info/0, info/1, info/2]).
-export([get_queue_lengths/1, get_queue_lengths/2]).
-export([get_queue_stat/1, get_queue_stat/2, lengths_stat/1]).
% ------------------------------------------------------------------------------------------

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

% ------------------------------------------------------------------------------------------
% from ranch1
% ------------------------------------------------------------------------------------------
-export([set_port/2]).
-export([get_port/1]).
% ------------------------------------------------------------------------------------------

-define(TAB, ?MODULE).

-type monitors() :: [{{reference(), pid()}, any()}].
-record(state, {
	monitors = [] :: monitors()
}).

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec set_new_listener_opts(ranch:ref(), ranch:max_conns(), any(), any(), [any()]) -> ok.
set_new_listener_opts(Ref, MaxConns, TransOpts, ProtoOpts, StartArgs) ->
	gen_server:call(?MODULE, {set_new_listener_opts, Ref, MaxConns, TransOpts, ProtoOpts, StartArgs}).

% ------------------------------------------------------------------------------------------
% added AR
% ------------------------------------------------------------------------------------------
-type stat_res() :: tuple().

-define(DEFAULT_REF, rtbgw).

-spec add_acceptor(ranch:ref(), pid(), pid()) -> ok.
add_acceptor(Ref, Pid, Socket) ->
	gen_server:cast(?MODULE, {acceptors, Ref, Pid, Socket}).

-spec add_connection(ranch:ref(), pid(), pid()) -> ok.
add_connection(Ref, Pid, Socket) ->
	gen_server:cast(?MODULE, {connections, Ref, Pid, Socket}).

-spec get_acceptors(ranch:ref()) -> [{pid(), tuple()}].
get_acceptors(Ref) -> get_a_c(acceptors, Ref).

-spec get_connections(ranch:ref()) -> [{pid(), tuple()}].
get_connections(Ref) -> get_a_c(connections, Ref). 

-spec get_a_c(acceptors | connections, ranch:ref()) -> [{pid(), tuple()}].
get_a_c(Type, Ref) -> 
	case ets:match(?TAB, {{Type, Ref}, '$1'}) of
		[] -> [];
		[[A] | _] -> [X || X = {P,_} <- A, is_process_alive(P)]
	end.

-spec get_queue_lengths(acceptors | connections) -> [non_neg_integer()].
% @doc returns processes queque lengths
get_queue_lengths(Type) -> 
	get_queue_lengths(Type, ?DEFAULT_REF).

-spec get_queue_lengths(acceptors | connections, ranch:ref()) -> [non_neg_integer()].
% @doc returns processes queque lengths
get_queue_lengths(Type, Ref) -> 
	[element(2, element(2, X)) || X <-[C || C <- ranch_server:info(Type, Ref), is_tuple(element(2, C))]].

-spec get_queue_stat(acceptors | connections) -> stat_res().
get_queue_stat(Type) -> 
	get_queue_stat(Type, ?DEFAULT_REF).

-spec get_queue_stat(acceptors | connections, ranch:ref()) -> stat_res().
get_queue_stat(Type, Ref) ->
	lengths_stat(get_queue_lengths(Type, Ref)).

-spec lengths_stat([number()]) -> stat_res().
lengths_stat([]) ->
	{0, 0.0, 0, 0, 0};
lengths_stat(Lst) ->
	Len = length(Lst),
	Mean = lists:sum(Lst) / Len,
	Median = ranch_utils:median(Lst),
	{Len, Mean, Median, lists:max(Lst), lists:min(Lst)}.


% -spec info() -> [{
% 	{ok, {ip_address(), port_number()} | returned_non_ip_address()} | {error, posix()},
% 	{ok, {ip_address(), port_number()} | returned_non_ip_address()} | {error, posix()},
% 	{ok, OptionValues} | {error, posix()}
% 	]}.
info() -> 
	[	{
		inet:peername(Socket),
		inet:socknames(Socket),
		inet:getstat(Socket)
	}  || Socket <- gen_tcp_socket:which_sockets()].

% -spec info(acceptors | connections) -> [{
% 	pid(),
% 	{ok, {tuple(), non_neg_integer()},}
% 	{ok, {tuple(), non_neg_integer()},}
% 	{ok, {ip_address(), port_number()} | returned_non_ip_address()} | {error, posix()},
% 	{ok, {ip_address(), port_number()} | returned_non_ip_address()} | {error, posix()},
% 	{ok, OptionValues} | {error, posix()}
% 	]}.
info(Type) -> info(Type, ?DEFAULT_REF).

% -spec info(acceptors | connections, ranch:ref()) -> [{
% 	pid(),
% 	{ok, {tuple(), non_neg_integer()},}
% 	{ok, {tuple(), non_neg_integer()},}
% 	{ok, {ip_address(), port_number()} | returned_non_ip_address()} | {error, posix()},
% 	{ok, {ip_address(), port_number()} | returned_non_ip_address()} | {error, posix()},
% 	{ok, OptionValues} | {error, posix()}
% 	]}.
info(Type, Ref) ->
	% [{Pid, erlang:process_info(Pid, message_queue_len), gen_tcp_socket:peername(Socket), gen_tcp_socket:info(Socket)}  || {Pid, Socket} <- get_a_c(Type, http)].
	[	{Pid, 
		erlang:process_info(Pid, message_queue_len),
		erlang:process_info(Pid, reductions),
		inet:peername(Socket),
		inet:socknames(Socket),
		inet:getstat(Socket)
	}  || {Pid, Socket} <- get_a_c(Type, Ref)].

% ------------------------------------------------------------------------------------------

-spec cleanup_listener_opts(ranch:ref()) -> ok.
cleanup_listener_opts(Ref) ->
	_ = ets:delete(?TAB, {addr, Ref}),
	_ = ets:delete(?TAB, {max_conns, Ref}),
	_ = ets:delete(?TAB, {trans_opts, Ref}),
	_ = ets:delete(?TAB, {proto_opts, Ref}),
	_ = ets:delete(?TAB, {listener_start_args, Ref}),
	%% We also remove the pid of the connection supervisors.
	%% Depending on the timing, they might already have been deleted
	%% when we handled the monitor DOWN message. However, in some
	%% cases when calling stop_listener followed by get_connections_sup,
	%% we could end up with the pid still being returned, when we
	%% expected a crash (because the listener was stopped).
	%% Deleting it explicitly here removes any possible confusion.
	_ = ets:match_delete(?TAB, {{conns_sup, Ref, '_'}, '_'}),
	_ = ets:delete(?TAB, {stats_counters, Ref}),
	%% Ditto for the listener supervisor.
	_ = ets:delete(?TAB, {listener_sup, Ref}),
	ok.

-spec cleanup_connections_sups(ranch:ref()) -> ok.
cleanup_connections_sups(Ref) ->
	_ = ets:match_delete(?TAB, {{conns_sup, Ref, '_'}, '_'}),
	_ = ets:delete(?TAB, {stats_counters, Ref}),
	ok.

-spec set_connections_sup(ranch:ref(), non_neg_integer(), pid()) -> ok.
set_connections_sup(Ref, Id, Pid) ->
	gen_server:call(?MODULE, {set_connections_sup, Ref, Id, Pid}).

-spec get_connections_sup(ranch:ref(), pos_integer()) -> pid().
get_connections_sup(Ref, Id) ->
	ConnsSups = get_connections_sups(Ref),
	NConnsSups = length(ConnsSups),
	{_, Pid} = lists:keyfind((Id rem NConnsSups) + 1, 1, ConnsSups),
	Pid.

-spec get_connections_sups(ranch:ref()) -> [{pos_integer(), pid()}].
get_connections_sups(Ref) ->
	[{Id, Pid} ||
		[Id, Pid] <- ets:match(?TAB, {{conns_sup, Ref, '$1'}, '$2'})].

-spec get_connections_sups() -> [{ranch:ref(), pos_integer(), pid()}].
get_connections_sups() ->
	[{Ref, Id, Pid} ||
		[Ref, Id, Pid] <- ets:match(?TAB, {{conns_sup, '$1', '$2'}, '$3'})].

-spec set_listener_sup(ranch:ref(), pid()) -> ok.
set_listener_sup(Ref, Pid) ->
	gen_server:call(?MODULE, {set_listener_sup, Ref, Pid}).

-spec get_listener_sup(ranch:ref()) -> pid().
get_listener_sup(Ref) ->
	ets:lookup_element(?TAB, {listener_sup, Ref}, 2).

-spec get_listener_sups() -> [{ranch:ref(), pid()}].
get_listener_sups() ->
	[{Ref, Pid} || [Ref, Pid] <- ets:match(?TAB, {{listener_sup, '$1'}, '$2'})].

-spec set_addr(ranch:ref(), {inet:ip_address(), inet:port_number()} |
	{local, binary()} | {undefined, undefined}) -> ok.
set_addr(Ref, Addr) ->
	gen_server:call(?MODULE, {set_addr, Ref, Addr}).

-spec get_addr(ranch:ref()) -> {inet:ip_address(), inet:port_number()} |
	{local, binary()} | {undefined, undefined}.
get_addr(Ref) ->
	ets:lookup_element(?TAB, {addr, Ref}, 2).

-spec set_max_connections(ranch:ref(), ranch:max_conns()) -> ok.
set_max_connections(Ref, MaxConnections) ->
	gen_server:call(?MODULE, {set_max_conns, Ref, MaxConnections}).

-spec get_max_connections(ranch:ref()) -> ranch:max_conns().
get_max_connections(Ref) ->
	ets:lookup_element(?TAB, {max_conns, Ref}, 2).

-spec set_stats_counters(ranch:ref(), counters:counters_ref()) -> ok.
set_stats_counters(Ref, Counters) ->
	gen_server:call(?MODULE, {set_stats_counters, Ref, Counters}).

-spec get_stats_counters(ranch:ref()) -> counters:counters_ref().
get_stats_counters(Ref) ->
	ets:lookup_element(?TAB, {stats_counters, Ref}, 2).

-spec set_transport_options(ranch:ref(), any()) -> ok.
set_transport_options(Ref, TransOpts) ->
	gen_server:call(?MODULE, {set_trans_opts, Ref, TransOpts}).

-spec get_transport_options(ranch:ref()) -> any().
get_transport_options(Ref) ->
	ets:lookup_element(?TAB, {trans_opts, Ref}, 2).

-spec set_protocol_options(ranch:ref(), any()) -> ok.
set_protocol_options(Ref, ProtoOpts) ->
	gen_server:call(?MODULE, {set_proto_opts, Ref, ProtoOpts}).

-spec get_protocol_options(ranch:ref()) -> any().
get_protocol_options(Ref) ->
	ets:lookup_element(?TAB, {proto_opts, Ref}, 2).

-spec get_listener_start_args(ranch:ref()) -> [any()].
get_listener_start_args(Ref) ->
	ets:lookup_element(?TAB, {listener_start_args, Ref}, 2).

-spec count_connections(ranch:ref()) -> non_neg_integer().
count_connections(Ref) ->
	lists:foldl(
		fun ({_, ConnsSup}, Acc) ->
			Acc+ranch_conns_sup:active_connections(ConnsSup)
		end,
		0,
		get_connections_sups(Ref)).


% ------------------------------------------------------------------------------------------
% from ranch1
% ------------------------------------------------------------------------------------------
-spec set_port(ranch:ref(), inet:port_number()) -> ok.
set_port(Ref, Port) ->
	gen_server:call(?MODULE, {set_port, Ref, Port}).

-spec get_port(ranch:ref()) -> inet:port_number().
get_port(Ref) ->
	ets:lookup_element(?TAB, {port, Ref}, 2).

% ------------------------------------------------------------------------------------------

%% gen_server.

-spec init([]) -> {ok, #state{}}.
init([]) ->
	ConnMonitors = [{{erlang:monitor(process, Pid), Pid}, {conns_sup, Ref, Id}} ||
		[Ref, Id, Pid] <- ets:match(?TAB, {{conns_sup, '$1', '$2'}, '$3'})],
	ListenerMonitors = [{{erlang:monitor(process, Pid), Pid}, {listener_sup, Ref}} ||
		[Ref, Pid] <- ets:match(?TAB, {{listener_sup, '$1'}, '$2'})],
	{ok, #state{monitors=ConnMonitors++ListenerMonitors}}.


-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, ok | ignore, #state{}}.
handle_call({set_new_listener_opts, Ref, MaxConns, TransOpts, ProtoOpts, StartArgs}, _, State) ->
	ets:insert_new(?TAB, {{max_conns, Ref}, MaxConns}),
	ets:insert_new(?TAB, {{trans_opts, Ref}, TransOpts}),
	ets:insert_new(?TAB, {{proto_opts, Ref}, ProtoOpts}),
	ets:insert_new(?TAB, {{listener_start_args, Ref}, StartArgs}),
	{reply, ok, State};
handle_call({set_connections_sup, Ref, Id, Pid}, _, State0) ->
	State = set_monitored_process({conns_sup, Ref, Id}, Pid, State0),
	{reply, ok, State};
handle_call({set_listener_sup, Ref, Pid}, _, State0) ->
	State = set_monitored_process({listener_sup, Ref}, Pid, State0),
	{reply, ok, State};
handle_call({set_addr, Ref, Addr}, _, State) ->
	true = ets:insert(?TAB, {{addr, Ref}, Addr}),
	{reply, ok, State};
handle_call({set_max_conns, Ref, MaxConns}, _, State) ->
	ets:insert(?TAB, {{max_conns, Ref}, MaxConns}),
	_ = [ConnsSup ! {set_max_conns, MaxConns} || {_, ConnsSup} <- get_connections_sups(Ref)],
	{reply, ok, State};
handle_call({set_stats_counters, Ref, Counters}, _, State) ->
	ets:insert(?TAB, {{stats_counters, Ref}, Counters}),
	{reply, ok, State};
handle_call({set_trans_opts, Ref, Opts}, _, State) ->
	ets:insert(?TAB, {{trans_opts, Ref}, Opts}),
	{reply, ok, State};
handle_call({set_proto_opts, Ref, Opts}, _, State) ->
	ets:insert(?TAB, {{proto_opts, Ref}, Opts}),
	_ = [ConnsSup ! {set_protocol_options, Opts} || {_, ConnsSup} <- get_connections_sups(Ref)],
	{reply, ok, State};
% ------------------------------------------------------------------------------------------
% from ranch1
% ------------------------------------------------------------------------------------------
handle_call({set_port, Ref, Port}, _, State) ->
	true = ets:insert(?TAB, {{port, Ref}, Port}),
	{reply, ok, State};
% ------------------------------------------------------------------------------------------

handle_call(_Request, _Fom, State) ->
	{reply, ignore, State}.

-spec handle_cast(_, #state{}) -> {noreply, #state{}}.
handle_cast({Type, Ref, Pid, Socket}, State) ->
	Stored = case ets:match(?TAB, {{Type, Ref}, '$1'}) of
		[] -> [];
		[[A] | _] -> [X || X = {P,_} <- A, is_process_alive(P)]
	end,
	true = ets:insert(?TAB, {{Type, Ref}, [{Pid, Socket} | Stored]}),
	{noreply, State};
handle_cast(_Request, State) ->
	{noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info({'DOWN', MonitorRef, process, Pid, Reason},
		State=#state{monitors=Monitors}) ->
	{_, TypeRef} = lists:keyfind({MonitorRef, Pid}, 1, Monitors),
	ok = case {TypeRef, Reason} of
		{{listener_sup, Ref}, normal} ->
			cleanup_listener_opts(Ref);
		{{listener_sup, Ref}, shutdown} ->
			cleanup_listener_opts(Ref);
		{{listener_sup, Ref}, {shutdown, _}} ->
			cleanup_listener_opts(Ref);
		_ ->
			_ = ets:delete(?TAB, TypeRef),
			ok
	end,
	Monitors2 = lists:keydelete({MonitorRef, Pid}, 1, Monitors),
	{noreply, State#state{monitors=Monitors2}};
handle_info(_Info, State) ->
	{noreply, State}.

-spec terminate(_, #state{}) -> ok.
terminate(_Reason, _State) ->
	ok.

-spec code_change(term() | {down, term()}, #state{}, term()) -> {ok, term()}.
code_change({down, _}, State, _Extra) ->
	true = ets:match_delete(?TAB, {{stats_counters, '_'}, '_'}),
	{ok, State};
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% Internal.

set_monitored_process(Key, Pid, State=#state{monitors=Monitors0}) ->
	%% First we cleanup the monitor if a residual one exists.
	%% This can happen during crashes when the restart is faster
	%% than the cleanup.
	Monitors = case lists:keytake(Key, 2, Monitors0) of
		false ->
			Monitors0;
		{value, {{OldMonitorRef, _}, _}, Monitors1} ->
			true = erlang:demonitor(OldMonitorRef, [flush]),
			Monitors1
	end,
	%% Then we unconditionally insert in the ets table.
	%% If residual data is there, it will be overwritten.
	true = ets:insert(?TAB, {Key, Pid}),
	%% Finally we start monitoring this new process.
	MonitorRef = erlang:monitor(process, Pid),
	State#state{monitors=[{{MonitorRef, Pid}, Key}|Monitors]}.
