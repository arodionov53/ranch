-module(ranch_queue).

-export([get_ip/1,info/1, msg_queue/1]).

-spec get_ip(atom()) -> pid() | [pid()].
get_ip(ranch_listener_sup) -> 
    % [A |_] =  supervisor:which_children(ranch_sup),
    element(2, lists:keyfind([ranch_listener_sup], 4, supervisor:which_children(ranch_sup))); 
get_ip(ranch_acceptors_sup) ->
    [A] = supervisor:which_children(get_ip(ranch_listener_sup)),
    element(2, lists:keyfind(ranch_acceptors_sup, 1, supervisor:which_children(get_ip(ranch_listener_sup))
));
get_ip(acceptors) ->
    [element(2, X) || X <- supervisor:which_children(get_ip(ranch_acceptors_sup))].

-spec info(atom()) -> {pid(), list()} | [{pid(), list()}].
info(ranch_listener_sup) ->
    erlang:process_info(get_ip(ranch_listener_sup));
info(ranch_acceptors_sup) ->
    erlang:process_info(get_ip(ranch_acceptors_sup));
info(acceptors) ->
    [erlang:process_info(Ip) || Ip <- get_ip(acceptors)].

-spec msg_queue(atom()) -> {pid(), non_neg_integer()} | [{pid(), non_neg_integer()}].
msg_queue(ranch_listener_sup) ->
    Ip = get_ip(ranch_listener_sup),
    setelement(1, erlang:process_info(Ip, message_queue_len), Ip);
msg_queue(ranch_acceptors_sup) ->
    Ip = get_ip(ranch_acceptors_sup),
    setelement(1, erlang:process_info(Ip, message_queue_len), Ip);
msg_queue(acceptors) ->
    [setelement(1, erlang:process_info(Ip, message_queue_len), Ip) || Ip <- get_ip(acceptors)].
