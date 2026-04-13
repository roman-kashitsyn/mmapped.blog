(* Hand-rolled parser combinators, modeled after Text.Parsec.

   Semantics intentionally match Parsec's [(<|>)] / [try] discipline:
   - A parser may either succeed (POk) or fail (PFail).
   - On PFail we record whether *any* input was consumed; (<|>) only tries
     the right alternative when the left side failed *without consuming
     input*. Use [try_] to wrap a parser whose failure should be
     "rewindable" — exactly like Parsec's [try]. *)

type pos = Parser_pos.t

type state = {
  src : string;
  ofs : int;
  pos : pos;
}

(* Step result: success (POk) or failure (PFail). The bool flag indicates
   whether input was consumed; alternatives are only attempted on a
   non-consuming failure. *)
type 'a step =
  | POk of 'a * state * bool
  | PFail of pos * string * bool

type 'a t = state -> 'a step

(* --- core combinators --- *)

let return (x : 'a) : 'a t = fun st -> POk (x, st, false)

let fail (msg : string) : 'a t = fun st -> PFail (st.pos, msg, false)

let unexpected (what : string) : 'a t = fun st ->
  PFail (st.pos, "unexpected " ^ what, false)

let bind (p : 'a t) (f : 'a -> 'b t) : 'b t = fun st ->
  match p st with
  | PFail _ as e -> e
  | POk (x, st', c1) ->
    (match f x st' with
     | POk (y, st'', c2) -> POk (y, st'', c1 || c2)
     | PFail (pos, msg, c2) -> PFail (pos, msg, c1 || c2))

let ( let* ) = bind
let ( >>= ) = bind

let map (f : 'a -> 'b) (p : 'a t) : 'b t = fun st ->
  match p st with
  | POk (x, st', c) -> POk (f x, st', c)
  | PFail _ as e -> e

let ( >>| ) p f = map f p

let seq (p : 'a t) (q : 'b t) : 'b t = bind p (fun _ -> q)
let ( *> ) = seq

let seq_l (p : 'a t) (q : 'b t) : 'a t = fun st ->
  match p st with
  | PFail _ as e -> e
  | POk (x, st', c1) ->
    (match q st' with
     | POk (_, st'', c2) -> POk (x, st'', c1 || c2)
     | PFail (pos, msg, c2) -> PFail (pos, msg, c1 || c2))

let ( <* ) = seq_l

(* Choice: try [p]; if it fails *without consuming*, try [q].
   When both alternatives fail non-committing, keep the error from the
   one whose position is furthest — matching Parsec's error-merge rule so
   the most informative diagnostic survives. *)
let or_ (p : 'a t) (q : 'a t) : 'a t = fun st ->
  match p st with
  | POk _ as r -> r
  | PFail (_, _, true) as e -> e
  | PFail (p1, m1, false) ->
    (match q st with
     | POk _ as r -> r
     | PFail (p2, m2, c2) ->
       if Parser_pos.compare p1 p2 > 0 then PFail (p1, m1, c2)
       else PFail (p2, m2, c2))

let ( <|> ) = or_

let choice (ps : 'a t list) : 'a t =
  List.fold_right ( <|> ) ps (fail "no alternatives matched")

(* try_: rewind input on failure so the alternative may run. *)
let try_ (p : 'a t) : 'a t = fun st ->
  match p st with
  | POk _ as r -> r
  | PFail (pos, msg, _) -> PFail (pos, msg, false)

(* --- input inspection --- *)

let eof : unit t = fun st ->
  if st.ofs >= String.length st.src then POk ((), st, false)
  else PFail (st.pos, "expected end of input", false)

let any_char : char t = fun st ->
  if st.ofs >= String.length st.src then
    PFail (st.pos, "unexpected end of input", false)
  else
    let c = st.src.[st.ofs] in
    POk (c,
         { st with ofs = st.ofs + 1; pos = Parser_pos.advance st.pos c },
         true)

let satisfy (f : char -> bool) : char t = fun st ->
  if st.ofs >= String.length st.src then
    PFail (st.pos, "unexpected end of input", false)
  else
    let c = st.src.[st.ofs] in
    if f c then
      POk (c,
           { st with ofs = st.ofs + 1; pos = Parser_pos.advance st.pos c },
           true)
    else
      PFail (st.pos, Printf.sprintf "unexpected character %C" c, false)

let char (c : char) : char t = fun st ->
  if st.ofs >= String.length st.src then
    PFail (st.pos, Printf.sprintf "expected %C, got end of input" c, false)
  else if st.src.[st.ofs] = c then
    POk (c,
         { st with ofs = st.ofs + 1; pos = Parser_pos.advance st.pos c },
         true)
  else
    PFail (st.pos,
           Printf.sprintf "expected %C, got %C" c st.src.[st.ofs],
           false)

let one_of (chars : string) : char t =
  satisfy (fun c -> String.contains chars c)

let none_of (chars : string) : char t =
  satisfy (fun c -> not (String.contains chars c))

(* Match a literal multi-character string. Atomic: either fully consumes
   the prefix or fully rewinds (Parsec's [string] is partially consuming,
   but for the rest of the parser we want atomicity). *)
let string (lit : string) : string t = fun st ->
  let n = String.length lit in
  if st.ofs + n > String.length st.src then
    PFail (st.pos, Printf.sprintf "expected %S" lit, false)
  else if String.sub st.src st.ofs n = lit then begin
    let pos = ref st.pos in
    for i = 0 to n - 1 do pos := Parser_pos.advance !pos lit.[i] done;
    POk (lit, { st with ofs = st.ofs + n; pos = !pos }, n > 0)
  end
  else
    PFail (st.pos, Printf.sprintf "expected %S" lit, false)

(* --- repetition --- *)

let many (p : 'a t) : 'a list t = fun st0 ->
  let rec loop acc st consumed =
    match p st with
    | PFail (_, _, false) -> POk (List.rev acc, st, consumed)
    | PFail _ as e -> e
    | POk (x, st', c) -> loop (x :: acc) st' (consumed || c)
  in
  loop [] st0 false

let many1 (p : 'a t) : 'a list t =
  let* x = p in
  let* xs = many p in
  return (x :: xs)

let skip_many (p : 'a t) : unit t = fun st0 ->
  let rec loop st consumed =
    match p st with
    | PFail (_, _, false) -> POk ((), st, consumed)
    | PFail _ as e -> e
    | POk (_, st', c) -> loop st' (consumed || c)
  in
  loop st0 false

let optional (p : 'a t) : unit t = fun st ->
  match p st with
  | POk (_, st', c) -> POk ((), st', c)
  | PFail (_, _, false) -> POk ((), st, false)
  | PFail _ as e -> e

let option_maybe (p : 'a t) : 'a option t = fun st ->
  match p st with
  | POk (x, st', c) -> POk (Some x, st', c)
  | PFail (_, _, false) -> POk (None, st, false)
  | PFail _ as e -> e

(* Greedy character-mode "manyTill any-char (string terminator)". Used for
   verbatim and comment scanning. The terminator is consumed too. *)
let many_till_chars (terminator : string) : string t = fun st0 ->
  let n = String.length terminator in
  let len = String.length st0.src in
  let buf = Buffer.create 32 in
  let st = ref st0 in
  let consumed = ref false in
  let found = ref false in
  while not !found && !st.ofs <= len - n &&
        not (String.sub !st.src !st.ofs n = terminator) do
    let c = !st.src.[!st.ofs] in
    Buffer.add_char buf c;
    st := { !st with ofs = !st.ofs + 1; pos = Parser_pos.advance !st.pos c };
    consumed := true
  done;
  if !st.ofs <= len - n && String.sub !st.src !st.ofs n = terminator then begin
    found := true;
    let pos = ref !st.pos in
    for i = 0 to n - 1 do pos := Parser_pos.advance !pos terminator.[i] done;
    st := { !st with ofs = !st.ofs + n; pos = !pos };
    consumed := true
  end;
  if !found then POk (Buffer.contents buf, !st, !consumed)
  else PFail (st0.pos, Printf.sprintf "expected %S" terminator, false)

(* --- lookahead and position --- *)

let look_ahead (p : 'a t) : 'a t = fun st ->
  match p st with
  | POk (x, _, _) -> POk (x, st, false)
  | PFail (pos, msg, _) -> PFail (pos, msg, false)

let get_position : pos t = fun st -> POk (st.pos, st, false)

let set_position (pos : pos) : unit t = fun st ->
  POk ((), { st with pos }, false)

(* --- entry point --- *)

(* Build a string from a char list. *)
let string_of_chars (cs : char list) : string =
  let b = Bytes.create (List.length cs) in
  List.iteri (fun i c -> Bytes.unsafe_set b i c) cs;
  Bytes.unsafe_to_string b

let run (p : 'a t) ~source_name (input : string) : ('a, Error.parse_error) result =
  let st = { src = input; ofs = 0; pos = Parser_pos.initial source_name } in
  match p st with
  | POk (x, _, _) -> Ok x
  | PFail (pos, msg, _) ->
    Error { Error.pe_pos = pos; pe_message = msg }
