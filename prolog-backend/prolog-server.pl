% ============================================================
%  Dots & Boxes — SWI-Prolog HTTP Backend  (порт 3002)
% ============================================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_header)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).

:- dynamic g_size/1.
:- dynamic g_hline/2.
:- dynamic g_vline/2.
:- dynamic g_owner/3.
:- dynamic g_score/2.
:- dynamic g_current/1.
:- dynamic g_name/2.
:- dynamic g_moves/1.
:- dynamic g_over/1.
:- dynamic g_difficulty/1.
:- dynamic g_last_ai/3.

% ============================================================
% МАРШРУТИ
% ============================================================

:- http_handler(root(state), handle_state, []).
:- http_handler(root(new),   handle_new,   []).
:- http_handler(root(move),  handle_move,  []).
:- http_handler(root(ai),    handle_ai,    []).

server(Port) :-
    http_server(http_dispatch, [port(Port)]),
    init_game(3, 'Гравець 1', 'Гравець 2', medium),
    format("Prolog backend -> http://localhost:~w~n", [Port]),
    thread_get_message(_).

handle_state(_Request) :-
    state_json(JSON), reply_json_dict(JSON).

handle_new(Request) :-
    http_read_json_dict(Request, Dict),
    ( get_dict(size,       Dict, S0) -> true ; S0 = 3 ),
    ( get_dict(name1,      Dict, N1) -> true ; N1 = "Гравець 1" ),
    ( get_dict(name2,      Dict, N2) -> true ; N2 = "Гравець 2" ),
    ( get_dict(difficulty, Dict, D0) -> true ; D0 = "medium" ),
    ( integer(S0) -> N = S0 ; number(S0) -> N is round(S0) ; N = 3 ),
    atom_string(Diff, D0),
    init_game(N, N1, N2, Diff),
    state_json(JSON), reply_json_dict(JSON).

handle_move(Request) :-
    http_read_json_dict(Request, Dict),
    get_dict(dir, Dict, DirStr),
    get_dict(row, Dict, Row),
    get_dict(col, Dict, Col),
    ( DirStr = "H" -> Dir = h ; Dir = v ),
    ( g_over(_) ->
        reply_json_dict(_{error: "Гра вже завершена"})
    ; valid_move(Dir, Row, Col) ->
        do_move(Dir, Row, Col),
        retractall(g_last_ai(_,_,_)),
        state_json(JSON), reply_json_dict(JSON)
    ;
        reply_json_dict(_{error: "Невалідний хід"})
    ).

handle_ai(_Request) :-
    catch(
        (
            catch(
                ( \+ g_over(_) -> ( do_ai_move -> true ; true ) ; true ),
                ErrAI,
                format(user_error, "DO_AI_MOVE ERROR: ~w~n", [ErrAI])
            ),
            catch(
                state_json(JSON),
                ErrState,
                ( format(user_error, "STATE_JSON ERROR: ~w~n", [ErrState]),
                  JSON = _{error: "state_json failed"} )
            ),
            reply_json_dict(JSON)
        ),
        ErrTop,
        ( format(user_error, "TOP ERROR: ~w~n", [ErrTop]),
          reply_json_dict(_{error: "internal error"}) )
    ).

% ============================================================
% ІНІЦІАЛІЗАЦІЯ
% ============================================================

init_game(N, Name1, Name2, Diff) :-
    retractall(g_size(_)), retractall(g_hline(_,_)), retractall(g_vline(_,_)),
    retractall(g_owner(_,_,_)), retractall(g_score(_,_)), retractall(g_current(_)),
    retractall(g_name(_,_)), retractall(g_moves(_)), retractall(g_over(_)),
    retractall(g_difficulty(_)), retractall(g_last_ai(_,_,_)),
    assert(g_size(N)), assert(g_current(1)),
    assert(g_score(1, 0)), assert(g_score(2, 0)),
    assert(g_name(1, Name1)), assert(g_name(2, Name2)),
    assert(g_moves(0)), assert(g_difficulty(Diff)).

% ============================================================
% ІГРОВА ЛОГІКА
% ============================================================

valid_move(h, R, C) :-
    g_size(N), R >= 0, R =< N, C >= 0, C < N, \+ g_hline(R, C).
valid_move(v, R, C) :-
    g_size(N), R >= 0, R < N, C >= 0, C =< N, \+ g_vline(R, C).

box_complete(R, C) :-
    R1 is R+1, C1 is C+1,
    g_hline(R,C), g_hline(R1,C), g_vline(R,C), g_vline(R,C1).

newly_completed(R, C) :- box_complete(R, C), \+ g_owner(R, C, _).

adjacent_boxes(h, Row, Col, Boxes) :-
    g_size(N), Max is N-1,
    Row0 is Row, Row1 is Row-1,
    findall(R-Col,
        ( (R=Row0, R>=0, R=<Max) ; (R=Row1, R>=0, R=<Max) ),
        Cands),
    include(is_newly_completed, Cands, Boxes).

adjacent_boxes(v, Row, Col, Boxes) :-
    g_size(N), Max is N-1,
    Col0 is Col, Col1 is Col-1,
    findall(Row-C,
        ( (C=Col0, C>=0, C=<Max) ; (C=Col1, C>=0, C=<Max) ),
        Cands),
    include(is_newly_completed, Cands, Boxes).

is_newly_completed(R-C) :- newly_completed(R, C).

do_move(Dir, Row, Col) :-
    ( Dir=h -> assert(g_hline(Row,Col)) ; assert(g_vline(Row,Col)) ),
    retract(g_moves(M)), M1 is M+1, assert(g_moves(M1)),
    adjacent_boxes(Dir, Row, Col, NewBoxes),
    process_boxes(NewBoxes).

process_boxes([]) :- switch_player.
process_boxes(Boxes) :-
    Boxes \= [],
    g_current(P), length(Boxes, Num),
    assert_owners(Boxes, P),
    retract(g_score(P,S)), S2 is S+Num, assert(g_score(P,S2)),
    check_game_over.

assert_owners([], _).
assert_owners([R-C|Rest], P) :-
    assert(g_owner(R, C, P)),
    assert_owners(Rest, P).

switch_player :-
    retract(g_current(P)), P2 is 3-P, assert(g_current(P2)), check_game_over.

check_game_over :-
    g_size(N), Total is N*N,
    aggregate_all(count, g_owner(_,_,_), Cnt),
    ( Cnt =:= Total ->
        g_score(1,S1), g_score(2,S2),
        ( S1>S2->W=1 ; S2>S1->W=2 ; W=draw ),
        assert(g_over(W))
    ; true ).

% ============================================================
% ГЕНЕРАТОР ВСІХ ВАЛІДНИХ ХОДІВ
%
% Використовує between/3 для породження конкретних значень R, C —
% це уникає instantiation_error у valid_move при виклику з findall.
% ============================================================

all_valid_moves(Moves) :-
    g_size(N),
    % Горизонтальні лінії: R від 0 до N, C від 0 до N-1
    RmaxH is N,
    CmaxH is N - 1,
    findall(h-R-C,
        ( between(0, RmaxH, R),
          between(0, CmaxH, C),
          \+ g_hline(R, C) ),
        HMoves),
    % Вертикальні лінії: R від 0 до N-1, C від 0 до N
    RmaxV is N - 1,
    CmaxV is N,
    findall(v-R-C,
        ( between(0, RmaxV, R),
          between(0, CmaxV, C),
          \+ g_vline(R, C) ),
        VMoves),
    append(HMoves, VMoves, Moves).

% ============================================================
% CLP-ФІЛЬТРАЦІЯ ХОДІВ
% ============================================================

sides_of_box(R, C, Count) :-
    R1 is R+1, C1 is C+1,
    ( g_hline(R, C)  -> A=1 ; A=0 ),
    ( g_hline(R1,C)  -> B=1 ; B=0 ),
    ( g_vline(R, C)  -> D=1 ; D=0 ),
    ( g_vline(R, C1) -> E=1 ; E=0 ),
    Count is A+B+D+E.

adj_candidates(h, Row, Col, Boxes) :-
    g_size(N), Max is N-1,
    Row0 is Row, Row1 is Row-1,
    findall(R-Col,
        ( (R=Row0, R>=0, R=<Max) ; (R=Row1, R>=0, R=<Max) ),
        Boxes).
adj_candidates(v, Row, Col, Boxes) :-
    g_size(N), Max is N-1,
    Col0 is Col, Col1 is Col-1,
    findall(Row-C,
        ( (C=Col0, C>=0, C=<Max) ; (C=Col1, C>=0, C=<Max) ),
        Boxes).

% capturing_move/3 — Dir, Row, Col мають бути вже зв'язані при виклику
capturing_move(Dir, Row, Col) :-
    adj_candidates(Dir, Row, Col, Boxes),
    member(R-C, Boxes),
    \+ g_owner(R, C, _),
    sides_of_box(R, C, 3).

% opens_box/3 — Dir, Row, Col мають бути вже зв'язані при виклику
opens_box(Dir, Row, Col) :-
    adj_candidates(Dir, Row, Col, Boxes),
    member(R-C, Boxes),
    \+ g_owner(R, C, _),
    sides_of_box(R, C, 2).

safe_move(Dir-Row-Col) :-
    \+ opens_box(Dir, Row, Col).

clp_filtered_moves(Moves) :-
    all_valid_moves(All),
    % Constraint-1: захоплюючі ходи
    include(is_capturing, All, Capturing),
    ( Capturing \= [] -> Moves = Capturing
    ;
        % Constraint-2: безпечні ходи
        include(safe_move, All, Safe),
        ( Safe \= [] -> Moves = Safe
        ; Moves = All )
    ).

is_capturing(Dir-Row-Col) :-
    capturing_move(Dir, Row, Col).

% ============================================================
% AI ХІД
% ============================================================

difficulty_depth(easy,   2).
difficulty_depth(medium, 4).
difficulty_depth(hard,   6).
difficulty_depth(expert, 8).

difficulty_name(easy,   "Легкий (2 нп)").
difficulty_name(medium, "Середній (4 нп)").
difficulty_name(hard,   "Важкий (6 нп)").
difficulty_name(expert, "Експерт (8 нп)").

do_ai_move :-
    \+ g_over(_),
    clp_filtered_moves(Moves),
    Moves \= [],
    Moves = [Best|_],
    Best = BD-BR-BC,
    do_move(BD, BR, BC),
    retractall(g_last_ai(_,_,_)),
    ( BD=h -> DS="H" ; DS="V" ),
    assert(g_last_ai(DS, BR, BC)).

% ============================================================
% СЕРІАЛІЗАЦІЯ
% ============================================================

to_str(X,S) :- ( string(X)->S=X ; atom(X)->atom_string(X,S) ; term_string(X,S) ).

state_json(JSON) :-
    g_size(N), g_current(P),
    g_score(1,S1), g_score(2,S2),
    g_name(1,Name1), g_name(2,Name2), g_moves(MC), g_difficulty(Diff),
    to_str(Name1,N1Str), to_str(Name2,N2Str),
    ( difficulty_name(Diff,DiffName)->true ; DiffName="Середній (4 нп)" ),
    ( difficulty_depth(Diff,Depth)  ->true ; Depth=4 ),
    ( g_over(W) ->
        Over=true,
        ( W=draw -> Winner="Нічия!"
        ; g_name(W,WN), to_str(WN,WStr), string_concat(WStr," перемагає!",Winner) )
    ; Over=false, Winner=null ),
    ( g_last_ai(LADir,LARow,LACol) -> LastAI=_{dir:LADir,row:LARow,col:LACol}
    ; LastAI=null ),
    findall(_{dir:"H",row:R,col:C}, g_hline(R,C), HLines),
    findall(_{dir:"V",row:R,col:C}, g_vline(R,C), VLines),
    append(HLines,VLines,Lines),
    findall(_{row:R,col:C,player:Pl}, g_owner(R,C,Pl), Owners),
    JSON=_{size:N, lines:Lines, owners:Owners,
           score1:S1, score2:S2, current:P,
           name1:N1Str, name2:N2Str, moveCount:MC,
           over:Over, winner:Winner,
           mode:"human-human", difficulty:DiffName, depth:Depth, lastAI:LastAI}.