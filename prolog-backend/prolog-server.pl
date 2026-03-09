% ============================================================
%  Dots & Boxes — SWI-Prolog HTTP Backend
%  Порт: 3001
%
%  ЗАПУСК:
%    swipl -g "server(3001)" prolog-server.pl
% ============================================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_header)).
:- use_module(library(http/http_parameters)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).

% ============================================================
% СТАН ГРИ
% ============================================================

:- dynamic g_size/1.
:- dynamic g_hline/2.
:- dynamic g_vline/2.
:- dynamic g_owner/3.
:- dynamic g_score/2.
:- dynamic g_current/1.
:- dynamic g_name/2.
:- dynamic g_moves/1.
:- dynamic g_over/1.

% ============================================================
% МАРШРУТИ
% ============================================================

:- http_handler(root(state),  handle_state,  []).
:- http_handler(root(new),    handle_new,    []).
:- http_handler(root(move),   handle_move,   []).

server(Port) :-
    http_server(http_dispatch, [port(Port)]),
    init_game(3, 'Гравець 1', 'Гравець 2'),
    format("Prolog backend -> http://localhost:~w~n", [Port]).

% ============================================================
% CORS — додаємо до кожної відповіді
% ============================================================

cors_reply(JSON) :-
    format("Access-Control-Allow-Origin: *~n"),
    format("Access-Control-Allow-Methods: GET, POST, OPTIONS~n"),
    format("Access-Control-Allow-Headers: Content-Type~n"),
    reply_json_dict(JSON).

% ============================================================
% ОБРОБНИКИ
% ============================================================

handle_state(Request) :-
    ( memberchk(method(options), Request) ->
        format("Status: 204 No Content~n"),
        format("Access-Control-Allow-Origin: *~n"),
        format("Access-Control-Allow-Methods: GET, POST, OPTIONS~n"),
        format("Access-Control-Allow-Headers: Content-Type~n~n")
    ;
        state_json(JSON),
        cors_reply(JSON)
    ).

handle_new(Request) :-
    ( memberchk(method(options), Request) ->
        format("Status: 204 No Content~n"),
        format("Access-Control-Allow-Origin: *~n"),
        format("Access-Control-Allow-Methods: GET, POST, OPTIONS~n"),
        format("Access-Control-Allow-Headers: Content-Type~n~n")
    ;
        http_read_json_dict(Request, Dict),
        ( get_dict(size,  Dict, Size0) -> true ; Size0 = 3 ),
        ( get_dict(name1, Dict, N1)   -> true ; N1 = "Гравець 1" ),
        ( get_dict(name2, Dict, N2)   -> true ; N2 = "Гравець 2" ),
        ( integer(Size0) -> N = Size0
        ; number(Size0)  -> N is round(Size0)
        ; N = 3
        ),
        init_game(N, N1, N2),
        state_json(JSON),
        cors_reply(JSON)
    ).

handle_move(Request) :-
    ( memberchk(method(options), Request) ->
        format("Status: 204 No Content~n"),
        format("Access-Control-Allow-Origin: *~n"),
        format("Access-Control-Allow-Methods: GET, POST, OPTIONS~n"),
        format("Access-Control-Allow-Headers: Content-Type~n~n")
    ;
        http_read_json_dict(Request, Dict),
        get_dict(dir, Dict, DirStr),
        get_dict(row, Dict, Row),
        get_dict(col, Dict, Col),
        ( DirStr = "H" -> Dir = h ; Dir = v ),
        ( g_over(_) ->
            cors_reply(_{error: "Гра вже завершена"})
        ; valid_move(Dir, Row, Col) ->
            do_move(Dir, Row, Col),
            state_json(JSON),
            cors_reply(JSON)
        ;
            cors_reply(_{error: "Невалідний хід"})
        )
    ).

% ============================================================
% ІНІЦІАЛІЗАЦІЯ
% ============================================================

init_game(N, Name1, Name2) :-
    retractall(g_size(_)),
    retractall(g_hline(_,_)),
    retractall(g_vline(_,_)),
    retractall(g_owner(_,_,_)),
    retractall(g_score(_,_)),
    retractall(g_current(_)),
    retractall(g_name(_,_)),
    retractall(g_moves(_)),
    retractall(g_over(_)),
    assert(g_size(N)),
    assert(g_current(1)),
    assert(g_score(1, 0)),
    assert(g_score(2, 0)),
    assert(g_name(1, Name1)),
    assert(g_name(2, Name2)),
    assert(g_moves(0)).

% ============================================================
% ІГРОВА ЛОГІКА
% ============================================================

valid_move(h, R, C) :-
    g_size(N), R >= 0, R =< N, C >= 0, C < N,
    \+ g_hline(R, C).
valid_move(v, R, C) :-
    g_size(N), R >= 0, R < N, C >= 0, C =< N,
    \+ g_vline(R, C).

box_complete(R, C) :-
    R1 is R+1, C1 is C+1,
    g_hline(R,C), g_hline(R1,C),
    g_vline(R,C), g_vline(R,C1).

newly_completed(R, C) :-
    box_complete(R, C), \+ g_owner(R,C,_).

adjacent_boxes(h, Row, Col, Boxes) :-
    g_size(N), Max is N-1,
    findall(R-Col,
        (  (R = Row,    R >= 0, R =< Max)
        ;  (R is Row-1, R >= 0, R =< Max)
        ), Cands),
    include([RC]>>(RC=Rr-Cc, newly_completed(Rr,Cc)), Cands, Boxes).

adjacent_boxes(v, Row, Col, Boxes) :-
    g_size(N), Max is N-1,
    findall(Row-C,
        (  (C = Col,    C >= 0, C =< Max)
        ;  (C is Col-1, C >= 0, C =< Max)
        ), Cands),
    include([RC]>>(RC=Rr-Cc, newly_completed(Rr,Cc)), Cands, Boxes).

do_move(Dir, Row, Col) :-
    ( Dir = h -> assert(g_hline(Row,Col)) ; assert(g_vline(Row,Col)) ),
    retract(g_moves(M)), M1 is M+1, assert(g_moves(M1)),
    adjacent_boxes(Dir, Row, Col, NewBoxes),
    process_boxes(NewBoxes).

process_boxes([]) :- switch_player.
process_boxes(Boxes) :-
    Boxes \= [],
    g_current(P),
    length(Boxes, N),
    maplist([R-C]>>(assert(g_owner(R,C,P))), Boxes),
    retract(g_score(P, S)), S2 is S+N, assert(g_score(P, S2)),
    check_game_over.

switch_player :-
    retract(g_current(P)), P2 is 3-P, assert(g_current(P2)),
    check_game_over.

check_game_over :-
    g_size(N), Total is N*N,
    aggregate_all(count, g_owner(_,_,_), Cnt),
    ( Cnt =:= Total ->
        g_score(1,S1), g_score(2,S2),
        ( S1 > S2 -> W = 1 ; S2 > S1 -> W = 2 ; W = draw ),
        assert(g_over(W))
    ; true
    ).

% ============================================================
% СЕРІАЛІЗАЦІЯ В JSON
% ============================================================

to_string(X, S) :-
    ( string(X)  -> S = X
    ; atom(X)    -> atom_string(X, S)
    ; term_string(X, S)
    ).

state_json(JSON) :-
    g_size(N),
    g_current(P),
    g_score(1,S1), g_score(2,S2),
    g_name(1,Name1), g_name(2,Name2),
    g_moves(MC),
    to_string(Name1, N1Str),
    to_string(Name2, N2Str),
    ( g_over(W) ->
        Over = true,
        ( W = draw ->
            Winner = "Нічия!"
        ;
            g_name(W, WName),
            to_string(WName, WStr),
            string_concat(WStr, " перемагає!", Winner)
        )
    ;
        Over = false,
        Winner = null
    ),
    findall(_{dir:"H", row:R, col:C}, g_hline(R,C), HLines),
    findall(_{dir:"V", row:R, col:C}, g_vline(R,C), VLines),
    append(HLines, VLines, Lines),
    findall(_{row:R, col:C, player:Pl}, g_owner(R,C,Pl), Owners),
    JSON = _{
        size:      N,
        lines:     Lines,
        owners:    Owners,
        score1:    S1,
        score2:    S2,
        current:   P,
        name1:     N1Str,
        name2:     N2Str,
        moveCount: MC,
        over:      Over,
        winner:    Winner
    }.