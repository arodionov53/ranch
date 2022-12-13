-module(ranch_tools).

-export([get_ip/1, msg_queue/1]).

get_ip(ranch_listener_sup) -> 
    [A |_] =  supervisor:which_children(ranch_sup),
    element(2, A); 
get_ip(ranch_acceptors_sup) ->
    [A] = supervisor:which_children(get_ip(ranch_listener_sup)),
    element(2, A);
get_ip(acceptors) ->
    [element(2, X) || X <- get_ip(ranch_acceptors_sup)].

msg_queue(ranch_listener_sup) ->
    erlang:process_info(get_ip(ranch_listener_sup));
msg_queue(ranch_acceptors_sup) ->
    erlang:process_info(get_ip(ranch_acceptors_sup));
msg_queue(acceptors) ->
    [erlang:process_info(Ip, message_queue_len) || Ip <- get_ip(acceptors)].
