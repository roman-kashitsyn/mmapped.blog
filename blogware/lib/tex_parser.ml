open Parser
open Syntax

let is_alpha_num c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

let is_digit c = c >= '0' && c <= '9'

let is_special c =
  match c with
  | '%' | '{' | '}' | '\\' | '[' | ']' | '&' | '$' -> true
  | _ -> false

let is_symbolic c = is_alpha_num c || c = '*' || c = '-' || c = '.'

let is_url_char c =
  is_alpha_num c || String.contains "-._~:/?#[]@!$&()*+,;%='" c

let is_align_char c =
  match c with 'c' | 'l' | 'r' | '|' | ' ' -> true | _ -> false

module Math = struct
  let is_letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

  let is_math_op c =
    match c with
    | '+' | '-' | '&' | '=' | ',' | ';' | '[' | ']' | '|' | '(' | ')' | '\n'
    | '<' | '>' | ':' ->
        true
    | _ -> false

  let skip_math_spaces : unit t = skip_while (fun c -> c = ' ')

  (* Whether a node is "operator-like", meaning a following '-' should be
     parsed as a unary minus rather than as a binary operator. *)
  let is_operator_like = function
    | Math_op _ -> true
    | Math_cmd ("left", _) -> true
    | _ -> false

  (* Parse \{ or \} as an escaped brace character (used by \left/\right). *)
  let parse_escaped_brace : string t =
    let* c = char '\\' *> one_of "{}" in
    return (String.make 1 c)

  (* Parse a negative number: leading '-' followed by digits. The whole thing
     is wrapped in [try_] so that a bare '-' followed by a non-digit (i.e. a
     subtraction operator) does not consume the dash. *)
  let parse_negative_number : math_node t =
    let step state c =
      match (state, c) with
      | `start, '-' -> Some `saw_minus
      | `saw_minus, c when is_digit c -> Some `digits
      | `digits, c when is_digit c -> Some `digits
      | _ -> None
    in
    let accept = function `digits -> true | `start | `saw_minus -> false in
    try_
      (let* s = scan `start ~step ~accept in
       return (Math_num s))

  let parse_math_number : math_node t =
    let* digits = take_while1 is_digit in
    return (Math_num digits)

  let parse_math_operator : math_node t =
    let* c = satisfy is_math_op in
    return (Math_op (String.make 1 c, false))

  let parse_math_symbol : math_node t =
    let* c = satisfy is_letter in
    return (Math_text (String.make 1 c))

  (* Mutually recursive parsers. Each body is written as [fun st -> (...) st]
     so OCaml's [let rec] sees a syntactic function. *)
  let rec parse_m_list ~end_p st =
    let allow_negative = function
      | [] -> true
      | prev :: _ -> is_operator_like prev
    in
    let rec go acc st =
      match end_p st with
      | POk (_, st', c) -> POk (List.rev acc, st', c)
      | PFail (_, _, true) as e -> e
      | PFail (_, _, false) ->
          bind_step
            (parse_math_term_with_sub_sup ~end_p
               ~allow_negative:(allow_negative acc) st)
            (fun term st' -> go (term :: acc) st')
    in
    go [] st

  and parse_math_term_with_sub_sup ~end_p ~allow_negative st =
    (let* nucleus = parse_math_atom ~end_p ~allow_negative in
     collect_sub_sup ~end_p nucleus)
      st

  and collect_sub_sup ~end_p nuc st =
    let parse_scripted marker =
      option_maybe (char marker *> parse_math_atom ~end_p ~allow_negative:true)
    in
    (let* first_sub = parse_scripted '_' in
     match first_sub with
     | Some sub ->
         let* sup = parse_scripted '^' in
         return (Math_term (nuc, Some sub, sup))
     | None -> (
         let* sup = parse_scripted '^' in
         match sup with
         | None -> return nuc
         | Some sup ->
             let* sub = parse_scripted '_' in
             return (Math_term (nuc, sub, Some sup))))
      st

  and parse_math_atom ~end_p ~allow_negative st =
    let parse_atom_body =
      let* next = peek_char in
      match next with
      | None -> fail "unexpected end of input"
      | Some '{' -> parse_math_group ~end_p
      | Some '\\' -> parse_math_control
      | Some '-' when allow_negative ->
          try_ parse_negative_number <|> parse_math_operator
      | Some c when is_digit c -> parse_math_number
      | Some c when is_math_op c -> parse_math_operator
      | Some c when is_letter c -> parse_math_symbol
      | Some c -> fail (Printf.sprintf "unexpected character %C" c)
    in
    (skip_math_spaces *> parse_atom_body) st

  and parse_math_group ~end_p:_ st =
    (let* nodes = char '{' *> parse_m_list ~end_p:(expect_char '}') in
     return (Math_group nodes))
      st

  and parse_math_control st =
    (let* _ = char '\\' in
     let* esc = option_maybe (one_of "%{}\\^_") in
     match esc with
     | Some c -> return (Math_op (String.make 1 c, false))
     | None -> (
         let* c = look_ahead any_char in
         if c = ']' then unexpected "\\] (unmatched display math delimiter)"
         else
           let* name = take_while1 is_symbolic in
           match SMap.find_opt name math_cmds with
           | Some _ when name = "left" || name = "right" ->
               let* () = skip_math_spaces in
               let* op =
                 try_ parse_escaped_brace
                 <|> let* c = satisfy is_math_op in
                     return (String.make 1 c)
               in
               return (Math_cmd (name, [ Math_op (op, true) ]))
           | Some arg_types ->
               let rec collect_args = function
                 | [] -> return []
                 | t :: rest ->
                     let* a = parse_math_cmd_arg t in
                     let* xs = collect_args rest in
                     return (a :: xs)
               in
               let* args = collect_args arg_types in
               return (Math_cmd (name, args))
           | None -> return (Math_cmd (name, []))))
      st

  and parse_math_cmd_arg t st =
    (match t with
    | Math_arg_expr ->
        let* nodes =
          skip_math_spaces *> char '{' *> parse_m_list ~end_p:(expect_char '}')
        in
        return (Math_group nodes)
    | Math_arg_sym ->
        let* sym =
          skip_math_spaces *> char '{' *> take_while1 is_symbolic <* char '}'
        in
        return (Math_op (sym, false)))
      st

  (* Parse the body of a math environment.
     - display=true -> ends at \]
     - display=false -> ends at $ *)
  let parse_math_body ~display : math_node list t =
    let end_p =
      try_
        (skip_math_spaces
        *> if display then expect_string "\\]" else expect_char '$')
    in
    parse_m_list ~end_p
end

(* TeX comment: '%' to end of line. *)
let parse_comment : unit t =
  char '%'
  *> skip_while (fun c -> c <> '\n')
  *> optional (char '\n')
  *> return ()

(* Plain text run: a non-empty sequence of non-special characters.
   Also stops at backtick so that ``...'' can be structured as a
   [NQuotation] at the sequence-item level. *)
let parse_text_node : node t =
  let* pos = get_position in
  let* text = take_while1 (fun c -> (not (is_special c)) && c <> '`') in
  return (NText (pos, text))

(* Text run inside a quotation body: also stops at single-quote so the
   closing '' can be detected. *)
let parse_text_node_in_quot : node t =
  let* pos = get_position in
  let* text =
    take_while1 (fun c -> (not (is_special c)) && c <> '`' && c <> '\'')
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
  let* c = char '\\' *> one_of "%\\&#_{}\n$" in
  return (NText (pos, String.make 1 c))

(* Parse a {...} group of n column-spec letters. *)
let parse_col_specs s : col_spec list =
  let buf = ref [] in
  String.iter
    (fun c ->
      match c with
      | 'l' -> buf := Col_left :: !buf
      | 'r' -> buf := Col_right :: !buf
      | 'c' -> buf := Col_center :: !buf
      | _ -> ())
    s;
  List.rev !buf

let finish_cell (cell : cell) : cell =
  { cell with cell_body = List.rev cell.cell_body }

let finish_row (row_borders : row_border) (row_cells_rev : cell list) : row =
  { row_borders; row_cells = List.rev_map finish_cell row_cells_rev }

let collect_list (f : 'a -> 'b t) (xs : 'a list) : 'b list t =
  let rec go = function
    | [] -> return []
    | x :: rest ->
        let* a = f x in
        let* bs = go rest in
        return (a :: bs)
  in
  go xs

let singleton (p : node t) : node list t =
  let* n = p in
  return [ n ]

let parse_many_node_lists (p : node list t) : node list t =
 fun st0 ->
  let rec go acc consumed st =
    match p st with
    | POk (nodes, st', c1) -> (
        let acc = List.rev_append nodes acc in
        match go acc (consumed || c1) st' with
        | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
        | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
    | PFail (_, _, false) -> POk (List.rev acc, st, consumed)
    | PFail _ as e -> e
  in
  go [] false st0

let parse_end_env_name : (pos * string) t =
  let* _ = string "\\end{" in
  let* pos = get_position in
  let* name = take_while1 is_symbolic in
  let* _ = char '}' in
  return (pos, name)

(* Parse a single argument according to its type. *)
let rec parse_arg arg_type =
  let* _ = char '{' in
  let* pos = get_position in
  let* result =
    match arg_type with
    | At_seq ->
        let* nodes = parse_seq_body () in
        return (Arg_nodes (pos, nodes))
    | At_sym ->
        let* name = take_while1 is_symbolic in
        return (Arg_symbol (pos, name))
    | At_num -> (
        let* s = take_while1 (fun c -> is_digit c || c = '-') in
        match int_of_string_opt s with
        | Some n -> return (Arg_number (pos, n))
        | None -> fail ("invalid number: " ^ s))
    | At_url ->
        let* url = take_while1 is_url_char in
        return (Arg_url (pos, url))
    | At_align_spec ->
        let* spec = take_while1 is_align_char in
        return (Arg_align (pos, parse_col_specs spec))
  in
  let* _ = char '}' in
  return result

(* parse_seq_body and parse_seq_item are mutually recursive with parse_cmd. *)
and parse_seq_body () st = parse_many_node_lists parse_seq_item st

and parse_seq_like_item ~text_p ~allow_single_quote st =
  (let* c = look_ahead any_char in
   match c with
   | '%' -> parse_comment *> return []
   | '\\' ->
       let* display = starts_with "\\[" in
       if display then singleton parse_display_math else singleton parse_cmd
   | '{' -> singleton parse_group
   | '$' -> singleton parse_inline_math
   | '[' | ']' -> singleton parse_bracket_text
   | '`' ->
       try_ parse_quotation
       >>| (fun n -> [ n ])
       <|> (parse_one_char_text '`' >>| fun n -> [ n ])
   | '\'' when allow_single_quote -> singleton (parse_one_char_text '\'')
   | _ -> singleton text_p)
    st

and parse_seq_item st =
  parse_seq_like_item ~text_p:parse_text_node ~allow_single_quote:false st

(* ``...'' → [NQuotation]. [try_ (string "``")] makes the whole
   parser rewindable so a lone ` falls through to [parse_one_char_text]. *)
and parse_quotation st =
  (let* pos = get_position in
   let* _ = try_ (string "``") in
   let rec go acc st =
     (try_ (string "''") *> return (NQuotation (pos, List.rev acc))
     <|>
     let* nodes = parse_quot_item in
     go (List.rev_append nodes acc))
       st
   in
   go [])
    st

and parse_quot_item st =
  parse_seq_like_item ~text_p:parse_text_node_in_quot ~allow_single_quote:true
    st

(* Optional [opt1,opt2,...] argument list. *)
and parse_options st =
  ( option_maybe
      (try_
         (let* content =
            char '[' *> take_while (fun c -> c <> ']') <* char ']'
          in
          return (if content = "" then [] else String.split_on_char ',' content)))
  >>| function
    | None -> []
    | Some xs -> xs )
    st

and parse_group st =
  (let* pos = get_position in
   let* nodes = char '{' *> parse_seq_body () <* char '}' in
   return (NGroup (pos, nodes)))
    st

and parse_inline_math st =
  (let* pos = get_position in
   let* nodes = char '$' *> Math.parse_math_body ~display:false in
   return (NMath (pos, Math_inline, nodes)))
    st

and parse_display_math st =
  (let* pos = get_position in
   let* nodes = try_ (string "\\[") *> Math.parse_math_body ~display:true in
   return (NMath (pos, Math_display, nodes)))
    st

(* \name[opts]{arg1}{arg2}... *)
and parse_cmd st =
  (let* pos = get_position in
   let* next = char '\\' *> option_maybe any_char in
   match next with
   | None -> fail "unexpected end of input"
   | Some c when String.contains "%\\&#_{}\n$" c ->
       return (NText (pos, String.make 1 c))
   | Some ']' -> unexpected "display math end"
   | Some c when not (is_symbolic c) -> fail "expected matching character"
   | Some c -> (
       let* rest = take_while is_symbolic in
       let* () = optional (char ' ') in
       let name = String.make 1 c ^ rest in
       match name with
       | "begin" -> parse_begin_env pos
       | "end" -> unexpected "\\end without matching \\begin"
       | _ -> parse_command_with_args pos name))
    st

and parse_command_with_args pos name st =
  (let* opts = parse_options in
   let arg_types =
     match SMap.find_opt name cmd_args with Some xs -> xs | None -> []
   in
   let* args = collect_list parse_arg arg_types in
   return (NCmd (pos, name, opts, args)))
    st

(* \begin{envname}[opts] body \end{envname} *)
and parse_begin_env begin_pos st =
  (let* name = char '{' *> take_while1 is_symbolic <* char '}' in
   let* opts = parse_options in
   match name with
   | "verbatim" -> parse_verbatim_env begin_pos name opts
   | "tabular" | "tabular*" -> parse_table_env begin_pos name opts
   | "code" -> optional (char '\n') *> parse_regular_env begin_pos name opts
   | "align*" -> parse_align_env begin_pos
   | _ -> parse_regular_env begin_pos name opts)
    st

and parse_regular_env begin_pos name opts st =
  (let* body = parse_env_body name in
   let* end_pos = get_position in
   return (NEnv (begin_pos, end_pos, name, opts, body)))
    st

(* Parse an environment body until \end{name}. Skips comments inline. *)
and parse_env_body env_name st =
  let is_code = env_name = "code" in
  let rec go acc st =
    match parse_end_env_name st with
    | POk ((pos, n), st', _) ->
        if n = env_name then POk (List.rev acc, st', true)
        else
          PFail
            ( pos,
              lazy
                ("expected \\end{" ^ env_name ^ "} but found \\end{" ^ n ^ "}"),
              true )
    | PFail (_, _, false) -> (
        (* Skip comments; if any were skipped, re-check for \end{ before
         trying to parse a node. *)
        let rec skip_comments st skipped =
          match try_ parse_comment st with
          | POk (_, st', _) -> skip_comments st' true
          | PFail _ -> (st, skipped)
        in
        let st, skipped = skip_comments st false in
        if skipped then go acc st
        else
          let node_p = if is_code then parse_code_node else parse_env_node in
          match node_p st with
          | POk (n, st', c1) -> (
              match go (n :: acc) st' with
              | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
              | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
          | PFail _ as e -> e)
    | PFail _ as e -> e
  in
  go [] st

(* Code envs: only commands and math get parsed; everything else is text. *)
and parse_code_node st =
  (let* c = look_ahead any_char in
   match c with
   | '\\' ->
       let* display = starts_with "\\[" in
       if display then parse_display_math else parse_cmd
   | '$' -> parse_inline_math
   | _ -> parse_code_text)
    st

and parse_code_text st =
  (let* pos = get_position in
   let* text = take_while1 (fun c -> not (c = '\\' || c = '$' || c = '%')) in
   return (NText (pos, text)))
    st

(* Normal env body node parser *)
and parse_env_node st =
  (let* c = look_ahead any_char in
   match c with
   | '\\' ->
       let* display = starts_with "\\[" in
       if display then parse_display_math else parse_cmd
   | '{' -> parse_group
   | '$' -> parse_inline_math
   | '[' | ']' -> parse_bracket_text
   | '`' -> try_ parse_quotation <|> parse_one_char_text '`'
   | _ -> parse_text_node)
    st

(* Verbatim env: raw text until \end{verbatim} *)
and parse_verbatim_env begin_pos name opts st =
  (let* () = optional (char '\n') in
   let* pos = get_position in
   let* body = many_till_chars "\\end{verbatim}" in
   let* end_pos = get_position in
   return (NEnv (begin_pos, end_pos, name, opts, [ NText (pos, body) ])))
    st

(* Tabular env *)
and parse_table_env begin_pos name opts st =
  (let* spec = char '{' *> take_while1 is_align_char <* char '}' in
   let spec = parse_col_specs spec in
   let* rows = parse_table_rows name spec in
   let* end_pos = get_position in
   return (NTable (begin_pos, end_pos, name, opts, spec, rows)))
    st

and parse_table_rows env_name spec st =
  let spec_arr = Array.of_list spec in
  let num_cols = Array.length spec_arr in
  let spec_at i = if i < num_cols then spec_arr.(i) else Col_left in
  let fresh_cell pos align =
    { cell_pos = pos; cell_align = align; cell_colspan = 1; cell_body = [] }
  in
  let parse_row_sep : unit t = try_ (expect_string "\\\\") in
  let parse_hrule : unit t =
    try_ (string "\\hrule") *> optional (char ' ') *> return ()
  in
  let parse_multicolumn : (pos * arg * arg * arg) t =
    try_
      (let* pos = get_position in
       let* _ = string "\\multicolumn" in
       let* n = parse_arg At_num in
       let* a = parse_arg At_align_spec in
       let* b = parse_arg At_seq in
       return (pos, n, a, b))
  in
  let rec go rows_rev row_borders row_cells_rev current_cell cell_count st =
    match parse_end_env_name st with
    | POk ((pos, n), st', _) ->
        if n <> env_name then
          PFail
            ( pos,
              lazy
                ("expected \\end{" ^ env_name ^ "} but found \\end{" ^ n ^ "}"),
              true )
        else
          (* Handle pending hrule as bottom border on last row. *)
          let final_rows_rev =
            match (row_borders, row_cells_rev, rows_rev) with
            | Border_top, [], r :: rest_rev ->
                let border' =
                  match r.row_borders with
                  | Border_none -> Border_bottom
                  | Border_top -> Border_both
                  | Border_bottom -> Border_bottom
                  | Border_both -> Border_both
                in
                { r with row_borders = border' } :: rest_rev
            | _ -> rows_rev
          in
          POk (List.rev final_rows_rev, st', true)
    | PFail (_, _, false) -> (
        (* Try row separator: \\ *)
        match parse_row_sep st with
        | POk (_, st', _) ->
            let row' = finish_row row_borders (current_cell :: row_cells_rev) in
            go (row' :: rows_rev) Border_none []
              (fresh_cell st'.pos (spec_at 0))
              1 st'
        | PFail (_, _, false) -> (
            (* Try cell separator: & *)
            match option_maybe (char '&') st with
            | POk (Some _, st', _) -> (
                let next_spec =
                  if cell_count < num_cols then spec_at cell_count else Col_left
                in
                match get_position st' with
                | POk (pos, st'', _) ->
                    go rows_rev row_borders
                      (current_cell :: row_cells_rev)
                      (fresh_cell pos next_spec) (cell_count + 1) st''
                | PFail _ as e -> e)
            | POk (None, _, _) | PFail _ -> (
                (* Try \hrule *)
                match parse_hrule st with
                | POk (_, st', _) ->
                    go rows_rev Border_top row_cells_rev current_cell cell_count
                      st'
                | PFail _ -> (
                    (* Try \multicolumn *)
                    match parse_multicolumn st with
                    | POk
                        ( ( pos,
                            Arg_number (_, n),
                            Arg_align (_, [ al ]),
                            Arg_nodes (_, body) ),
                          st',
                          _ ) ->
                        let mcell =
                          {
                            cell_pos = pos;
                            cell_align = al;
                            cell_colspan = n;
                            cell_body = List.rev body;
                          }
                        in
                        let next_spec = spec_at (cell_count + n - 1) in
                        go rows_rev row_borders (mcell :: row_cells_rev)
                          (fresh_cell pos next_spec) (cell_count + n) st'
                    | POk ((pos, _, _, _), _, _) ->
                        PFail
                          ( pos,
                            lazy
                              "\\multicolumn requires {N}{alignment}{content}",
                            true )
                    | PFail _ -> (
                        (* Parse a node for the current cell *)
                        let cell_node =
                          choice
                            [
                              try_
                                (parse_comment
                                *> (parse_text_node <|> parse_cell_text));
                              try_ parse_cmd;
                              parse_group;
                              try_ parse_display_math;
                              parse_inline_math;
                              parse_cell_text;
                            ]
                        in
                        match cell_node st with
                        | POk (n, st', c1) -> (
                            let cell' =
                              {
                                current_cell with
                                cell_body = n :: current_cell.cell_body;
                              }
                            in
                            match
                              go rows_rev row_borders row_cells_rev cell'
                                cell_count st'
                            with
                            | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
                            | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
                        | PFail _ as e -> e))))
        | PFail _ as e -> e)
    | PFail _ as e -> e
  in
  go [] Border_none [] (fresh_cell st.pos (spec_at 0)) 1 st

(* align* env: \begin{align*} math & math \\ ... \end{align*}
   Parses in text mode but each cell contains math content.
   Produces NMath with Math_display and a single Math_align node. *)
and parse_align_env begin_pos st =
  let cell_end =
    try_
      (Math.skip_math_spaces
      *> look_ahead
           (expect_string "\\\\" <|> expect_string "\\end{" <|> expect_char '&')
      )
  in
  let filter_newlines nodes =
    List.filter (function Math_op ("\n", _) -> false | _ -> true) nodes
  in
  let skip_ws = skip_while (fun c -> c = ' ' || c = '\n') in
  let consume_delim =
    try_ (string "\\\\" *> return `Row)
    <|> try_ (char '&' *> return `Cell)
    <|> string "\\end{align*}" *> return `End
  in
  let finish_rows rows_rev cells_rev =
    let row = List.rev cells_rev in
    let rows = List.rev (row :: rows_rev) in
    List.filter (fun r -> not (List.for_all (fun c -> c = []) r)) rows
  in
  let default_align num_cols =
    match num_cols with
    | 0 -> []
    | 1 -> [ Col_right ]
    | n ->
        List.init n (fun i ->
            if i = 0 then Col_right
            else if i = n - 1 then Col_left
            else Col_center)
  in
  let rec go rows_rev cells_rev st =
    bind_step (Math.parse_m_list ~end_p:cell_end st) (fun nodes st1 ->
        let cells_rev = filter_newlines nodes :: cells_rev in
        bind_step (consume_delim st1) (fun delim st2 ->
            match delim with
            | `Cell -> go rows_rev cells_rev st2
            | `Row ->
                let row = List.rev cells_rev in
                bind_step (skip_ws st2) (fun () st3 ->
                    go (row :: rows_rev) [] st3)
            | `End ->
                let rows = finish_rows rows_rev cells_rev in
                let num_cols =
                  List.fold_left (fun m r -> max m (List.length r)) 0 rows
                in
                return
                  (NMath
                     ( begin_pos,
                       Math_display,
                       [ Math_align (default_align num_cols, rows) ] ))
                  st2))
  in
  (let* _ = optional (char '\n') in
   let* _ = skip_ws in
   go [] [])
    st

and parse_cell_text st =
  (let* pos = get_position in
   let* text = take_while1 (fun c -> (not (is_special c)) && c <> '&') in
   return (NText (pos, text)))
    st

let parse_sequence : node list t = parse_many_node_lists parse_seq_item

let parse_document ~source_name input : (node list, Error.parse_error) result =
  run (parse_sequence <* eof) ~source_name input
