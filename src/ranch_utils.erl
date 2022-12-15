-module(ranch_utils).

-export([median/1]).

-spec median([number()]) -> number().
% @doc Calculates list of numbers median; uses lists:sort.
median(Lst) ->
    S = lists:sort(Lst),
    L = length(S),
    M = L div 2,
    case L rem 2 of
        1 -> lists:nth(M+1, S);
        0 -> (lists:nth(M, S) + lists:nth(M+1, S))/2
    end.

