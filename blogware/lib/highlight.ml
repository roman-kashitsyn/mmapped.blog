(* Recovery-friendly syntax highlighting infrastructure. *)

type span = { span_role : Document.highlight_role option; span_text : Text.t }
type scanner = { input : string; start : int; stop : int; mutable pos : int }

let scanner_of_text text =
  let input, start, len = Text.to_substr text in
  { input; start; stop = start + len; pos = start }

let position sc = sc.pos
let is_eof sc = sc.pos >= sc.stop

let peek sc =
  if is_eof sc then None else Some (String.unsafe_get sc.input sc.pos)

let advance sc n = sc.pos <- min sc.stop (sc.pos + max 0 n)

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

let consume_block_comment_with_delims sc ~open_ ~close =
  let start = sc.pos in
  if starts_with sc open_ then begin
    advance sc (String.length open_);
    let closed = ref false in
    while (not !closed) && not (is_eof sc) do
      if starts_with sc close then begin
        advance sc (String.length close);
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

type token_kind =
  | Whitespace
  | Ident
  | Keyword
  | Comment
  | String
  | Delim
  | Operator
  | Unknown

type token = {
  kind : token_kind;
  text : Text.t;
  lexeme : string;
  mutable role : Document.highlight_role option;
}

type string_rule = { quote : char; allow_newline : bool; raw : bool }
type block_comment_rule = { open_ : string; close : string }

module type LEXICAL = sig
  val line_comments : string list
  val block_comments : block_comment_rule list
  val strings : string_rule list
  val is_whitespace : char -> bool
  val is_ident_start : char -> bool
  val is_ident_part : char -> bool
  val is_delim : char -> bool
  val is_operator_char : char -> bool
end

type segment_style = First_name | Name_list

let default_is_whitespace = function
  | ' ' | '\t' | '\n' | '\r' | '\x0C' -> true
  | _ -> false

let is_ascii_letter = function 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false
let is_digit = function '0' .. '9' -> true | _ -> false

let c_like_ident_start c =
  is_ascii_letter c || Char.equal c '_' || Char.code c >= 128

let c_like_ident_part c = c_like_ident_start c || is_digit c

let c_like_delim = function
  | '(' | ')' | '[' | ']' | '{' | '}' | ',' | ';' -> true
  | _ -> false

let c_like_operator_char = function
  | '+' | '-' | '*' | '/' | '%' | '&' | '|' | '^' | '!' | '~' | '=' | '<' | '>'
  | ':' | '.' | '?' | '@' | '#' | '$' ->
      true
  | _ -> false

module C_like_lexical = struct
  let line_comments = [ "//" ]
  let block_comments = [ { open_ = "/*"; close = "*/" } ]

  let strings =
    [
      { quote = '"'; allow_newline = false; raw = false };
      { quote = '\''; allow_newline = false; raw = false };
    ]

  let is_whitespace = default_is_whitespace
  let is_ident_start = c_like_ident_start
  let is_ident_part = c_like_ident_part
  let is_delim = c_like_delim
  let is_operator_char = c_like_operator_char
end

module Go_lexical = struct
  include C_like_lexical

  let strings =
    { quote = '`'; allow_newline = true; raw = true } :: C_like_lexical.strings
end

let make_keyword_set keywords =
  let table = Hashtbl.create (List.length keywords) in
  List.iter (fun kw -> Hashtbl.replace table kw ()) keywords;
  fun word -> Hashtbl.mem table word

let make_token sc kind start stop =
  {
    kind;
    text = slice sc start stop;
    lexeme = slice_string sc start stop;
    role = None;
  }

module Lexer (Lexical : LEXICAL) = struct
  let lex_text is_keyword text =
    let sc = scanner_of_text text in
    let rec go acc =
      if is_eof sc then List.rev acc
      else
        let start = position sc in
        match peek sc with
        | Some c when Lexical.is_whitespace c ->
            let _, stop = consume_while sc Lexical.is_whitespace in
            go (make_token sc Whitespace start stop :: acc)
        | _ when List.exists (starts_with sc) Lexical.line_comments ->
            let _, stop = consume_line_comment sc in
            go (make_token sc Comment start stop :: acc)
        | _ -> (
            match
              List.find_opt
                (fun rule -> starts_with sc rule.open_)
                Lexical.block_comments
            with
            | Some rule ->
                let _, stop =
                  consume_block_comment_with_delims sc ~open_:rule.open_
                    ~close:rule.close
                in
                go (make_token sc Comment start stop :: acc)
            | None -> (
                match
                  List.find_opt
                    (fun rule ->
                      match peek sc with
                      | Some c -> Char.equal c rule.quote
                      | None -> false)
                    Lexical.strings
                with
                | Some rule ->
                    let _, stop =
                      if rule.raw then
                        consume_raw_delimited sc ~quote:rule.quote
                      else
                        consume_delimited sc ~quote:rule.quote
                          ~allow_newline:rule.allow_newline
                    in
                    go (make_token sc String start stop :: acc)
                | None -> (
                    match peek sc with
                    | Some c when Lexical.is_ident_start c ->
                        let _, stop =
                          consume_identifier sc ~is_start:Lexical.is_ident_start
                            ~is_part:Lexical.is_ident_part
                        in
                        let lexeme = slice_string sc start stop in
                        let kind =
                          if is_keyword lexeme then Keyword else Ident
                        in
                        go (make_token sc kind start stop :: acc)
                    | Some c when Lexical.is_delim c ->
                        advance sc 1;
                        go (make_token sc Delim start (position sc) :: acc)
                    | Some c when Lexical.is_operator_char c ->
                        let _, stop =
                          consume_while sc Lexical.is_operator_char
                        in
                        go (make_token sc Operator start stop :: acc)
                    | Some _ ->
                        advance sc 1;
                        go (make_token sc Unknown start (position sc) :: acc)
                    | None -> List.rev acc)))
    in
    go []
end

let is_trivia t = match t.kind with Whitespace | Comment -> true | _ -> false
let is_ident t = match t.kind with Ident -> true | _ -> false
let text_is t s = String.equal t.lexeme s

let token_has_newline t =
  String.exists (function '\n' | '\r' -> true | _ -> false) t.lexeme

let mark role t =
  match t.kind with Ident | Keyword -> t.role <- Some role | _ -> ()

let set_base_role t =
  match t.kind with
  | Keyword -> t.role <- Some Hl_keyword
  | Comment -> t.role <- Some Hl_comment
  | String -> t.role <- Some Hl_string
  | _ -> ()

let next_sig_from tokens i =
  let n = Array.length tokens in
  let rec go j =
    if j >= n then None else if is_trivia tokens.(j) then go (j + 1) else Some j
  in
  go i

let next_sig tokens i = next_sig_from tokens (i + 1)

let prev_sig tokens i =
  let rec go j =
    if j < 0 then None else if is_trivia tokens.(j) then go (j - 1) else Some j
  in
  go (i - 1)

let matching_forward tokens open_idx open_text close_text =
  let n = Array.length tokens in
  let rec go depth i =
    if i >= n then None
    else
      let t = tokens.(i) in
      if text_is t open_text then go (depth + 1) (i + 1)
      else if text_is t close_text then
        if depth = 1 then Some i else go (depth - 1) (i + 1)
      else go depth (i + 1)
  in
  if open_idx < n && text_is tokens.(open_idx) open_text then go 0 open_idx
  else None

let balanced_from tokens i open_text close_text =
  match next_sig_from tokens i with
  | Some open_idx when text_is tokens.(open_idx) open_text -> (
      match matching_forward tokens open_idx open_text close_text with
      | Some close_idx -> Some (open_idx, close_idx, close_idx + 1)
      | None -> None)
  | _ -> None

let mark_next_ident tokens role i =
  match next_sig_from tokens i with
  | Some id when is_ident tokens.(id) ->
      mark role tokens.(id);
      Some (id + 1)
  | _ -> None

let is_open = function "(" | "[" | "{" | "<" -> true | _ -> false
let is_close = function ")" | "]" | "}" | ">" -> true | _ -> false

let step_depth depth t =
  if is_open t.lexeme then depth + 1
  else if is_close t.lexeme then max 0 (depth - 1)
  else depth

let find_top_level_comma_or_end tokens start stop =
  let rec go depth i =
    if i >= stop then i
    else
      let t = tokens.(i) in
      if depth = 0 && text_is t "," then i else go (step_depth depth t) (i + 1)
  in
  go 0 start

let segment_boundaries tokens start stop =
  let rec loop seg_start i depth acc =
    if i >= stop then List.rev ((seg_start, stop) :: acc)
    else
      let t = tokens.(i) in
      if depth = 0 && (text_is t ";" || token_has_newline t) then
        loop (i + 1) (i + 1) 0 ((seg_start, i) :: acc)
      else loop seg_start (i + 1) (step_depth depth t) acc
  in
  loop start start 0 []

let mark_first_name tokens role start stop =
  match next_sig_from tokens start with
  | Some i when i < stop && is_ident tokens.(i) -> mark role tokens.(i)
  | _ -> ()

let mark_name_list tokens role start stop =
  match next_sig_from tokens start with
  | Some i when i < stop && is_ident tokens.(i) ->
      mark role tokens.(i);
      let rec go last_id =
        match next_sig tokens last_id with
        | Some comma when comma < stop && text_is tokens.(comma) "," -> (
            match next_sig tokens comma with
            | Some id when id < stop && is_ident tokens.(id) ->
                mark role tokens.(id);
                go id
            | _ -> ())
        | _ -> ()
      in
      go i
  | _ -> ()

let mark_segment tokens style role start stop =
  match style with
  | First_name -> mark_first_name tokens role start stop
  | Name_list -> mark_name_list tokens role start stop

let mark_go_field_vars tokens open_idx close_idx role =
  let rec parse_field i =
    match next_sig_from tokens i with
    | None -> ()
    | Some i when i >= close_idx -> ()
    | Some i ->
        let field_end =
          match tokens.(i).kind with
          | Ident ->
              let rec collect_names names last_id =
                match next_sig tokens last_id with
                | Some comma
                  when comma < close_idx && text_is tokens.(comma) "," -> (
                    match next_sig tokens comma with
                    | Some id when id < close_idx && is_ident tokens.(id) ->
                        collect_names (id :: names) id
                    | _ -> (List.rev names, None))
                | Some j when j < close_idx -> (List.rev names, Some j)
                | _ -> (List.rev names, None)
              in
              let names, type_start = collect_names [ i ] i in
              begin match type_start with
              | Some j when not (text_is tokens.(j) ".") ->
                  List.iter (fun idx -> mark role tokens.(idx)) names;
                  find_top_level_comma_or_end tokens j close_idx
              | _ -> find_top_level_comma_or_end tokens i close_idx
              end
          | _ -> find_top_level_comma_or_end tokens i close_idx
        in
        parse_field (field_end + 1)
  in
  parse_field (open_idx + 1)

let mark_colon_field_vars tokens open_idx close_idx role =
  let mark_segment start stop =
    match next_sig_from tokens start with
    | Some mut when mut < stop && text_is tokens.(mut) "mut" -> (
        match next_sig tokens mut with
        | Some id when id < stop && is_ident tokens.(id) ->
            mark role tokens.(id)
        | _ -> ())
    | Some id when id < stop && is_ident tokens.(id) -> mark role tokens.(id)
    | _ -> ()
  in
  let rec loop seg_start i depth =
    if i >= close_idx then mark_segment seg_start close_idx
    else
      let t = tokens.(i) in
      if depth = 0 && text_is t "," then begin
        mark_segment seg_start i;
        loop (i + 1) (i + 1) 0
      end
      else loop seg_start (i + 1) (step_depth depth t)
  in
  loop (open_idx + 1) (open_idx + 1) 0

let mark_c_field_vars tokens open_idx close_idx role =
  let mark_segment start stop =
    let last_ident = ref None in
    let rec loop depth i =
      if i >= stop then ()
      else
        let t = tokens.(i) in
        if depth = 0 && is_ident t then last_ident := Some i;
        loop (step_depth depth t) (i + 1)
    in
    loop 0 start;
    match !last_ident with Some idx -> mark role tokens.(idx) | None -> ()
  in
  let rec loop seg_start i depth =
    if i >= close_idx then mark_segment seg_start close_idx
    else
      let t = tokens.(i) in
      if depth = 0 && text_is t "," then begin
        mark_segment seg_start i;
        loop (i + 1) (i + 1) 0
      end
      else loop seg_start (i + 1) (step_depth depth t)
  in
  loop (open_idx + 1) (open_idx + 1) 0

let statement_boundary_before tokens i =
  match prev_sig tokens i with
  | None -> -1
  | Some j ->
      let rec go j =
        if j < 0 then -1
        else
          let t = tokens.(j) in
          if
            token_has_newline t || text_is t ";" || text_is t "{"
            || text_is t "}" || text_is t "("
          then j
          else
            match t.kind with
            | Keyword
              when List.exists (text_is t)
                     [ "if"; "for"; "switch"; "select"; "case"; "match" ] ->
                j
            | _ -> go (j - 1)
      in
      go j

let mark_short_decl_lhs tokens op_idx role =
  let start = statement_boundary_before tokens op_idx + 1 in
  let mark_segment a b =
    let ident_count = ref 0 in
    let ident_idx = ref None in
    let depth = ref 0 in
    for i = a to b - 1 do
      let t = tokens.(i) in
      if !depth = 0 && is_ident t then begin
        incr ident_count;
        ident_idx := Some i
      end;
      depth := step_depth !depth t
    done;
    match (!ident_count, !ident_idx) with
    | 1, Some idx -> mark role tokens.(idx)
    | _ -> ()
  in
  let rec loop seg_start i depth =
    if i >= op_idx then mark_segment seg_start op_idx
    else
      let t = tokens.(i) in
      if depth = 0 && text_is t "," then begin
        mark_segment seg_start i;
        loop (i + 1) (i + 1) 0
      end
      else loop seg_start (i + 1) (step_depth depth t)
  in
  loop start start 0

let find_statement_stop tokens start =
  let n = Array.length tokens in
  let rec go i =
    if i >= n then n
    else
      let t = tokens.(i) in
      if text_is t ";" || text_is t "}" || token_has_newline t then i
      else go (i + 1)
  in
  go start

let apply_decl_segments tokens open_ close style role i =
  match next_sig_from tokens i with
  | Some open_idx when text_is tokens.(open_idx) open_ -> (
      match matching_forward tokens open_idx open_ close with
      | None -> None
      | Some close_idx ->
          List.iter
            (fun (start, stop) -> mark_segment tokens style role start stop)
            (segment_boundaries tokens (open_idx + 1) close_idx);
          Some (close_idx + 1))
  | _ -> None

let apply_decl_until_boundary tokens style role i =
  match next_sig_from tokens i with
  | Some start ->
      let stop = find_statement_stop tokens start in
      mark_segment tokens style role start stop;
      Some stop
  | None -> None

let apply_decl_choice tokens style role i =
  match apply_decl_segments tokens "(" ")" style role i with
  | Some _ -> ()
  | None -> ignore (apply_decl_until_boundary tokens style role i)

let find_top_level tokens start delim =
  let n = Array.length tokens in
  let rec go depth i =
    if i >= n then None
    else
      let t = tokens.(i) in
      if depth = 0 && text_is t delim then Some i
      else go (step_depth depth t) (i + 1)
  in
  go 0 start

let first_top_level_token tokens start stop =
  let rec go depth i =
    if i >= stop then None
    else
      let t = tokens.(i) in
      if depth = 0 && not (is_trivia t) then Some i
      else go (step_depth depth t) (i + 1)
  in
  go 0 start

let mark_ocaml_value_pattern tokens role start stop =
  let rec loop depth i =
    if i >= stop then ()
    else
      let t = tokens.(i) in
      if depth = 0 && text_is t ":" then ()
      else begin
        if depth = 0 && is_ident t then mark role t;
        loop (step_depth depth t) (i + 1)
      end
  in
  loop 0 start

let apply_ocaml_value_binding tokens variable_role defun_role i =
  match next_sig_from tokens i with
  | Some name_idx when is_ident tokens.(name_idx) -> (
      match find_top_level tokens (name_idx + 1) "=" with
      | None -> None
      | Some eq_idx ->
          begin match first_top_level_token tokens (name_idx + 1) eq_idx with
          | None -> mark variable_role tokens.(name_idx)
          | Some j when text_is tokens.(j) "," || text_is tokens.(j) ":" ->
              mark_ocaml_value_pattern tokens variable_role name_idx eq_idx
          | Some _ -> mark defun_role tokens.(name_idx)
          end;
          Some (eq_idx + 1))
  | _ -> None

let previous_allows_c_function_name tokens name_idx =
  match prev_sig tokens name_idx with
  | Some prev when text_is tokens.(prev) "." || text_is tokens.(prev) "->" ->
      false
  | Some prev when text_is tokens.(prev) "#" -> false
  | _ -> true

let apply_c_function_definition tokens defun_role parameter_role i =
  match next_sig_from tokens i with
  | Some name_idx
    when is_ident tokens.(name_idx)
         && previous_allows_c_function_name tokens name_idx -> (
      match next_sig tokens name_idx with
      | Some open_idx when text_is tokens.(open_idx) "(" -> (
          match matching_forward tokens open_idx "(" ")" with
          | Some close_idx -> (
              match next_sig tokens close_idx with
              | Some body_idx when text_is tokens.(body_idx) "{" ->
                  mark defun_role tokens.(name_idx);
                  mark_c_field_vars tokens open_idx close_idx parameter_role;
                  Some (body_idx + 1)
              | _ -> None)
          | None -> None)
      | _ -> None)
  | _ -> None

let find_c_function_pointer_typedef tokens start stop =
  let rec loop i =
    if i + 3 >= stop then None
    else if
      text_is tokens.(i) "("
      && text_is tokens.(i + 1) "*"
      && is_ident tokens.(i + 2)
      && text_is tokens.(i + 3) ")"
    then Some (i + 2)
    else loop (i + 1)
  in
  loop start

let apply_c_typedef_declaration tokens role i =
  match find_top_level tokens i ";" with
  | None -> None
  | Some stop ->
      let last_top_level_ident = ref None in
      let rec loop depth j =
        if j >= stop then ()
        else
          let t = tokens.(j) in
          if depth = 0 && is_ident t then last_top_level_ident := Some j;
          loop (step_depth depth t) (j + 1)
      in
      loop 0 i;
      begin match !last_top_level_ident with
      | Some idx -> mark role tokens.(idx)
      | None -> (
          match find_c_function_pointer_typedef tokens i stop with
          | Some idx -> mark role tokens.(idx)
          | None -> ())
      end;
      Some (stop + 1)

let spans_of_tokens tokens =
  List.map
    (fun t -> { span_role = t.role; span_text = t.text })
    (Array.to_list tokens)

module type LANGUAGE = sig
  val keywords : string list

  module Lexical : LEXICAL

  val classify : token array -> unit
end

module Make (Lang : LANGUAGE) = struct
  module Lex = Lexer (Lang.Lexical)

  let is_keyword = make_keyword_set Lang.keywords

  let classify tokens =
    let arr = Array.of_list tokens in
    Array.iter set_base_role arr;
    Lang.classify arr;
    Array.iter
      (fun t ->
        if t.kind = Ident && Option.is_none t.role then
          t.role <- Some Hl_identifier)
      arr;
    arr

  let is_line_comment t =
    t.kind = Comment
    && List.exists
         (fun prefix -> String.starts_with ~prefix t.lexeme)
         Lang.Lexical.line_comments

  let is_unclosed_block_comment t =
    t.kind = Comment
    && List.exists
         (fun rule ->
           String.starts_with ~prefix:rule.open_ t.lexeme
           && not (String.ends_with ~suffix:rule.close t.lexeme))
         Lang.Lexical.block_comments

  let split_trailing_open_comment tokens =
    match List.rev tokens with
    | t :: rest when is_line_comment t || is_unclosed_block_comment t ->
        let mode = if is_line_comment t then `Line else `Block in
        Some (List.rev rest, mode, t.text)
    | _ -> None

  let inlines_of_tokens tokens =
    tokens |> classify |> spans_of_tokens |> spans_to_inlines

  let comment_inline body = Document.Highlighted (Hl_comment, List.rev body)

  let flush_comment body acc =
    match body with [] -> acc | _ -> comment_inline body :: acc

  let split_text_once text sep =
    match Text.str_index text sep with
    | None -> None
    | Some i ->
        let left, rest = Text.split_at text i in
        let _, right = Text.split_at rest (String.length sep) in
        Some (left, right)

  let first_block_close () =
    match Lang.Lexical.block_comments with
    | [] -> None
    | rule :: _ -> Some rule.close

  let rec take_str_chunks text = function
    | Document.Str next :: rest -> take_str_chunks (Text.append text next) rest
    | rest -> (text, rest)

  let rec highlight_normal acc = function
    | [] -> List.rev acc
    | Document.Str text :: rest -> (
        let text, rest = take_str_chunks text rest in
        let tokens = Lex.lex_text is_keyword text in
        match split_trailing_open_comment tokens with
        | None ->
            highlight_normal
              (List.rev_append (inlines_of_tokens tokens) acc)
              rest
        | Some (prefix_tokens, `Line, comment) ->
            let acc = List.rev_append (inlines_of_tokens prefix_tokens) acc in
            highlight_line_comment [ Document.Str comment ] acc rest
        | Some (prefix_tokens, `Block, comment) ->
            let acc = List.rev_append (inlines_of_tokens prefix_tokens) acc in
            highlight_block_comment [ Document.Str comment ] acc rest)
    | inline :: rest -> highlight_normal (inline :: acc) rest

  and highlight_line_comment body acc = function
    | [] -> List.rev (flush_comment body acc)
    | Document.Str text :: rest -> (
        match Text.split_once_by is_newline text with
        | before_newline, after_newline when Text.is_empty after_newline ->
            highlight_line_comment
              (Document.Str before_newline :: body)
              acc rest
        | before_newline, after_newline ->
            let newline, suffix = Text.split_at after_newline 1 in
            let acc =
              comment_inline (Document.Str before_newline :: body) :: acc
            in
            highlight_normal
              (Document.Str newline :: acc)
              (Document.Str suffix :: rest))
    | inline :: rest -> highlight_line_comment (inline :: body) acc rest

  and highlight_block_comment body acc rest =
    match first_block_close () with
    | None -> List.rev (flush_comment body acc)
    | Some close -> (
        match rest with
        | [] -> List.rev (flush_comment body acc)
        | Document.Str text :: rest -> (
            match split_text_once text close with
            | None -> (
                match Text.split_once_by is_newline text with
                | _, after when Text.is_empty after ->
                    highlight_block_comment (Document.Str text :: body) acc rest
                | before, after ->
                    let newline, suffix = Text.split_at after 1 in
                    let acc =
                      comment_inline (Document.Str before :: body) :: acc
                    in
                    let acc = Document.Str newline :: acc in
                    highlight_block_comment [ Document.Str suffix ] acc rest)
            | Some (before_close, suffix) ->
                let comment_text =
                  Text.append before_close (Text.of_string close)
                in
                let acc =
                  comment_inline (Document.Str comment_text :: body) :: acc
                in
                highlight_normal acc (Document.Str suffix :: rest))
        | inline :: rest -> highlight_block_comment (inline :: body) acc rest)

  let highlight inlines = highlight_normal [] inlines
end

module Go = Make (struct
  let keywords =
    [
      "break";
      "default";
      "func";
      "interface";
      "select";
      "case";
      "defer";
      "go";
      "map";
      "struct";
      "chan";
      "else";
      "goto";
      "package";
      "switch";
      "const";
      "fallthrough";
      "if";
      "range";
      "type";
      "continue";
      "for";
      "import";
      "return";
      "var";
    ]

  module Lexical = Go_lexical

  let mark_params tokens (open_idx, close_idx, _) =
    mark_go_field_vars tokens open_idx close_idx Hl_variable

  let group_next (_, _, next) = next

  let classify_func tokens i =
    let receiver, name_start =
      match balanced_from tokens (i + 1) "(" ")" with
      | Some (_, _, next) as receiver -> (receiver, next)
      | None -> (None, i + 1)
    in
    match next_sig_from tokens name_start with
    | Some name_idx when is_ident tokens.(name_idx) -> (
        match balanced_from tokens (name_idx + 1) "(" ")" with
        | Some params ->
            Option.iter (mark_params tokens) receiver;
            mark Hl_defun tokens.(name_idx);
            mark_params tokens params;
            begin match balanced_from tokens (group_next params) "(" ")" with
            | Some returns -> mark_params tokens returns
            | None -> ()
            end;
            true
        | None -> false)
    | _ -> false

  let classify_func_literal tokens i =
    match balanced_from tokens (i + 1) "(" ")" with
    | Some params ->
        mark_params tokens params;
        begin match balanced_from tokens (group_next params) "(" ")" with
        | Some returns -> mark_params tokens returns
        | None -> ()
        end
    | None -> ()

  let classify tokens =
    Array.iteri
      (fun i t ->
        match (t.kind, t.lexeme) with
        | Keyword, "func" ->
            if not (classify_func tokens i) then classify_func_literal tokens i
        | Keyword, "type" ->
            apply_decl_choice tokens First_name Hl_typedef (i + 1)
        | Keyword, ("var" | "const") ->
            apply_decl_choice tokens Name_list Hl_variable (i + 1)
        | Operator, ":=" -> mark_short_decl_lhs tokens i Hl_variable
        | _ -> ())
      tokens
end)

module C = Make (struct
  let keywords =
    [
      "_Alignas";
      "_Alignof";
      "_Atomic";
      "_Bool";
      "_Complex";
      "_Generic";
      "_Imaginary";
      "_Noreturn";
      "_Static_assert";
      "_Thread_local";
      "auto";
      "break";
      "case";
      "char";
      "const";
      "continue";
      "default";
      "do";
      "double";
      "else";
      "enum";
      "extern";
      "float";
      "for";
      "goto";
      "if";
      "inline";
      "int";
      "long";
      "register";
      "restrict";
      "return";
      "short";
      "signed";
      "sizeof";
      "static";
      "struct";
      "switch";
      "typedef";
      "union";
      "unsigned";
      "void";
      "volatile";
      "while";
    ]

  module Lexical = C_like_lexical

  let classify tokens =
    Array.iteri
      (fun i t ->
        match (t.kind, t.lexeme) with
        | Ident, _ ->
            ignore (apply_c_function_definition tokens Hl_defun Hl_variable i)
        | Keyword, "typedef" ->
            ignore (apply_c_typedef_declaration tokens Hl_typedef (i + 1))
        | Keyword, ("struct" | "union" | "enum") ->
            ignore (mark_next_ident tokens Hl_typedef (i + 1))
        | _ -> ())
      tokens
end)

module Rust = Make (struct
  let keywords =
    [
      "as";
      "async";
      "await";
      "break";
      "const";
      "continue";
      "crate";
      "dyn";
      "else";
      "enum";
      "extern";
      "false";
      "fn";
      "for";
      "if";
      "impl";
      "in";
      "let";
      "loop";
      "match";
      "mod";
      "move";
      "mut";
      "pub";
      "ref";
      "return";
      "self";
      "Self";
      "static";
      "struct";
      "super";
      "trait";
      "true";
      "type";
      "unsafe";
      "use";
      "where";
      "while";
    ]

  module Lexical = struct
    include C_like_lexical

    let strings = [ { quote = '"'; allow_newline = false; raw = false } ]
  end

  let classify_fn tokens i =
    match next_sig_from tokens (i + 1) with
    | Some name_idx when is_ident tokens.(name_idx) ->
        let params_start =
          match balanced_from tokens (name_idx + 1) "<" ">" with
          | Some (_, _, next) -> next
          | None -> name_idx + 1
        in
        begin match balanced_from tokens params_start "(" ")" with
        | Some (open_idx, close_idx, _) ->
            mark Hl_defun tokens.(name_idx);
            mark_colon_field_vars tokens open_idx close_idx Hl_variable
        | None -> ()
        end
    | _ -> ()

  let classify_let tokens i =
    let name_start =
      match next_sig_from tokens (i + 1) with
      | Some mut when tokens.(mut).kind = Keyword && text_is tokens.(mut) "mut"
        ->
          mut + 1
      | _ -> i + 1
    in
    ignore (mark_next_ident tokens Hl_variable name_start)

  let classify tokens =
    Array.iteri
      (fun i t ->
        match (t.kind, t.lexeme) with
        | Keyword, "fn" -> classify_fn tokens i
        | Keyword, "let" -> classify_let tokens i
        | Keyword, ("struct" | "enum" | "trait" | "type") ->
            ignore (mark_next_ident tokens Hl_typedef (i + 1))
        | _ -> ())
      tokens
end)

module OCaml = Make (struct
  let keywords =
    [
      "and";
      "as";
      "assert";
      "begin";
      "class";
      "constraint";
      "do";
      "done";
      "downto";
      "else";
      "end";
      "exception";
      "external";
      "false";
      "for";
      "fun";
      "function";
      "functor";
      "if";
      "in";
      "include";
      "inherit";
      "initializer";
      "lazy";
      "let";
      "match";
      "method";
      "module";
      "mutable";
      "new";
      "nonrec";
      "object";
      "of";
      "open";
      "or";
      "private";
      "rec";
      "sig";
      "struct";
      "then";
      "to";
      "true";
      "try";
      "type";
      "val";
      "virtual";
      "when";
      "while";
      "with";
    ]

  let is_ident_start = function
    | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
    | c -> Char.code c >= 128

  let is_ident_part = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
    | c -> Char.code c >= 128

  let is_delim = function
    | '(' | ')' | '[' | ']' | '{' | '}' | ',' | ';' -> true
    | _ -> false

  let is_operator_char = function
    | '!' | '$' | '%' | '&' | '*' | '+' | '-' | '.' | '/' | ':' | '<' | '='
    | '>' | '?' | '@' | '^' | '|' | '~' | '#' | '\\' ->
        true
    | _ -> false

  module Lexical = struct
    let line_comments = []
    let block_comments = [ { open_ = "(*"; close = "*)" } ]
    let strings = [ { quote = '"'; allow_newline = false; raw = false } ]
    let is_whitespace = default_is_whitespace
    let is_ident_start = is_ident_start
    let is_ident_part = is_ident_part
    let is_delim = is_delim
    let is_operator_char = is_operator_char
  end

  let classify_let tokens i =
    let binding_start =
      match next_sig_from tokens (i + 1) with
      | Some rec_
        when tokens.(rec_).kind = Keyword && text_is tokens.(rec_) "rec" ->
          rec_ + 1
      | _ -> i + 1
    in
    ignore (apply_ocaml_value_binding tokens Hl_variable Hl_defun binding_start)

  let classify_type tokens i =
    let name_start =
      match next_sig_from tokens (i + 1) with
      | Some nonrec_idx
        when tokens.(nonrec_idx).kind = Keyword
             && text_is tokens.(nonrec_idx) "nonrec" ->
          nonrec_idx + 1
      | _ -> i + 1
    in
    ignore (mark_next_ident tokens Hl_typedef name_start)

  let classify tokens =
    Array.iteri
      (fun i t ->
        match (t.kind, t.lexeme) with
        | Keyword, "let" -> classify_let tokens i
        | Keyword, "and" ->
            ignore
              (apply_ocaml_value_binding tokens Hl_variable Hl_defun (i + 1))
        | Keyword, "type" -> classify_type tokens i
        | _ -> ())
      tokens
end)

let has_language name classes =
  List.exists (fun c -> Text.equal_string c name) classes

let highlighters =
  [
    ("go", Go.highlight);
    ("c", C.highlight);
    ("rust", Rust.highlight);
    ("ocaml", OCaml.highlight);
  ]

let highlight ~classes ~content =
  let rec find = function
    | [] -> None
    | (name, hl) :: rest ->
        if has_language name classes then Some hl else find rest
  in
  match find highlighters with Some hl -> hl content | None -> content
