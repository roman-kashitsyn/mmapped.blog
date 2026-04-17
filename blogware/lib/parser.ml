(* A simplistic parser combinator modeled after Haskell's Text.Parsec.

   Semantics intentionally match Parsec's [(<|>)] / [try] quirks:
   - A parser may either succeed (POk) or fail (PFail).
   - On PFail we record whether *any* input was consumed;
     (<|>) only tries the right alternative when the left side failed
     *without consuming input*.
     Use [try_] to wrap a parser whose failure should be "rewindable" like Parsec's [try].
*)

module Pos = struct
  type t = int
  type resolved = { line : int; column : int }

  let make offset = offset
  let initial = 0
  let offset p = p
  let equal a b = a = b
  let compare a b = compare a b
  let advance p _c = p + 1
  let advance_by p n = p + n

  let resolve source p =
    let line = ref 1 in
    let column = ref 1 in
    let limit = min p (String.length source) in
    let i = ref 0 in
    while !i < limit do
      if source.[!i] = '\n' then begin
        incr line;
        column := 1
      end
      else incr column;
      let decoded = String.get_utf_8_uchar source !i in
      let step = Uchar.utf_decode_length decoded in
      i := min limit (!i + step)
    done;
    { line = !line; column = !column }

  let to_string (p : t) = Printf.sprintf "offset %d" p
end

type pos = Pos.t
type state = { src : string; source_name : string; ofs : int; pos : pos }
type message = string Lazy.t

(* Step result: success (POk) or failure (PFail). The bool flag indicates
   whether input was consumed; alternatives are only attempted on a
   non-consuming failure. *)
type 'a step = POk of 'a * state * bool | PFail of pos * message * bool
type 'a t = state -> 'a step

type parse_error = {
  pe_source_name : string;
  pe_pos : pos;
  pe_message : string;
}

(* --- core combinators --- *)

let return (x : 'a) : 'a t = fun st -> POk (x, st, false)
let fail (msg : string) : 'a t = fun st -> PFail (st.pos, lazy msg, false)

let unexpected (what : string) : 'a t =
 fun st -> PFail (st.pos, lazy ("unexpected " ^ what), false)

let bind (p : 'a t) (f : 'a -> 'b t) : 'b t =
 fun st ->
  match p st with
  | PFail _ as e -> e
  | POk (x, st', c1) -> (
      match f x st' with
      | POk (y, st'', c2) -> POk (y, st'', c1 || c2)
      | PFail (pos, msg, c2) -> PFail (pos, msg, c1 || c2))

let bind_step (step : 'a step) (f : 'a -> state -> 'b step) : 'b step =
  match step with
  | PFail _ as e -> e
  | POk (x, st', c1) -> (
      match f x st' with
      | POk (y, st'', c2) -> POk (y, st'', c1 || c2)
      | PFail (pos, msg, c2) -> PFail (pos, msg, c1 || c2))

let ( let* ) = bind
let ( >>= ) = bind

let map (f : 'a -> 'b) (p : 'a t) : 'b t =
 fun st ->
  match p st with POk (x, st', c) -> POk (f x, st', c) | PFail _ as e -> e

let ( >>| ) p f = map f p
let seq (p : 'a t) (q : 'b t) : 'b t = bind p (fun _ -> q)
let ( *> ) = seq

let seq_l (p : 'a t) (q : 'b t) : 'a t =
 fun st ->
  match p st with
  | PFail _ as e -> e
  | POk (x, st', c1) -> (
      match q st' with
      | POk (_, st'', c2) -> POk (x, st'', c1 || c2)
      | PFail (pos, msg, c2) -> PFail (pos, msg, c1 || c2))

let ( <* ) = seq_l

(* Choice: try [p]; if it fails *without consuming*, try [q].
   When both alternatives fail non-committing, keep the error from the
   one whose position is furthest — matching Parsec's error-merge rule so
   the most informative diagnostic survives. *)
let or_ (p : 'a t) (q : 'a t) : 'a t =
 fun st ->
  match p st with
  | POk _ as r -> r
  | PFail (_, _, true) as e -> e
  | PFail (p1, m1, false) -> (
      match q st with
      | POk _ as r -> r
      | PFail (p2, m2, c2) ->
          if Pos.compare p1 p2 > 0 then PFail (p1, m1, c2)
          else PFail (p2, m2, c2))

let ( <|> ) = or_

let choice (ps : 'a t list) : 'a t =
  List.fold_right ( <|> ) ps (fail "no alternatives matched")

(* try_: rewind input on failure so the alternative may run. *)
let try_ (p : 'a t) : 'a t =
 fun st ->
  match p st with
  | POk _ as r -> r
  | PFail (_, _, false) as e -> e
  | PFail (pos, msg, true) -> PFail (pos, msg, false)

(* --- input inspection --- *)

let eof : unit t =
 fun st ->
  if st.ofs >= String.length st.src then POk ((), st, false)
  else PFail (st.pos, lazy "expected end of input", false)

let peek_char : char option t =
 fun st ->
  if st.ofs >= String.length st.src then POk (None, st, false)
  else POk (Some st.src.[st.ofs], st, false)

let any_char : char t =
 fun st ->
  if st.ofs >= String.length st.src then
    PFail (st.pos, lazy "unexpected end of input", false)
  else
    let c = st.src.[st.ofs] in
    POk (c, { st with ofs = st.ofs + 1; pos = Pos.advance st.pos c }, true)

let satisfy (f : char -> bool) : char t =
 fun st ->
  if st.ofs >= String.length st.src then
    PFail (st.pos, lazy "unexpected end of input", false)
  else
    let c = st.src.[st.ofs] in
    if f c then
      POk (c, { st with ofs = st.ofs + 1; pos = Pos.advance st.pos c }, true)
    else PFail (st.pos, lazy (Printf.sprintf "unexpected character %C" c), false)

let char (c : char) : char t =
 fun st ->
  if st.ofs >= String.length st.src then
    PFail
      (st.pos, lazy (Printf.sprintf "expected %C, got end of input" c), false)
  else if st.src.[st.ofs] = c then
    POk (c, { st with ofs = st.ofs + 1; pos = Pos.advance st.pos c }, true)
  else
    PFail
      ( st.pos,
        lazy (Printf.sprintf "expected %C, got %C" c st.src.[st.ofs]),
        false )

let expect_char (c : char) : unit t = char c *> return ()

let one_of (chars : string) : char t =
  satisfy (fun c -> String.contains chars c)

let none_of (chars : string) : char t =
  satisfy (fun c -> not (String.contains chars c))

let advance_range (_src : string) (start : int) (stop : int) (pos : pos) : pos =
  Pos.advance_by pos (stop - start)

let starts_with (lit : string) : bool t =
 fun st -> POk (Strings.has_prefix_at st.src st.ofs lit, st, false)

(* Match a literal multi-character string. Atomic: either fully consumes
   the prefix or fully rewinds (Parsec's [string] is partially consuming,
   but for the rest of the parser we want atomicity). *)
let string (lit : string) : string t =
 fun st ->
  let n = String.length lit in
  if st.ofs + n > String.length st.src then
    PFail (st.pos, lazy (Printf.sprintf "expected %S" lit), false)
  else if Strings.has_prefix_at st.src st.ofs lit then begin
    let stop = st.ofs + n in
    let pos = Pos.advance_by st.pos n in
    POk (lit, { st with ofs = stop; pos }, n > 0)
  end
  else PFail (st.pos, lazy (Printf.sprintf "expected %S" lit), false)

let expect_string (s : string) : unit t = string s *> return ()

let take_while (f : char -> bool) : string t =
 fun st ->
  let len = String.length st.src in
  let i = ref st.ofs in
  while !i < len && f st.src.[!i] do
    incr i
  done;
  let pos = advance_range st.src st.ofs !i st.pos in
  POk
    ( String.sub st.src st.ofs (!i - st.ofs),
      { st with ofs = !i; pos },
      !i > st.ofs )

let take_while1 (f : char -> bool) : string t =
 fun st ->
  match take_while f st with
  | POk ("", _, _) -> PFail (st.pos, lazy "expected matching character", false)
  | POk (s, st', _) -> POk (s, st', true)
  | PFail _ as e -> e

let skip_while (f : char -> bool) : unit t =
 fun st ->
  match take_while f st with
  | POk (_, st', consumed) -> POk ((), st', consumed)
  | PFail _ as e -> e

let scan (s0 : 's) ~(step : 's -> char -> 's option) ~(accept : 's -> bool) :
    string t =
 fun st ->
  let src = st.src in
  let len = String.length src in
  let start = st.ofs in
  let rec loop s ofs pos =
    if ofs >= len then (s, ofs, pos)
    else
      let c = String.unsafe_get src ofs in
      match step s c with
      | Some s' -> loop s' (ofs + 1) (Pos.advance pos c)
      | None -> (s, ofs, pos)
  in
  let s1, ofs', pos' = loop s0 start st.pos in
  if accept s1 then
    POk
      ( String.sub src start (ofs' - start),
        { st with ofs = ofs'; pos = pos' },
        ofs' > st.ofs )
  else PFail (st.pos, lazy "expected matching character", false)

(* --- repetition --- *)

let many (p : 'a t) : 'a list t =
 fun st0 ->
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

let skip_many (p : 'a t) : unit t =
 fun st0 ->
  let rec loop st consumed =
    match p st with
    | PFail (_, _, false) -> POk ((), st, consumed)
    | PFail _ as e -> e
    | POk (_, st', c) -> loop st' (consumed || c)
  in
  loop st0 false

let optional (p : 'a t) : unit t =
 fun st ->
  match p st with
  | POk (_, st', c) -> POk ((), st', c)
  | PFail (_, _, false) -> POk ((), st, false)
  | PFail _ as e -> e

let option_maybe (p : 'a t) : 'a option t =
 fun st ->
  match p st with
  | POk (x, st', c) -> POk (Some x, st', c)
  | PFail (_, _, false) -> POk (None, st, false)
  | PFail _ as e -> e

(* Greedy character-mode "manyTill any-char (string terminator)". Used for
   verbatim and comment scanning. The terminator is consumed too. *)
let many_till_chars (terminator : string) : string t =
 fun st0 ->
  let n = String.length terminator in
  let len = String.length st0.src in
  let rec find ofs =
    if ofs > len - n then None
    else if Strings.has_prefix_at st0.src ofs terminator then Some ofs
    else find (ofs + 1)
  in
  match find st0.ofs with
  | None ->
      PFail (st0.pos, lazy (Printf.sprintf "expected %S" terminator), false)
  | Some end_ofs ->
      let after_term = end_ofs + n in
      let pos = advance_range st0.src st0.ofs after_term st0.pos in
      POk
        ( String.sub st0.src st0.ofs (end_ofs - st0.ofs),
          { st0 with ofs = after_term; pos },
          true )

(* --- lookahead and position --- *)

let look_ahead (p : 'a t) : 'a t =
 fun st ->
  match p st with
  | POk (x, _, _) -> POk (x, st, false)
  | PFail (pos, msg, _) -> PFail (pos, msg, false)

let get_position : pos t = fun st -> POk (st.pos, st, false)

(* --- entry point --- *)

let run (p : 'a t) ~source_name (input : string) : ('a, parse_error) result =
  let st = { src = input; source_name; ofs = 0; pos = Pos.initial } in
  match p st with
  | POk (x, _, _) -> Ok x
  | PFail (pos, msg, _) ->
      Error
        {
          pe_source_name = source_name;
          pe_pos = pos;
          pe_message = Lazy.force msg;
        }
