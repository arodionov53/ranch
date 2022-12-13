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

-export([start_link/5]).
-export([loop/5]).

-spec start_link(inet:socket(), module(), ranch:ref(), module(), any())
	-> {ok, pid()}.

start_link(LSocket, Transport, Ref, Protocol, ProtoOpts) ->
	Pid = spawn_link(?MODULE, loop, [LSocket, Transport, Ref, Protocol, ProtoOpts]),
	ranch_server:add_acceptor(Ref, Pid, LSocket),
	{ok, Pid}.

-spec loop(inet:socket(), module(), ranch:ref(), module(), any()) ->
    no_return().

% Ref, Opts
loop(LSocket, Transport, Ref, Protocol, Opts) ->
    case Transport:accept(LSocket, infinity) of
		{ok, CSocket} ->
			case Protocol:start_link(Ref, CSocket, Transport, Opts) of
				{ok, Pid} ->
					ranch_server:add_connection(Ref, Pid, CSocket),
					Transport:controlling_process(CSocket, Pid);
                _ ->
					Transport:close(CSocket)
			end;
		{error, Reason} when Reason =/= closed ->
			ok
	end,
	flush(),
	?MODULE:loop(LSocket, Transport, Ref, Protocol, Opts).

flush() ->
	receive Msg ->
		error_logger:error_msg(
			"Ranch acceptor received unexpected message: ~p~n",
			[Msg]),
		flush()
	after 0 ->
		ok
	end.
