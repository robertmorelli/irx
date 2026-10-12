#!/usr/bin/env escript
%%! +A0
%% irx host: Erlang's re module (PCRE2-based in OTP 28+), Perl-dialect patterns with unicode + ucp.
%% Modes: default/shell, repeat, span, ospan (offset), aspan (sticky: anchored at the offset), capture.
-mode(compile).

main([Mode]) -> loop(Mode);
main(_) -> loop("default").

loop(Mode) ->
    io:setopts(standard_io, [binary]),
    io:format("ready erlang-re-otp~s mode=~s~n", [erlang:system_info(otp_release), Mode]),
    next(Mode).

next(Mode) ->
    case io:get_line(standard_io, "") of
        eof -> ok;
        {error, _} -> ok;
        Line ->
            case string:trim(Line) of
                <<>> -> next(Mode);
                L ->
                    [Seq, Cases] = json:decode(L),
                    Out = [run_case(Mode, C) || C <- Cases],
                    io:put_chars([integer_to_list(Seq), " ", Out, "\n"]),
                    next(Mode)
            end
    end.

opts(Flags) ->
    [unicode, ucp] ++ [caseless || has($i, Flags)] ++ [multiline || has($m, Flags)] ++ [dotall || has($s, Flags)].
has(C, Flags) -> binary:match(Flags, <<C>>) =/= nomatch.

split_flags(F) ->
    case binary:split(F, <<"@">>) of
        [Fl, Offs] -> [A, R] = binary:split(Offs, <<",">>), {Fl, binary_to_integer(A), binary_to_integer(R)};
        [Fl] -> {Fl, 0, 0}
    end.

hex2(N) -> io_lib:format("~2.16.0b", [N]).
fail(B, Rest) -> ["fe", hex2(B), lists:duplicate(Rest, "00")].

run_case("bench", [F0, A, R, P]) -> bench(F0, A, R, P);
run_case(Mode, [F0, A, R, P]) ->
    {F, OA, OR} = split_flags(F0),
    case Mode of
        "span" -> span(F, A, R, P, 0, 0, []);
        "ospan" -> span(F, A, R, P, OA, OR, []);
        "aspan" -> span(F, A, R, P, OA, OR, [anchored]);
        "capture" -> capture(F, A, R, P);
        _ -> full(Mode, F, A, R, P)
    end.

full(Mode, F, A, R, P) ->
    case re:compile(<<"\\A(?:", P/binary, ")\\z">>, opts(F)) of
        {error, _} -> "04";
        {ok, MP} ->
            Reps = case Mode of "repeat" -> 2; "tierup" -> 2; _ -> 1 end,
            try
                Bits = lists:foldl(fun({K, S, Rep}, Acc) ->
                    case re:run(S, MP, [{capture, none}]) of
                        match -> Acc bor ((1 bsl K) bsl (4 * Rep));
                        nomatch -> Acc;
                        {error, _} -> throw(limit)
                    end end, 0, [{K, S, Rep} || Rep <- lists:seq(0, Reps - 1), {K, S} <- [{0, A}, {1, R}]]),
                hex2(Bits)
            catch throw:limit -> "40"; _:_ -> "08"
            end
    end.

span(F, A, R, P, OA, OR, RunOpts) ->
    case re:compile(P, opts(F)) of
        {error, _} -> fail(4, 2);
        {ok, MP} ->
            try
                [case re:run(S, MP, [{capture, first, index}, {offset, O} | RunOpts]) of
                     {match, [{Pos, Len}]} -> [hex2(Pos), hex2(Pos + Len)];
                     nomatch -> "ffff";
                     {error, _} -> throw(limit)
                 end || {S, O} <- [{A, OA}, {R, OR}]]
            catch throw:limit -> fail(16#40, 2); _:_ -> fail(8, 2)
            end
    end.

capture(F, A, R, P) ->
    case re:compile(P, opts(F)) of
        {error, _} -> fail(4, 26);
        {ok, MP} ->
            try
                [case re:run(S, MP, [{capture, all, index}]) of
                     {match, Gs} ->
                         Gs7 = lists:sublist(Gs ++ lists:duplicate(7, {-1, 0}), 7),
                         [case G of {-1, _} -> "ffff"; {Pos, Len} -> [hex2(Pos), hex2(Pos + Len)] end || G <- Gs7];
                     nomatch -> lists:duplicate(7, "ffff");
                     {error, _} -> throw(limit)
                 end || S <- [A, R]]
            catch throw:limit -> fail(16#40, 26); _:_ -> fail(8, 26)
            end
    end.

%% bench (Shootout 2): "<flags>#<reps>"; compile once, timed re:run loops (capture none).
hex12(N) -> io_lib:format("~12.16.0b", [N]).
bench(F0, A, R, P) ->
    {F, N} = case binary:split(F0, <<"#">>) of [Fl, Ns] -> {Fl, max(1, binary_to_integer(Ns))}; [Fl] -> {Fl, 1} end,
    T0 = erlang:monotonic_time(nanosecond),
    case re:compile(P, opts(F)) of
        {error, _} -> ["fe04", lists:duplicate(36, $0)];
        {ok, MP} ->
            Tc = erlang:monotonic_time(nanosecond) - T0,
            try
                M = fun(S) -> case re:run(S, MP, [{capture, none}]) of match -> 1; nomatch -> 0; {error, _} -> throw(limit) end end,
                Bits = M(A) bor (M(R) bsl 1),
                Loop = fun Lp(_, 0) -> ok; Lp(S, K) -> _ = re:run(S, MP, [{capture, none}]), Lp(S, K - 1) end,
                T1 = erlang:monotonic_time(nanosecond), Loop(A, N),
                T2 = erlang:monotonic_time(nanosecond), Loop(R, N),
                T3 = erlang:monotonic_time(nanosecond),
                [hex2(Bits), hex12(Tc), hex12(T2 - T1), hex12(T3 - T2)]
            catch throw:limit -> ["fe40", lists:duplicate(36, $0)]; _:_ -> ["fe08", lists:duplicate(36, $0)]
            end
    end.
