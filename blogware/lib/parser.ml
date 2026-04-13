(* Top-level TeX parser. Mirror of Blogware.Parser. *)

open Parser_state
open Syntax

let is_alpha_num c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

let is_digit c = c >= '0' && c <= '9'

let is_special c = match c with
  | '%' | '{' | '}' | '\\' | '[' | ']' | '&' | '$' -> true
  | _ -> false

let is_symbolic c =
  is_alpha_num c || c = '*' || c = '-' || c = '.'

let is_url_char c =
  is_alpha_num c
  || (let s = "-._~:/?#[]@!$&()*+,;%='" in String.contains s c)

let is_align_char c =
  c = 'c' || c = 'l' || c = 'r' || c = '|' || c = ' '

(* TeX comment: '%' to end of line. *)
let parse_comment : unit t =
  let* _ = char '%' in
  let rec drop st =
    if st.ofs >= String.length st.src then POk ((), st, true)
    else
      let c = st.src.[st.ofs] in
      let st' = { st with ofs = st.ofs + 1; pos = Parser_pos.advance st.pos c } in
      if c = '\n' then POk ((), st', true)
      else drop st'
  in
  drop

(* Plain text run: a non-empty sequence of non-special characters.
   Also stops at backtick so that ``...'' can be structured as a
   [NQuotation] at the sequence-item level. *)
let parse_text_node : node t =
  let* pos = get_position in
  let* chars = many1 (satisfy (fun c -> not (is_special c) && c <> '`')) in
  return (NText (pos, string_of_chars chars))

(* Text run inside a quotation body: also stops at single-quote so the
   closing '' can be detected. *)
let parse_text_node_in_quot : node t =
  let* pos = get_position in
  let* chars =
    many1 (satisfy (fun c -> not (is_special c) && c <> '`' && c <> '\''))
  in
  return (NText (pos, string_of_chars chars))

(* Single literal character as a text node (fallback for lone ` or '
   that aren't part of a quotation pair). *)
let parse_one_char_text (c : char) : node t =
  let* pos = get_position in
  let* _ = char c in
  return (NText (pos, String.make 1 c))

(* Bracket characters as single-char text nodes. *)
let parse_bracket_text : node t =
  let* pos = get_position in
  let* c = char '[' <|> char ']' in
  return (NText (pos, String.make 1 c))

(* Escaped character: \%, \\, \&, \#, \_, \{, \}, \$, \<newline> *)
let parse_escape : node t =
  let* pos = get_position in
  let* _ = char '\\' in
  let* c = one_of "%\\&#_{}\n$" in
  return (NText (pos, String.make 1 c))

(* Split a string on a delimiter character. *)
let split_on_char delim s =
  String.split_on_char delim s

(* Parse a {...} group of n column-spec letters. *)
let parse_col_specs s : col_spec list =
  let buf = ref [] in
  String.iter (fun c -> match c with
    | 'l' -> buf := Col_left :: !buf
    | 'r' -> buf := Col_right :: !buf
    | 'c' -> buf := Col_center :: !buf
    | _ -> ()
  ) s;
  List.rev !buf

(* Parse a single argument according to its type. Mutually recursive with
   parse_seq_body via At_seq. Eta-expanded on [st] so OCaml accepts the
   recursive group. *)
let rec parse_arg arg_type st =
  (match arg_type with
   | At_seq ->
     let* _ = char '{' in
     let* pos = get_position in
     let* nodes = parse_seq_body () in
     let* _ = char '}' in
     return (Arg_nodes (pos, nodes))
   | At_sym ->
     let* _ = char '{' in
     let* pos = get_position in
     let* chars = many1 (satisfy is_symbolic) in
     let* _ = char '}' in
     return (Arg_symbol (pos, string_of_chars chars))
   | At_num ->
     let* _ = char '{' in
     let* pos = get_position in
     let* chars = many1 (satisfy (fun c -> is_digit c || c = '-')) in
     let* _ = char '}' in
     let s = string_of_chars chars in
     (match int_of_string_opt s with
      | Some n -> return (Arg_number (pos, n))
      | None -> fail ("invalid number: " ^ s))
   | At_url ->
     let* _ = char '{' in
     let* pos = get_position in
     let* chars = many1 (satisfy is_url_char) in
     let* _ = char '}' in
     return (Arg_url (pos, string_of_chars chars))
   | At_align_spec ->
     let* _ = char '{' in
     let* pos = get_position in
     let* chars = many1 (satisfy is_align_char) in
     let* _ = char '}' in
     return (Arg_align (pos, parse_col_specs (string_of_chars chars)))) st

(* parse_seq_body and parse_seq_item are mutually recursive with parse_cmd. *)
and parse_seq_body () st =
  (let* nodess = many parse_seq_item in
   return (List.concat nodess)) st

and parse_seq_item st =
  (choice
     [ try_ parse_comment *> return []
     ; (let* n = try_ parse_display_math in return [n])
     ; (let* n = try_ parse_cmd in return [n])
     ; (let* n = parse_group in return [n])
     ; (let* n = parse_inline_math in return [n])
     ; (let* n = parse_bracket_text in return [n])
     ; (let* n = try_ parse_quotation in return [n])
     ; (let* n = parse_text_node in return [n])
     ; (let* n = parse_one_char_text '`' in return [n])
     ]) st

(* ``...'' → [NQuotation]. [try_ (string "``")] makes the whole
   parser rewindable so a lone ` falls through to [parse_one_char_text]. *)
and parse_quotation st =
  (let* pos = get_position in
   let* _ = try_ (string "``") in
   parse_quotation_body pos []) st

and parse_quotation_body open_pos acc st =
  match try_ (string "''") st with
  | POk (_, st', c) ->
    POk (NQuotation (open_pos, List.rev acc), st', c)
  | PFail _ ->
    (match parse_quot_item st with
     | POk (ns, st', c1) ->
       (match parse_quotation_body open_pos (List.rev_append ns acc) st' with
        | POk (r, st'', c2) -> POk (r, st'', c1 || c2)
        | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
     | PFail _ as e -> e)

and parse_quot_item st =
  (choice
     [ try_ parse_comment *> return []
     ; (let* n = try_ parse_display_math in return [n])
     ; (let* n = try_ parse_cmd in return [n])
     ; (let* n = parse_group in return [n])
     ; (let* n = parse_inline_math in return [n])
     ; (let* n = parse_bracket_text in return [n])
     ; (let* n = try_ parse_quotation in return [n])
     ; (let* n = parse_text_node_in_quot in return [n])
     ; (let* n = parse_one_char_text '`' in return [n])
     ; (let* n = parse_one_char_text '\'' in return [n])
     ]) st

(* Optional [opt1,opt2,...] argument list. *)
and parse_options st =
  ((option_maybe (try_ (
       let* _ = char '[' in
       let* content = option_maybe (many1 (none_of "]")) in
       let* _ = char ']' in
       match content with
       | None -> return []
       | Some cs -> return (split_on_char ',' (string_of_chars cs))
     )))
   >>| (function None -> [] | Some xs -> xs)) st

and parse_group st =
  (let* pos = get_position in
   let* _ = char '{' in
   let* nodes = parse_seq_body () in
   let* _ = char '}' in
   return (NGroup (pos, nodes))) st

and parse_inline_math st =
  (let* pos = get_position in
   let* _ = char '$' in
   let* nodes = Parser_math.parse_math_body ~display:false in
   return (NMath (pos, Math_inline, nodes))) st

and parse_display_math st =
  (let* pos = get_position in
   let* _ = try_ (string "\\[") in
   let* nodes = Parser_math.parse_math_body ~display:true in
   return (NMath (pos, Math_display, nodes))) st

(* \name[opts]{arg1}{arg2}... *)
and parse_cmd st =
  (try_ parse_escape
   <|> (
     let* pos = get_position in
     let* _ = char '\\' in
     let* c = look_ahead any_char in
     let* () =
       if c = ']' then unexpected "display math end"
       else return ()
     in
     let* name_chars = many1 (satisfy is_symbolic) in
     let name = string_of_chars name_chars in
     (* Skip a single trailing space after command name *)
     let* () = optional (char ' ') in
     match name with
     | "begin" -> parse_begin_env pos
     | "end" -> fail "unexpected \\end without matching \\begin"
     | _ -> parse_command_with_args pos name
   )) st

and parse_command_with_args pos name st =
  (let* opts = parse_options in
   let arg_types = match SMap.find_opt name cmd_args with
     | Some xs -> xs
     | None -> []
   in
   let rec collect = function
     | [] -> return []
     | t :: rest ->
       let* a = parse_arg t in
       let* xs = collect rest in
       return (a :: xs)
   in
   let* args = collect arg_types in
   return (NCmd (pos, name, opts, args))) st

(* \begin{envname}[opts] body \end{envname} *)
and parse_begin_env begin_pos st =
  (let* _ = char '{' in
   let* name_chars = many1 (satisfy is_symbolic) in
   let name = string_of_chars name_chars in
   let* _ = char '}' in
   let* opts = parse_options in
   match name with
   | "verbatim" -> parse_verbatim_env begin_pos name opts
   | "tabular" | "tabular*" -> parse_table_env begin_pos name opts
   | "code" ->
     let* () = optional (char '\n') in
     parse_regular_env begin_pos name opts
   | _ -> parse_regular_env begin_pos name opts) st

and parse_regular_env begin_pos name opts st =
  (let* body = parse_env_body name in
   let* end_pos = get_position in
   return (NEnv (begin_pos, end_pos, name, opts, body))) st

(* Parse an environment body until \end{name}. Skips comments inline. *)
and parse_env_body env_name st =
  let is_code = env_name = "code" in
  let rec go acc st =
    (* Try to detect \end{ *)
    let end_tag =
      try_ (
        let* _ = char '\\' in
        let* _ = string "end" in
        let* _ = char '{' in
        return ()
      ) st
    in
    match end_tag with
    | POk ((), st', _c) ->
      (* committed: parse the env name and check it *)
      (match get_position st' with
       | POk (pos, st'', _) ->
         (match many1 (satisfy is_symbolic) st'' with
          | POk (chars, st''', _) ->
            let n = string_of_chars chars in
            (match char '}' st''' with
             | POk (_, st'''', _) ->
               if n = env_name then POk (List.rev acc, st'''', true)
               else
                 (* rewind position for error reporting *)
                 PFail (pos,
                        "expected \\end{" ^ env_name ^ "} but found \\end{" ^ n ^ "}",
                        true)
             | PFail _ as e -> e)
          | PFail _ as e -> e)
       | PFail _ as e -> e)
    | PFail (_, _, _) ->
      (* Skip comments; if any were skipped, re-check for \end{ before
         trying to parse a node. *)
      let rec skip_comments st skipped =
        match try_ parse_comment st with
        | POk (_, st', _) -> skip_comments st' true
        | PFail _ -> (st, skipped)
      in
      let (st, skipped) = skip_comments st false in
      if skipped then go acc st
      else
        let node_p = if is_code then parse_code_node else parse_env_node in
        (match node_p st with
         | POk (n, st', c1) ->
           (match go (n :: acc) st' with
            | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
            | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
         | PFail _ as e -> e)
  in
  go [] st

(* Code envs: only commands and math get parsed; everything else is text. *)
and parse_code_node st =
  (choice
     [ try_ parse_display_math
     ; try_ parse_cmd
     ; parse_inline_math
     ; parse_code_text
     ]) st

and parse_code_text st =
  (let* pos = get_position in
   let* chars =
     many1 (satisfy (fun c -> not (c = '\\' || c = '$' || c = '%')))
   in
   return (NText (pos, string_of_chars chars))) st

(* Normal env body node parser *)
and parse_env_node st =
  (choice
     [ try_ parse_display_math
     ; try_ parse_cmd
     ; parse_group
     ; parse_inline_math
     ; parse_bracket_text_single
     ; try_ parse_quotation
     ; parse_text_node
     ; parse_one_char_text '`'
     ]) st

and parse_bracket_text_single st =
  (let* pos = get_position in
   let* c = char '[' <|> char ']' in
   return (NText (pos, String.make 1 c))) st

(* Verbatim env: raw text until \end{verbatim} *)
and parse_verbatim_env begin_pos name opts st =
  (let* () = optional (char '\n') in
   let* pos = get_position in
   let* body = many_till_chars "\\end{verbatim}" in
   let* end_pos = get_position in
   return (NEnv (begin_pos, end_pos, name, opts, [NText (pos, body)]))) st

(* Tabular env *)
and parse_table_env begin_pos name opts st =
  (let* _ = char '{' in
   let* spec_chars = many1 (satisfy is_align_char) in
   let* _ = char '}' in
   let spec = parse_col_specs (string_of_chars spec_chars) in
   let* rows = parse_table_rows name spec in
   let* end_pos = get_position in
   return (NTable (begin_pos, end_pos, name, opts, spec, rows))) st

and parse_table_rows env_name spec st =
  let num_cols = List.length spec in
  let spec_at i =
    if i < num_cols then List.nth spec i else Col_left
  in
  let dummy_pos = Parser_pos.make "<table>" 0 0 in
  let rec go rows current_row current_cell cell_count st =
    (* Try \end{ *)
    let end_tag =
      try_ (
        let* _ = char '\\' in
        let* _ = string "end" in
        let* _ = char '{' in
        return ()
      ) st
    in
    match end_tag with
    | POk ((), st', _) ->
      (match get_position st' with
       | POk (pos, st'', _) ->
         (match many1 (satisfy is_symbolic) st'' with
          | POk (chars, st''', _) ->
            let n = string_of_chars chars in
            (match char '}' st''' with
             | POk (_, st'''', _) ->
               if n <> env_name then
                 PFail (pos,
                        "expected \\end{" ^ env_name ^ "} but found \\end{" ^ n ^ "}",
                        true)
               else begin
                 (* Handle pending hrule as bottom border on last row *)
                 let final_rows =
                   match current_row.row_borders, current_row.row_cells, List.rev rows with
                   | Border_top, [], r :: rest_rev ->
                     let border' = match r.row_borders with
                       | Border_none -> Border_bottom
                       | Border_top -> Border_both
                       | Border_bottom -> Border_bottom
                       | Border_both -> Border_both
                     in
                     List.rev ({ r with row_borders = border' } :: rest_rev)
                   | _ -> rows
                 in
                 POk (final_rows, st'''', true)
               end
             | PFail _ as e -> e)
          | PFail _ as e -> e)
       | PFail _ as e -> e)
    | PFail (_, _, _) ->
      (* Try row separator: \\ *)
      let row_sep =
        try_ (
          let* _ = char '\\' in
          let* c = look_ahead any_char in
          if c = '\\' then let* _ = char '\\' in return ()
          else fail "not a row separator"
        ) st
      in
      match row_sep with
      | POk ((), st', _) ->
        let row' = { current_row with row_cells = current_row.row_cells @ [current_cell] } in
        go (rows @ [row'])
          { row_borders = Border_none; row_cells = [] }
          { cell_pos = dummy_pos; cell_align = spec_at 0; cell_colspan = 1; cell_body = [] }
          1
          st'
      | PFail _ ->
        (* Try cell separator: & *)
        match option_maybe (char '&') st with
        | POk (Some _, st', _) ->
          let next_spec =
            if cell_count < num_cols then spec_at cell_count else Col_left
          in
          (match get_position st' with
           | POk (pos, st'', _) ->
             go rows
               { current_row with row_cells = current_row.row_cells @ [current_cell] }
               { cell_pos = pos; cell_align = next_spec; cell_colspan = 1; cell_body = [] }
               (cell_count + 1)
               st''
           | PFail _ as e -> e)
        | POk (None, _, _) | PFail _ ->
          (* Try \hrule *)
          let hrule =
            try_ (
              let* _ = char '\\' in
              let* _ = string "hrule" in
              let* () = optional (char ' ') in
              return ()
            ) st
          in
          match hrule with
          | POk ((), st', _) ->
            go rows { current_row with row_borders = Border_top } current_cell cell_count st'
          | PFail _ ->
            (* Try \multicolumn *)
            let mcol =
              try_ (
                let* pos = get_position in
                let* _ = char '\\' in
                let* _ = string "multicolumn" in
                let* n = parse_arg At_num in
                let* a = parse_arg At_align_spec in
                let* b = parse_arg At_seq in
                return (pos, n, a, b)
              ) st
            in
            match mcol with
            | POk ((pos, Arg_number (_, n), Arg_align (_, [al]), Arg_nodes (_, body)), st', _) ->
              let mcell = { cell_pos = pos; cell_align = al; cell_colspan = n; cell_body = body } in
              let next_spec =
                spec_at (cell_count + n - 1)
              in
              go rows
                { current_row with row_cells = current_row.row_cells @ [mcell] }
                { cell_pos = pos; cell_align = next_spec; cell_colspan = 1; cell_body = [] }
                (cell_count + n)
                st'
            | POk _ -> PFail (Parser_pos.initial "<table>", "\\multicolumn requires {N}{alignment}{content}", true)
            | PFail _ ->
              (* Parse a node for the current cell *)
              let cell_node =
                choice
                  [ try_ (parse_comment *> (parse_text_node <|> parse_cell_text))
                  ; try_ parse_cmd
                  ; parse_group
                  ; try_ parse_display_math
                  ; parse_inline_math
                  ; parse_cell_text
                  ]
              in
              (match cell_node st with
               | POk (n, st', c1) ->
                 let cell' = { current_cell with cell_body = current_cell.cell_body @ [n] } in
                 (match go rows current_row cell' cell_count st' with
                  | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
                  | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
               | PFail _ as e -> e)
  in
  go []
    { row_borders = Border_none; row_cells = [] }
    { cell_pos = dummy_pos; cell_align = spec_at 0; cell_colspan = 1; cell_body = [] }
    1
    st

and parse_cell_text st =
  (let* pos = get_position in
   let* chars =
     many1 (satisfy (fun c -> not (is_special c) && c <> '&'))
   in
   return (NText (pos, string_of_chars chars))) st

(* Top-level node sequence. *)
let parse_top_level : node list t =
  choice
    [ try_ parse_comment *> return []
    ; (let* n = try_ parse_display_math in return [n])
    ; (let* n = parse_cmd in return [n])
    ; (let* n = parse_group in return [n])
    ; (let* n = parse_inline_math in return [n])
    ; (let* n = parse_bracket_text in return [n])
    ; (let* n = try_ parse_quotation in return [n])
    ; (let* n = parse_text_node in return [n])
    ; (let* n = parse_one_char_text '`' in return [n])
    ]

let parse_sequence : node list t =
  let* xss = many parse_top_level in
  return (List.concat xss)

let parse_document ~source_name input : (node list, Error.parse_error) result =
  run (parse_sequence <* eof) ~source_name input
