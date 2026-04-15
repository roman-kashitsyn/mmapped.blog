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

let has_char_at (src : string) (ofs : int) (c : char) : bool =
  ofs < String.length src && String.unsafe_get src ofs = c

let starts_display_math st =
  has_char_at st.src (st.ofs + 1) '['

(* TeX comment: '%' to end of line. *)
let parse_comment : unit t =
  let* _ = char '%' in
  let* () = skip_while (fun c -> c <> '\n') in
  let* () = optional (char '\n') in
  return ()

(* Plain text run: a non-empty sequence of non-special characters.
   Also stops at backtick so that ``...'' can be structured as a
   [NQuotation] at the sequence-item level. *)
let parse_text_node : node t =
  let* pos = get_position in
  let* text = take_while1 (fun c -> not (is_special c) && c <> '`') in
  return (NText (pos, text))

(* Text run inside a quotation body: also stops at single-quote so the
   closing '' can be detected. *)
let parse_text_node_in_quot : node t =
  let* pos = get_position in
  let* text =
    take_while1 (fun c -> not (is_special c) && c <> '`' && c <> '\'')
  in
  return (NText (pos, text))

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

let finish_cell (cell : cell) : cell =
  { cell with cell_body = List.rev cell.cell_body }

let finish_row (row_borders : row_border) (row_cells_rev : cell list) : row =
  { row_borders; row_cells = List.rev_map finish_cell row_cells_rev }

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
     let* name = take_while1 is_symbolic in
     let* _ = char '}' in
     return (Arg_symbol (pos, name))
   | At_num ->
     let* _ = char '{' in
     let* pos = get_position in
     let* s = take_while1 (fun c -> is_digit c || c = '-') in
     let* _ = char '}' in
     (match int_of_string_opt s with
      | Some n -> return (Arg_number (pos, n))
      | None -> fail ("invalid number: " ^ s))
   | At_url ->
     let* _ = char '{' in
     let* pos = get_position in
     let* url = take_while1 is_url_char in
     let* _ = char '}' in
     return (Arg_url (pos, url))
   | At_align_spec ->
     let* _ = char '{' in
     let* pos = get_position in
     let* spec = take_while1 is_align_char in
     let* _ = char '}' in
     return (Arg_align (pos, parse_col_specs spec))) st

(* parse_seq_body and parse_seq_item are mutually recursive with parse_cmd. *)
and parse_seq_body () st =
  let rec go acc consumed st =
    match parse_seq_item st with
    | POk (nodes, st', c1) ->
      let acc = List.rev_append nodes acc in
      (match go acc (consumed || c1) st' with
       | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
       | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
    | PFail (_, _, false) -> POk (List.rev acc, st, consumed)
    | PFail _ as e -> e
  in
  go [] false st

and parse_seq_item st =
  if st.ofs >= String.length st.src then
    PFail (st.pos, "unexpected end of input", false)
  else
    match String.unsafe_get st.src st.ofs with
    | '%' -> (try_ parse_comment *> return []) st
    | '\\' ->
      if starts_display_math st then
        (let* n = parse_display_math in return [n]) st
      else
        (let* n = parse_cmd in return [n]) st
    | '{' -> (let* n = parse_group in return [n]) st
    | '$' -> (let* n = parse_inline_math in return [n]) st
    | '[' | ']' -> (let* n = parse_bracket_text in return [n]) st
    | '`' ->
      (match try_ parse_quotation st with
       | POk (n, st', c) -> POk ([n], st', c)
       | PFail (_, _, false) -> (let* n = parse_one_char_text '`' in return [n]) st
       | PFail _ as e -> e)
    | _ -> (let* n = parse_text_node in return [n]) st

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
  if st.ofs >= String.length st.src then
    PFail (st.pos, "unexpected end of input", false)
  else
    match String.unsafe_get st.src st.ofs with
    | '%' -> (try_ parse_comment *> return []) st
    | '\\' ->
      if starts_display_math st then
        (let* n = parse_display_math in return [n]) st
      else
        (let* n = parse_cmd in return [n]) st
    | '{' -> (let* n = parse_group in return [n]) st
    | '$' -> (let* n = parse_inline_math in return [n]) st
    | '[' | ']' -> (let* n = parse_bracket_text in return [n]) st
    | '`' ->
      (match try_ parse_quotation st with
       | POk (n, st', c) -> POk ([n], st', c)
       | PFail (_, _, false) -> (let* n = parse_one_char_text '`' in return [n]) st
       | PFail _ as e -> e)
    | '\'' -> (let* n = parse_one_char_text '\'' in return [n]) st
    | _ -> (let* n = parse_text_node_in_quot in return [n]) st

(* Optional [opt1,opt2,...] argument list. *)
and parse_options st =
  ((option_maybe (try_ (
       let* _ = char '[' in
       let* content = take_while (fun c -> c <> ']') in
       let* _ = char ']' in
       return
         (if content = "" then [] else split_on_char ',' content)
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
  let len = String.length st.src in
  if st.ofs >= len || String.unsafe_get st.src st.ofs <> '\\' then
    PFail (st.pos, "expected '\\\\'", false)
  else
    let pos = st.pos in
    let cmd_ofs = st.ofs + 1 in
    let pos_after_slash = Parser_pos.advance pos '\\' in
    if cmd_ofs >= len then
      PFail (pos_after_slash, "unexpected end of input", true)
    else
      let c = String.unsafe_get st.src cmd_ofs in
      if String.contains "%\\&#_{}\n$" c then
        let pos' = Parser_pos.advance pos_after_slash c in
        POk
          ( NText (pos, String.make 1 c)
          , { st with ofs = cmd_ofs + 1; pos = pos' }
          , true )
      else if c = ']' then
        PFail (pos_after_slash, "unexpected display math end", true)
      else if not (is_symbolic c) then
        PFail (pos_after_slash, "expected matching character", true)
      else
        let name_end = ref (cmd_ofs + 1) in
        while !name_end < len && is_symbolic (String.unsafe_get st.src !name_end) do
          incr name_end
        done;
        let name = String.sub st.src cmd_ofs (!name_end - cmd_ofs) in
        let ofs =
          if !name_end < len && String.unsafe_get st.src !name_end = ' '
          then !name_end + 1
          else !name_end
        in
        let pos' = Parser_pos.advance_by pos (ofs - st.ofs) in
        let st' = { st with ofs; pos = pos' } in
        match name with
        | "begin" -> parse_begin_env pos st'
        | "end" -> PFail (st'.pos, "unexpected \\end without matching \\begin", true)
        | _ -> parse_command_with_args pos name st'

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
   let* name = take_while1 is_symbolic in
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
    if has_prefix_at st.src st.ofs "\\end{" then
      let name_ofs = st.ofs + 5 in
      let pos = Parser_pos.advance_by st.pos 5 in
      let name_end = ref name_ofs in
      let len = String.length st.src in
      while !name_end < len && is_symbolic (String.unsafe_get st.src !name_end) do
        incr name_end
      done;
      if !name_end = name_ofs then
        PFail (pos, "expected matching character", true)
      else if !name_end >= len || String.unsafe_get st.src !name_end <> '}' then
        PFail (Parser_pos.advance_by pos (!name_end - name_ofs), "expected '}'", true)
      else
        let n = String.sub st.src name_ofs (!name_end - name_ofs) in
        let st' =
          { st with
            ofs = !name_end + 1
          ; pos = Parser_pos.advance_by st.pos (!name_end + 1 - st.ofs)
          }
        in
        if n = env_name then POk (List.rev acc, st', true)
        else
          PFail
            ( pos
            , "expected \\end{" ^ env_name ^ "} but found \\end{" ^ n ^ "}"
            , true )
    else
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
  if st.ofs >= String.length st.src then
    PFail (st.pos, "unexpected end of input", false)
  else
    match String.unsafe_get st.src st.ofs with
    | '\\' ->
      if starts_display_math st then parse_display_math st else parse_cmd st
    | '$' -> parse_inline_math st
    | _ -> parse_code_text st

and parse_code_text st =
  (let* pos = get_position in
   let* text =
     take_while1 (fun c -> not (c = '\\' || c = '$' || c = '%'))
   in
   return (NText (pos, text))) st

(* Normal env body node parser *)
and parse_env_node st =
  if st.ofs >= String.length st.src then
    PFail (st.pos, "unexpected end of input", false)
  else
    match String.unsafe_get st.src st.ofs with
    | '\\' ->
      if starts_display_math st then parse_display_math st else parse_cmd st
    | '{' -> parse_group st
    | '$' -> parse_inline_math st
    | '[' | ']' -> parse_bracket_text_single st
    | '`' ->
      (match try_ parse_quotation st with
       | POk _ as r -> r
       | PFail (_, _, false) -> parse_one_char_text '`' st
       | PFail _ as e -> e)
    | _ -> parse_text_node st

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
   let* spec = take_while1 is_align_char in
   let* _ = char '}' in
   let spec = parse_col_specs spec in
   let* rows = parse_table_rows name spec in
   let* end_pos = get_position in
   return (NTable (begin_pos, end_pos, name, opts, spec, rows))) st

and parse_table_rows env_name spec st =
  let spec_arr = Array.of_list spec in
  let num_cols = Array.length spec_arr in
  let spec_at i = if i < num_cols then spec_arr.(i) else Col_left in
  let dummy_pos = Parser_pos.make "<table>" 0 0 in
  let fresh_cell pos align =
    { cell_pos = pos; cell_align = align; cell_colspan = 1; cell_body = [] }
  in
  let rec go rows_rev row_borders row_cells_rev current_cell cell_count st =
    if has_prefix_at st.src st.ofs "\\end{" then
      let name_ofs = st.ofs + 5 in
      let pos = Parser_pos.advance_by st.pos 5 in
      let name_end = ref name_ofs in
      let len = String.length st.src in
      while !name_end < len && is_symbolic (String.unsafe_get st.src !name_end) do
        incr name_end
      done;
      if !name_end = name_ofs then
        PFail (pos, "expected matching character", true)
      else if !name_end >= len || String.unsafe_get st.src !name_end <> '}' then
        PFail (Parser_pos.advance_by pos (!name_end - name_ofs), "expected '}'", true)
      else
        let n = String.sub st.src name_ofs (!name_end - name_ofs) in
        if n <> env_name then
          PFail
            ( pos
            , "expected \\end{" ^ env_name ^ "} but found \\end{" ^ n ^ "}"
            , true )
        else
          let st' =
            { st with
              ofs = !name_end + 1
            ; pos = Parser_pos.advance_by st.pos (!name_end + 1 - st.ofs)
            }
          in
          (* Handle pending hrule as bottom border on last row. *)
          let final_rows_rev =
            match row_borders, row_cells_rev, rows_rev with
            | Border_top, [], r :: rest_rev ->
              let border' = match r.row_borders with
                | Border_none -> Border_bottom
                | Border_top -> Border_both
                | Border_bottom -> Border_bottom
                | Border_both -> Border_both
              in
              { r with row_borders = border' } :: rest_rev
            | _ -> rows_rev
          in
          POk (List.rev final_rows_rev, st', true)
    else
      (* Try row separator: \\ *)
      if has_prefix_at st.src st.ofs "\\\\" then
        let st' =
          { st with ofs = st.ofs + 2; pos = Parser_pos.advance_by st.pos 2 }
        in
        let row' = finish_row row_borders (current_cell :: row_cells_rev) in
        go (row' :: rows_rev)
          Border_none
          []
          (fresh_cell dummy_pos (spec_at 0))
          1
          st'
      else
        (* Try cell separator: & *)
        match option_maybe (char '&') st with
        | POk (Some _, st', _) ->
          let next_spec =
            if cell_count < num_cols then spec_at cell_count else Col_left
          in
          (match get_position st' with
           | POk (pos, st'', _) ->
             go rows_rev
               row_borders
               (current_cell :: row_cells_rev)
               (fresh_cell pos next_spec)
               (cell_count + 1)
               st''
           | PFail _ as e -> e)
        | POk (None, _, _) | PFail _ ->
          (* Try \hrule *)
          if has_prefix_at st.src st.ofs "\\hrule" then
            let ofs = st.ofs + 6 in
            let ofs =
              if has_char_at st.src ofs ' ' then ofs + 1 else ofs
            in
            let st' = { st with ofs; pos = Parser_pos.advance_by st.pos (ofs - st.ofs) } in
            go rows_rev Border_top row_cells_rev current_cell cell_count st'
          else
            (* Try \multicolumn *)
            let mcol =
              if has_prefix_at st.src st.ofs "\\multicolumn" then
                let st' =
                  { st with
                    ofs = st.ofs + 12
                  ; pos = Parser_pos.advance_by st.pos 12
                  }
                in
                (let* n = parse_arg At_num in
                 let* a = parse_arg At_align_spec in
                 let* b = parse_arg At_seq in
                 return (st.pos, n, a, b)) st'
              else
                PFail (st.pos, "expected \"\\\\multicolumn\"", false)
            in
            match mcol with
            | POk ((pos, Arg_number (_, n), Arg_align (_, [al]), Arg_nodes (_, body)), st', _) ->
              let mcell =
                { cell_pos = pos
                ; cell_align = al
                ; cell_colspan = n
                ; cell_body = List.rev body
                }
              in
              let next_spec =
                spec_at (cell_count + n - 1)
              in
              go rows_rev
                row_borders
                (mcell :: row_cells_rev)
                (fresh_cell pos next_spec)
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
                 let cell' = { current_cell with cell_body = n :: current_cell.cell_body } in
                 (match go rows_rev row_borders row_cells_rev cell' cell_count st' with
                  | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
                  | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
               | PFail _ as e -> e)
  in
  go []
    Border_none
    []
    (fresh_cell dummy_pos (spec_at 0))
    1
    st

and parse_cell_text st =
  (let* pos = get_position in
   let* text =
     take_while1 (fun c -> not (is_special c) && c <> '&')
   in
   return (NText (pos, text))) st

(* Top-level node sequence. *)
let parse_top_level : node list t =
  fun st ->
    if st.ofs >= String.length st.src then
      PFail (st.pos, "unexpected end of input", false)
    else
      match String.unsafe_get st.src st.ofs with
      | '%' -> (try_ parse_comment *> return []) st
      | '\\' ->
        if starts_display_math st then
          (let* n = parse_display_math in return [n]) st
        else
          (let* n = parse_cmd in return [n]) st
      | '{' -> (let* n = parse_group in return [n]) st
      | '$' -> (let* n = parse_inline_math in return [n]) st
      | '[' | ']' -> (let* n = parse_bracket_text in return [n]) st
      | '`' ->
        (match try_ parse_quotation st with
         | POk (n, st', c) -> POk ([n], st', c)
         | PFail (_, _, false) -> (let* n = parse_one_char_text '`' in return [n]) st
         | PFail _ as e -> e)
      | _ -> (let* n = parse_text_node in return [n]) st

let parse_sequence : node list t =
  let rec go acc consumed st =
    match parse_top_level st with
    | POk (nodes, st', c1) ->
      let acc = List.rev_append nodes acc in
      (match go acc (consumed || c1) st' with
       | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
       | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
    | PFail (_, _, false) -> POk (List.rev acc, st, consumed)
    | PFail _ as e -> e
  in
  go [] false

let parse_document ~source_name input : (node list, Error.parse_error) result =
  run (parse_sequence <* eof) ~source_name input
