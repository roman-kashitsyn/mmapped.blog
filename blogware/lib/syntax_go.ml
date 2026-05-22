(* Approximate, recovery-friendly Go syntax highlighter. *)

open Document

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
  mutable role : highlight_role option;
}

let make_token sc kind start stop =
  {
    kind;
    text = Highlight.slice sc start stop;
    lexeme = Highlight.slice_string sc start stop;
    role = None;
  }

let keywords =
  let table = Hashtbl.create 32 in
  List.iter
    (fun kw -> Hashtbl.add table kw ())
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
    ];
  table

let is_keyword s = Hashtbl.mem keywords s

let is_whitespace = function
  | ' ' | '\t' | '\n' | '\r' | '\x0C' -> true
  | _ -> false

let is_ascii_letter = function 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false
let is_digit = function '0' .. '9' -> true | _ -> false

let is_ident_start c =
  is_ascii_letter c || Char.equal c '_' || Char.code c >= 128

let is_ident_part c = is_ident_start c || is_digit c

let is_delim = function
  | '(' | ')' | '[' | ']' | '{' | '}' | ',' | ';' -> true
  | _ -> false

let is_operator_char = function
  | '+' | '-' | '*' | '/' | '%' | '&' | '|' | '^' | '!' | '~' | '=' | '<' | '>'
  | ':' | '.' ->
      true
  | _ -> false

let lex_text text =
  let sc = Highlight.scanner_of_text text in
  let rec go acc =
    if Highlight.is_eof sc then List.rev acc
    else
      let start = Highlight.position sc in
      match Highlight.peek sc with
      | Some c when is_whitespace c ->
          let _, stop = Highlight.consume_while sc is_whitespace in
          go (make_token sc Whitespace start stop :: acc)
      | Some '/' when Highlight.starts_with sc "//" ->
          let _, stop = Highlight.consume_line_comment sc in
          go (make_token sc Comment start stop :: acc)
      | Some '/' when Highlight.starts_with sc "/*" ->
          let _, stop = Highlight.consume_block_comment sc in
          go (make_token sc Comment start stop :: acc)
      | Some '"' ->
          let _, stop =
            Highlight.consume_delimited sc ~quote:'"' ~allow_newline:false
          in
          go (make_token sc String start stop :: acc)
      | Some '`' ->
          let _, stop = Highlight.consume_raw_delimited sc ~quote:'`' in
          go (make_token sc String start stop :: acc)
      | Some '\'' ->
          let _, stop =
            Highlight.consume_delimited sc ~quote:'\'' ~allow_newline:false
          in
          go (make_token sc String start stop :: acc)
      | Some c when is_ident_start c ->
          let _, stop =
            Highlight.consume_identifier sc ~is_start:is_ident_start
              ~is_part:is_ident_part
          in
          let lexeme = Highlight.slice_string sc start stop in
          let kind = if is_keyword lexeme then Keyword else Ident in
          go (make_token sc kind start stop :: acc)
      | Some c when is_delim c ->
          Highlight.advance sc 1;
          go (make_token sc Delim start (Highlight.position sc) :: acc)
      | Some c when is_operator_char c ->
          let _, stop = Highlight.consume_while sc is_operator_char in
          go (make_token sc Operator start stop :: acc)
      | Some _ ->
          Highlight.advance sc 1;
          go (make_token sc Unknown start (Highlight.position sc) :: acc)
      | None -> List.rev acc
  in
  go []

let is_trivia t = match t.kind with Whitespace | Comment -> true | _ -> false
let is_ident t = match t.kind with Ident -> true | _ -> false
let text_is t s = String.equal t.lexeme s

let token_has_newline t =
  String.exists (function '\n' | '\r' -> true | _ -> false) t.lexeme

let mark role t = match t.kind with Ident -> t.role <- Some role | _ -> ()

let set_base_role t =
  match t.kind with
  | Keyword -> t.role <- Some Hl_keyword
  | Comment -> t.role <- Some Hl_comment
  | String -> t.role <- Some Hl_string
  | _ -> ()

let next_sig tokens i =
  let n = Array.length tokens in
  let rec go j =
    if j >= n then None else if is_trivia tokens.(j) then go (j + 1) else Some j
  in
  go (i + 1)

let next_sig_from tokens i =
  let n = Array.length tokens in
  let rec go j =
    if j >= n then None else if is_trivia tokens.(j) then go (j + 1) else Some j
  in
  go i

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

let is_open = function "(" | "[" | "{" -> true | _ -> false
let is_close = function ")" | "]" | "}" -> true | _ -> false

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

let mark_param_section_vars tokens open_idx =
  match matching_forward tokens open_idx "(" ")" with
  | None -> None
  | Some close_idx ->
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
                      List.iter (fun idx -> mark Hl_variable tokens.(idx)) names;
                      find_top_level_comma_or_end tokens j close_idx
                  | _ -> find_top_level_comma_or_end tokens i close_idx
                  end
              | _ -> find_top_level_comma_or_end tokens i close_idx
            in
            parse_field (field_end + 1)
      in
      parse_field (open_idx + 1);
      Some close_idx

let mark_decl_segment tokens start stop =
  match next_sig_from tokens start with
  | Some i when i < stop && is_ident tokens.(i) ->
      mark Hl_variable tokens.(i);
      let rec go last_id =
        match next_sig tokens last_id with
        | Some comma when comma < stop && text_is tokens.(comma) "," -> (
            match next_sig tokens comma with
            | Some id when id < stop && is_ident tokens.(id) ->
                mark Hl_variable tokens.(id);
                go id
            | _ -> ())
        | _ -> ()
      in
      go i
  | _ -> ()

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
                     [ "if"; "for"; "switch"; "select"; "case" ] ->
                j
            | _ -> go (j - 1)
      in
      go j

let mark_short_decl_lhs tokens op_idx =
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
    | 1, Some idx -> mark Hl_variable tokens.(idx)
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

let mark_var_or_const_decl tokens kw_idx =
  match next_sig tokens kw_idx with
  | Some open_idx when text_is tokens.(open_idx) "(" -> (
      match matching_forward tokens open_idx "(" ")" with
      | None -> ()
      | Some close_idx ->
          let rec loop seg_start i depth =
            if i >= close_idx then mark_decl_segment tokens seg_start close_idx
            else
              let t = tokens.(i) in
              if depth = 0 && (text_is t ";" || token_has_newline t) then begin
                mark_decl_segment tokens seg_start i;
                loop (i + 1) (i + 1) 0
              end
              else loop seg_start (i + 1) (step_depth depth t)
          in
          loop (open_idx + 1) (open_idx + 1) 0)
  | Some start ->
      let n = Array.length tokens in
      let rec find_stop i =
        if i >= n then n
        else
          let t = tokens.(i) in
          if text_is t ";" || text_is t "}" || token_has_newline t then i
          else find_stop (i + 1)
      in
      mark_decl_segment tokens start (find_stop start)
  | None -> ()

let mark_typedef_segment tokens start stop =
  match next_sig_from tokens start with
  | Some i when i < stop && is_ident tokens.(i) -> mark Hl_typedef tokens.(i)
  | _ -> ()

let mark_type_decl tokens kw_idx =
  match next_sig tokens kw_idx with
  | Some open_idx when text_is tokens.(open_idx) "(" -> (
      match matching_forward tokens open_idx "(" ")" with
      | None -> ()
      | Some close_idx ->
          let rec loop seg_start i depth =
            if i >= close_idx then
              mark_typedef_segment tokens seg_start close_idx
            else
              let t = tokens.(i) in
              if depth = 0 && (text_is t ";" || token_has_newline t) then begin
                mark_typedef_segment tokens seg_start i;
                loop (i + 1) (i + 1) 0
              end
              else loop seg_start (i + 1) (step_depth depth t)
          in
          loop (open_idx + 1) (open_idx + 1) 0)
  | Some start ->
      let n = Array.length tokens in
      let rec find_stop i =
        if i >= n then n
        else
          let t = tokens.(i) in
          if text_is t ";" || text_is t "}" || token_has_newline t then i
          else find_stop (i + 1)
      in
      mark_typedef_segment tokens start (find_stop start)
  | None -> ()

let mark_func_decl tokens kw_idx =
  let mark_func_name name_idx =
    mark Hl_defun tokens.(name_idx);
    match next_sig tokens name_idx with
    | Some open_idx when text_is tokens.(open_idx) "(" -> (
        match mark_param_section_vars tokens open_idx with
        | Some close_idx -> (
            match next_sig tokens close_idx with
            | Some ret_open when text_is tokens.(ret_open) "(" ->
                ignore (mark_param_section_vars tokens ret_open)
            | _ -> ())
        | None -> ())
    | _ -> ()
  in
  match next_sig tokens kw_idx with
  | Some first when text_is tokens.(first) "(" -> (
      match mark_param_section_vars tokens first with
      | Some close_idx -> (
          match next_sig tokens close_idx with
          | Some name_idx when is_ident tokens.(name_idx) -> (
              match next_sig tokens name_idx with
              | Some open_idx when text_is tokens.(open_idx) "(" ->
                  mark_func_name name_idx
              | _ -> ())
          | _ -> ())
      | None -> ())
  | Some name_idx when is_ident tokens.(name_idx) -> mark_func_name name_idx
  | _ -> ()

let classify tokens =
  let arr = Array.of_list tokens in
  Array.iter set_base_role arr;
  Array.iteri
    (fun i t ->
      if text_is t "func" then mark_func_decl arr i
      else if text_is t "var" || text_is t "const" then
        mark_var_or_const_decl arr i
      else if text_is t "type" then mark_type_decl arr i
      else if text_is t ":=" then mark_short_decl_lhs arr i)
    arr;
  Array.iter
    (fun t ->
      if t.kind = Ident && Option.is_none t.role then
        t.role <- Some Hl_identifier)
    arr;
  Array.to_list arr

let spans_of_tokens tokens =
  List.map
    (fun t -> { Highlight.span_role = t.role; span_text = t.text })
    tokens

let highlight_text text =
  text |> lex_text |> classify |> spans_of_tokens |> Highlight.spans_to_inlines

let is_line_comment t =
  t.kind = Comment && String.starts_with ~prefix:"//" t.lexeme

let is_unclosed_block_comment t =
  t.kind = Comment
  && String.starts_with ~prefix:"/*" t.lexeme
  && not (Strings.is_infix_of "*/" t.lexeme)

let split_trailing_open_comment tokens =
  match List.rev tokens with
  | t :: rest when is_line_comment t || is_unclosed_block_comment t ->
      let mode = if is_line_comment t then `Line else `Block in
      Some (List.rev rest, mode, t.text)
  | _ -> None

let inlines_of_tokens tokens =
  tokens |> classify |> spans_of_tokens |> Highlight.spans_to_inlines

let comment_inline body = Highlighted (Hl_comment, List.rev body)

let flush_comment body acc =
  match body with [] -> acc | _ -> comment_inline body :: acc

let split_text_once text sep =
  match Text.str_index text sep with
  | None -> None
  | Some i ->
      let left, rest = Text.split_at text i in
      let _, right = Text.split_at rest (String.length sep) in
      Some (left, right)

let rec highlight_normal acc = function
  | [] -> List.rev acc
  | Str text :: rest -> (
      let tokens = lex_text text in
      match split_trailing_open_comment tokens with
      | None ->
          highlight_normal (List.rev_append (inlines_of_tokens tokens) acc) rest
      | Some (prefix_tokens, `Line, comment) ->
          let acc = List.rev_append (inlines_of_tokens prefix_tokens) acc in
          highlight_line_comment [ Str comment ] acc rest
      | Some (prefix_tokens, `Block, comment) ->
          let acc = List.rev_append (inlines_of_tokens prefix_tokens) acc in
          highlight_block_comment [ Str comment ] acc rest)
  | inline :: rest -> highlight_normal (inline :: acc) rest

and highlight_line_comment body acc = function
  | [] -> List.rev (flush_comment body acc)
  | Str text :: rest -> (
      match Text.split_once_by Highlight.is_newline text with
      | before_newline, after_newline when Text.is_empty after_newline ->
          highlight_line_comment (Str before_newline :: body) acc rest
      | before_newline, after_newline ->
          let newline, suffix = Text.split_at after_newline 1 in
          let acc = comment_inline (Str before_newline :: body) :: acc in
          highlight_normal (Str newline :: acc) (Str suffix :: rest))
  | inline :: rest -> highlight_line_comment (inline :: body) acc rest

and highlight_block_comment body acc = function
  | [] -> List.rev (flush_comment body acc)
  | Str text :: rest -> (
      match split_text_once text "*/" with
      | None -> (
          match Text.split_once_by Highlight.is_newline text with
          | _, after when Text.is_empty after ->
              highlight_block_comment (Str text :: body) acc rest
          | before, after ->
              let newline, suffix = Text.split_at after 1 in
              let acc = comment_inline (Str before :: body) :: acc in
              let acc = Str newline :: acc in
              highlight_block_comment [ Str suffix ] acc rest)
      | Some (before_close, suffix) ->
          let comment_text = Text.append before_close (Text.of_string "*/") in
          let acc = comment_inline (Str comment_text :: body) :: acc in
          highlight_normal acc (Str suffix :: rest))
  | inline :: rest -> highlight_block_comment (inline :: body) acc rest

let highlight inlines = highlight_normal [] inlines
