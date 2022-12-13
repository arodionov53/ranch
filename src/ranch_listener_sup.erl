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

-module(ranch_listener_sup).
-behaviour(supervisor).

-export([start_link/6]).
-export([init/1]).

-spec start_link(ranch:ref(), non_neg_integer(), module(), any(), module(), any())
	-> {ok, pid()}.
start_link(Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts) ->
	% MaxConns = maps:get(max_connections, TransOpts, 1024),  % from ranch2
	MaxConns = 1024,
	ranch_server:set_new_listener_opts(Ref, MaxConns, TransOpts, ProtoOpts,
		[Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts]),   % from ranch2
	supervisor:start_link(?MODULE, {
		Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts
	}).

init({Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts}) ->
	ok = ranch_server:set_listener_sup(Ref, self()),   % from ranch2

	ChildSpecs = [
		{ranch_acceptors_sup, {ranch_acceptors_sup, start_link,
				[Ref, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts]},
			permanent, infinity, supervisor, [ranch_acceptors_sup]}
	],
	{ok, {{rest_for_one, 10, 10}, ChildSpecs}}.
