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

-module(ranch_acceptor).

-export([start_link/3]).
-export([loop/4]).

-spec start_link(ranch:ref(), inet:socket(), module())
	-> {ok, pid()}.
start_link(Ref, LSocket, Transport) ->
	Opts = ranch_server:get_protocol_options(Ref),
	Pid = spawn_link(?MODULE, loop, [Ref, LSocket, Transport, Opts]),
	{ok, Pid}.

-spec loop(ranch:ref(), inet:socket(), module(), any()) -> no_return().
loop(Ref, LSocket, Transport, Opts) ->
	process_flag(trap_exit, true),
	cowboy_protocol:start_link(self(), Ref, LSocket, Transport, Opts),
	receive_loop(Ref, LSocket, Transport, Opts).

receive_loop(Ref, LSocket, Transport, Opts) ->
	receive
		accepted ->
			?MODULE:loop(Ref, LSocket, Transport, Opts);
		{'EXIT', _Pid, normal} ->
			receive_loop(Ref, LSocket, Transport, Opts);
		Msg ->
			luger:info("ranch", "unexpected msg: ~p~n", [Msg]),
			receive_loop(Ref, LSocket, Transport, Opts)
	end.

