(* Small reusable helpers for recovery-friendly syntax highlighting. *)

type span = { span_role : Document.highlight_role option; span_text : Text.t }
type scanner = { input : string; start : int; stop : int; mutable pos : int }

let scanner_of_text text =
  let input, start, len = Text.to_substr text in
  { input; start; stop = start + len; pos = start }

let scanner_of_string input =
  { input; start = 0; stop = String.length input; pos = 0 }

let position sc = sc.pos
let offset sc = sc.pos - sc.start
let is_eof sc = sc.pos >= sc.stop

let peek sc =
  if is_eof sc then None else Some (String.unsafe_get sc.input sc.pos)

let peek_n sc n =
  let pos = sc.pos + n in
  if pos < sc.start || pos >= sc.stop then None
  else Some (String.unsafe_get sc.input pos)

let advance sc n = sc.pos <- min sc.stop (sc.pos + max 0 n)

let bump sc =
  match peek sc with
  | None -> None
  | Some c ->
      advance sc 1;
      Some c

let starts_with sc pat =
  let len = String.length pat in
  sc.pos + len <= sc.stop
  &&
  let rec go i =
    i = len
    || String.unsafe_get sc.input (sc.pos + i) = String.unsafe_get pat i
       && go (i + 1)
  in
  go 0

let slice sc start stop = Text.of_substr sc.input start (stop - start)
let slice_string sc start stop = String.sub sc.input start (stop - start)

let span ?span_role sc start stop =
  { span_role; span_text = slice sc start stop }

let consume_while sc pred =
  let start = sc.pos in
  while (not (is_eof sc)) && pred (String.unsafe_get sc.input sc.pos) do
    advance sc 1
  done;
  (start, sc.pos)

let consume_identifier sc ~is_start ~is_part =
  let start = sc.pos in
  match peek sc with
  | Some c when is_start c ->
      advance sc 1;
      ignore (consume_while sc is_part);
      (start, sc.pos)
  | _ -> (start, start)

let is_newline = function '\n' | '\r' -> true | _ -> false

let consume_line_comment sc =
  let start = sc.pos in
  while
    (not (is_eof sc)) && not (is_newline (String.unsafe_get sc.input sc.pos))
  do
    advance sc 1
  done;
  (start, sc.pos)

let consume_block_comment sc =
  let start = sc.pos in
  if starts_with sc "/*" then begin
    advance sc 2;
    let closed = ref false in
    while (not !closed) && not (is_eof sc) do
      if starts_with sc "*/" then begin
        advance sc 2;
        closed := true
      end
      else advance sc 1
    done
  end;
  (start, sc.pos)

let consume_delimited sc ~quote ~allow_newline =
  let start = sc.pos in
  match peek sc with
  | Some c when Char.equal c quote ->
      advance sc 1;
      let done_ = ref false in
      while (not !done_) && not (is_eof sc) do
        match peek sc with
        | Some c when Char.equal c quote ->
            advance sc 1;
            done_ := true
        | Some '\\' ->
            advance sc 1;
            begin match peek sc with
            | Some c when (not allow_newline) && is_newline c -> done_ := true
            | Some _ -> advance sc 1
            | None -> ()
            end
        | Some c when (not allow_newline) && is_newline c -> done_ := true
        | Some _ -> advance sc 1
        | None -> ()
      done;
      (start, sc.pos)
  | _ -> (start, start)

let consume_raw_delimited sc ~quote =
  let start = sc.pos in
  match peek sc with
  | Some c when Char.equal c quote ->
      advance sc 1;
      let closed = ref false in
      while (not !closed) && not (is_eof sc) do
        match peek sc with
        | Some c when Char.equal c quote ->
            advance sc 1;
            closed := true
        | Some _ -> advance sc 1
        | None -> ()
      done;
      (start, sc.pos)
  | _ -> (start, start)

let spans_to_inlines spans =
  let newline = Text.of_char '\n' in
  let make role text =
    match role with
    | None -> Document.Str text
    | Some role -> Document.Highlighted (role, [ Document.Str text ])
  in
  let flush pending acc =
    match pending with
    | None -> acc
    | Some (role, text) -> make role text :: acc
  in
  let append_piece pending acc role text =
    if Text.is_empty text then (pending, acc)
    else
      match pending with
      | Some (prev_role, prev_text) when prev_role = role ->
          (Some (role, Text.append prev_text text), acc)
      | _ -> (Some (role, text), flush pending acc)
  in
  let rec append_split pending acc role = function
    | [] -> (pending, acc)
    | [ text ] -> append_piece pending acc role text
    | text :: rest ->
        let pending, acc = append_piece pending acc role text in
        let pending, acc = append_piece pending acc None newline in
        append_split pending acc role rest
  in
  let rec go pending acc = function
    | [] -> List.rev (flush pending acc)
    | { span_text; _ } :: rest when Text.is_empty span_text ->
        go pending acc rest
    | { span_role; span_text } :: rest ->
        let pending, acc =
          append_split pending acc span_role (Text.split_on span_text "\n")
        in
        go pending acc rest
  in
  go None [] spans

let map_str_chunks highlight_text inlines =
  List.concat
    (List.map
       (function
         | Document.Str text -> highlight_text text | inline -> [ inline ])
       inlines)
