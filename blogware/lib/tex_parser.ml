open Parser
open Syntax

let is_alpha_num c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

let is_digit c = c >= '0' && c <= '9'

let is_special c =
  match c with
  | '%' | '{' | '}' | '\\' | '[' | ']' | '&' | '$' -> true
  | _ -> false

let is_symbolic c = match c with '*' | '-' | '.' -> true | c -> is_alpha_num c

let is_url_char c =
  match c with
  | '-' | '.' | '_' | '~' | ':' | '/' | '?' | '#' | '[' | ']' | '@' | '!' | '$'
  | '&' | '(' | ')' | '*' | '+' | ',' | ';' | '%' | '=' | '\'' ->
      true
  | c -> is_alpha_num c

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

  let is_operator_like = function
    | Math_op _ -> true
    | Math_cmd (S_left, _) -> true
    | _ -> false

  let parse_escaped_brace : Text.t t =
    let* c = expect_char '\\' *> one_of "{}" in
    return (Text.of_char c)

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
    return (Math_op (Text.of_char c, false))

  let parse_math_symbol : math_node t =
    let* c = satisfy is_letter in
    return (Math_text (Text.of_char c))

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
    (let* nodes = expect_char '{' *> parse_m_list ~end_p:(expect_char '}') in
     return (Math_group nodes))
      st

  and parse_math_control st =
    (let* _ = expect_char '\\' in
     let* esc = option_maybe (one_of "%{}\\^_") in
     match esc with
     | Some c -> return (Math_op (Text.of_char c, false))
     | None -> (
         let* c = look_ahead any_char in
         if c = ']' then unexpected "\\] (unmatched display math delimiter)"
         else
           let* name = take_while1 is_symbolic in
           let sym = resolve_sym name in
           match SMap.find_opt name math_cmds with
           | Some _ when sym = S_left || sym = S_right ->
               let* () = skip_math_spaces in
               let* op =
                 try_ parse_escaped_brace
                 <|> let* c = satisfy is_math_op in
                     return (Text.of_char c)
               in
               return (Math_cmd (sym, [ Math_op (op, true) ]))
           | Some arg_types ->
               let rec collect_args = function
                 | [] -> return []
                 | t :: rest ->
                     let* a = parse_math_cmd_arg t in
                     let* xs = collect_args rest in
                     return (a :: xs)
               in
               let* args = collect_args arg_types in
               return (Math_cmd (sym, args))
           | None -> return (Math_cmd (sym, []))))
      st

  and parse_math_cmd_arg t st =
    (match t with
    | Math_arg_expr ->
        let* nodes =
          skip_math_spaces *> expect_char '{'
          *> parse_m_list ~end_p:(expect_char '}')
        in
        return (Math_group nodes)
    | Math_arg_sym ->
        let* sym =
          skip_math_spaces *> expect_char '{' *> take_while1 is_symbolic
          <* expect_char '}'
        in
        return (Math_op (sym, false)))
      st

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
  expect_char '%' *> skip_while (fun c -> c <> '\n') *> skip_char '\n'

let parse_text_node : node t =
  let* pos = get_position in
  let* text = take_while1 (fun c -> (not (is_special c)) && c <> '`') in
  return (NText (pos, text))

let parse_text_node_in_quot : node t =
  let* pos = get_position in
  let* text =
    take_while1 (fun c -> (not (is_special c)) && c <> '`' && c <> '\'')
  in
  return (NText (pos, text))

let parse_one_char_text (c : char) : node t =
  let* pos = get_position in
  let* _ = expect_char c in
  return (NText (pos, Text.of_char c))

let parse_bracket_text : node t =
  let* pos = get_position in
  let* c = one_of "[]" in
  return (NText (pos, Text.of_char c))

(* Parse a {...} group of n column-spec letters. *)
let parse_col_specs (s : Text.t) : col_spec list =
  Text.fold_right
    (fun c acc ->
      match c with
      | 'l' -> Col_left :: acc
      | 'r' -> Col_right :: acc
      | 'c' -> Col_center :: acc
      | _ -> acc)
    s []

let finish_cell (cell : cell) : cell =
  { cell with cell_body = List.rev cell.cell_body }

let finish_row (row_borders : row_border) (row_cells_rev : cell list) : row =
  { row_borders; row_cells = List.rev_map finish_cell row_cells_rev }

let collect_list (f : 'a -> 'b t) (xs : 'a list) : 'b list t =
 fun st0 ->
  let rec go acc consumed st = function
    | [] -> POk (List.rev acc, st, consumed)
    | x :: rest -> (
        match f x st with
        | POk (a, st', c) -> go (a :: acc) (consumed || c) st' rest
        | PFail _ as e -> e)
  in
  go [] false st0 xs

let optional_node (p : node t) : node option t =
  let* n = p in
  return (Some n)

let parse_many_nodes (p : node option t) : node list t =
 fun st0 ->
  let rec go acc consumed st =
    match p st with
    | POk (None, st', c) -> go acc (consumed || c) st'
    | POk (Some n, st', c) -> go (n :: acc) (consumed || c) st'
    | PFail (_, _, false) -> POk (List.rev acc, st, consumed)
    | PFail _ as e -> e
  in
  go [] false st0

let parse_end_env_name : (pos * Text.t) t =
  let* _ = expect_string "\\end{" in
  let* pos = get_position in
  let* name = take_while1 is_symbolic in
  let* _ = expect_char '}' in
  return (pos, name)

(* Parse a single argument according to its type. *)
let rec parse_arg arg_type =
  let* _ = expect_char '{' in
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
        let s_str = Text.to_string s in
        match int_of_string_opt s_str with
        | Some n -> return (Arg_number (pos, n))
        | None -> fail ("invalid number: " ^ s_str))
    | At_url ->
        let* url = take_while1 is_url_char in
        return (Arg_url (pos, url))
    | At_align_spec ->
        let* spec = take_while1 is_align_char in
        return (Arg_align (pos, parse_col_specs spec))
  in
  let* _ = expect_char '}' in
  return result

(* parse_seq_body and parse_seq_item are mutually recursive with parse_cmd. *)
and parse_seq_body () st = parse_many_nodes parse_seq_item st

and parse_seq_like_item ~text_p ~allow_single_quote st =
  (let* next = peek_char in
   match next with
   | None -> fail "unexpected end of input"
   | Some '%' -> parse_comment *> return None
   | Some '\\' ->
       let* display = starts_with "\\[" in
       if display then optional_node parse_display_math
       else optional_node parse_cmd
   | Some '{' -> optional_node parse_group
   | Some '$' -> optional_node parse_inline_math
   | Some ('[' | ']') -> optional_node parse_bracket_text
   | Some '`' ->
       try_ parse_quotation
       >>| (fun n -> Some n)
       <|> optional_node (parse_one_char_text '`')
   | Some '\'' when allow_single_quote ->
       optional_node (parse_one_char_text '\'')
   | Some _ -> optional_node text_p)
    st

and parse_seq_item st =
  parse_seq_like_item ~text_p:parse_text_node ~allow_single_quote:false st

and parse_quotation st =
  (let* pos = get_position in
   let* _ = try_ (expect_string "``") in
   let rec go acc st =
     (try_ (expect_string "''") *> return (NQuotation (pos, List.rev acc))
     <|>
     let* node = parse_quot_item in
     match node with None -> go acc | Some n -> go (n :: acc))
       st
   in
   go [])
    st

and parse_quot_item st =
  parse_seq_like_item ~text_p:parse_text_node_in_quot ~allow_single_quote:true
    st

(* Optional [opt1,opt2,...] argument list. Returns Text.t list. *)
and parse_options st =
  let bracketed =
    try_
      (let* content =
         expect_char '[' *> take_while (fun c -> c <> ']') <* expect_char ']'
       in
       return (if Text.is_empty content then [] else Text.split_on content ","))
  in
  (bracketed <|> return []) st

and parse_group st =
  (let* pos = get_position in
   let* nodes = expect_char '{' *> parse_seq_body () <* expect_char '}' in
   return (NGroup (pos, nodes)))
    st

and parse_inline_math st =
  (let* pos = get_position in
   let* nodes = expect_char '$' *> Math.parse_math_body ~display:false in
   return (NMath (pos, Math_inline, nodes)))
    st

and parse_display_math st =
  (let* pos = get_position in
   let* nodes =
     try_ (expect_string "\\[") *> Math.parse_math_body ~display:true
   in
   return (NMath (pos, Math_display, nodes)))
    st

(* \name[opts]{arg1}{arg2}... *)
and parse_cmd st =
  (let* pos = get_position in
   let* () = expect_char '\\' in
   let* next = peek_char in
   match next with
   | None -> fail "unexpected end of input"
   | Some c
     when match c with
          | '%' | '\\' | '&' | '#' | '_' | '{' | '}' | '\n' | '$' -> true
          | _ -> false ->
       let* c = any_char in
       return (NText (pos, Text.of_char c))
   | Some ']' ->
       let* _ = any_char in
       unexpected "display math end"
   | Some c when not (is_symbolic c) ->
       let* _ = any_char in
       fail "expected matching character"
   | Some _ ->
       let* name = take_while1 is_symbolic in
       let* () = skip_char ' ' in
       if Text.equal_string name "begin" then parse_begin_env pos
       else if Text.equal_string name "end" then
         unexpected "\\end without matching \\begin"
       else
         let sym = resolve_sym name in
         parse_command_with_args pos sym name)
    st

and parse_command_with_args pos sym name st =
  (let* opts = parse_options in
   let arg_types =
     match SMap.find_opt name cmd_args with Some xs -> xs | None -> []
   in
   let* args = collect_list parse_arg arg_types in
   return (NCmd (pos, sym, opts, args)))
    st

(* \begin{envname}[opts] body \end{envname} *)
and parse_begin_env begin_pos st =
  (let* name = expect_char '{' *> take_while1 is_symbolic <* expect_char '}' in
   let* opts = parse_options in
   let sym = resolve_sym name in
   match sym with
   | S_verbatim -> parse_verbatim_env begin_pos sym opts
   | S_tabular | S_tabular_star -> parse_table_env begin_pos sym name opts
   | S_code -> skip_char '\n' *> parse_regular_env begin_pos sym name opts
   | S_align_star -> parse_align_env begin_pos
   | _ -> parse_regular_env begin_pos sym name opts)
    st

and parse_regular_env begin_pos sym name opts st =
  (let* body = parse_env_body name in
   let* end_pos = get_position in
   return (NEnv (begin_pos, end_pos, sym, opts, body)))
    st

(* Parse an environment body until \end{name}. Skips comments inline. *)
and parse_env_body env_name st =
  let is_code = Text.equal_string env_name "code" in
  let rec go acc st =
    match starts_with "\\end{" st with
    | POk (true, _, _) -> (
        match parse_end_env_name st with
        | POk ((pos, n), st', _) ->
            if Text.equal n env_name then POk (List.rev acc, st', true)
            else
              PFail
                ( pos,
                  lazy
                    ("expected \\end{" ^ Text.to_string env_name
                   ^ "} but found \\end{" ^ Text.to_string n ^ "}"),
                  true )
        | PFail _ as e -> e)
    | PFail _ as e -> e
    | POk (false, _, _) -> (
        let rec skip_comments st skipped =
          match peek_char st with
          | POk (Some '%', _, _) -> (
              match parse_comment st with
              | POk (_, st', _) -> skip_comments st' true
              | PFail _ -> (st, skipped))
          | _ -> (st, skipped)
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
  in
  go [] st

and parse_code_node st =
  (let* next = peek_char in
   match next with
   | None -> fail "unexpected end of input"
   | Some '\\' ->
       let* display = starts_with "\\[" in
       if display then parse_display_math else parse_cmd
   | Some '$' -> parse_inline_math
   | Some _ -> parse_code_text)
    st

and parse_code_text st =
  (let* pos = get_position in
   let* text = take_while1 (fun c -> not (c = '\\' || c = '$' || c = '%')) in
   return (NText (pos, text)))
    st

and parse_env_node st =
  (let* next = peek_char in
   match next with
   | None -> fail "unexpected end of input"
   | Some '\\' ->
       let* display = starts_with "\\[" in
       if display then parse_display_math else parse_cmd
   | Some '{' -> parse_group
   | Some '$' -> parse_inline_math
   | Some ('[' | ']') -> parse_bracket_text
   | Some '`' -> try_ parse_quotation <|> parse_one_char_text '`'
   | Some _ -> parse_text_node)
    st

and parse_verbatim_env begin_pos sym opts st =
  (let* () = skip_char '\n' in
   let* pos = get_position in
   let* body = many_till_chars "\\end{verbatim}" in
   let* end_pos = get_position in
   return (NEnv (begin_pos, end_pos, sym, opts, [ NText (pos, body) ])))
    st

and parse_table_env begin_pos sym name opts st =
  (let* spec =
     expect_char '{' *> take_while1 is_align_char <* expect_char '}'
   in
   let spec = parse_col_specs spec in
   let* rows = parse_table_rows name spec in
   let* end_pos = get_position in
   return (NTable (begin_pos, end_pos, sym, opts, spec, rows)))
    st

and parse_table_rows env_name spec st =
  let spec_arr = Array.of_list spec in
  let num_cols = Array.length spec_arr in
  let spec_at i = if i < num_cols then spec_arr.(i) else Col_left in
  let fresh_cell pos align =
    { cell_pos = pos; cell_align = align; cell_colspan = 1; cell_body = [] }
  in
  let parse_hrule : unit t = try_ (expect_string "\\hrule") *> skip_char ' ' in
  let parse_multicolumn : (pos * arg * arg * arg) t =
    try_
      (let* pos = get_position in
       let* _ = expect_string "\\multicolumn" in
       let* n = parse_arg At_num in
       let* a = parse_arg At_align_spec in
       let* b = parse_arg At_seq in
       return (pos, n, a, b))
  in
  let cell_node =
    choice
      [
        try_ (parse_comment *> (parse_text_node <|> parse_cell_text));
        try_ parse_cmd;
        parse_group;
        try_ parse_display_math;
        parse_inline_math;
        parse_cell_text;
      ]
  in
  let table_item =
    parse_end_env_name
    >>| (fun end_env -> `End end_env)
    <|> (let* _ = expect_string "\\\\" in
         let* pos = get_position in
         return (`Row_sep pos))
    <|> (let* _ = expect_char '&' in
         let* pos = get_position in
         return (`Cell_sep pos))
    <|> parse_hrule *> return `HRule
    <|> (parse_multicolumn >>| fun col -> `Multicolumn col)
    <|> (cell_node >>| fun n -> `Cell n)
  in
  let finish_table row_borders row_cells_rev rows_rev st' =
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
  in
  let rec go rows_rev row_borders row_cells_rev current_cell cell_count st =
    bind_step (table_item st) (fun item st' ->
        match item with
        | `End (pos, n) ->
            if not (Text.equal n env_name) then
              PFail
                ( pos,
                  lazy
                    ("expected \\end{" ^ Text.to_string env_name
                   ^ "} but found \\end{" ^ Text.to_string n ^ "}"),
                  false )
            else finish_table row_borders row_cells_rev rows_rev st'
        | `Row_sep pos ->
            let row' = finish_row row_borders (current_cell :: row_cells_rev) in
            go (row' :: rows_rev) Border_none []
              (fresh_cell pos (spec_at 0))
              1 st'
        | `Cell_sep pos ->
            let next_spec =
              if cell_count < num_cols then spec_at cell_count else Col_left
            in
            go rows_rev row_borders
              (current_cell :: row_cells_rev)
              (fresh_cell pos next_spec) (cell_count + 1) st'
        | `HRule ->
            go rows_rev Border_top row_cells_rev current_cell cell_count st'
        | `Multicolumn
            (pos, Arg_number (_, n), Arg_align (_, [ al ]), Arg_nodes (_, body))
          ->
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
        | `Multicolumn (pos, _, _, _) ->
            PFail
              (pos, lazy "\\multicolumn requires {N}{alignment}{content}", false)
        | `Cell n ->
            let cell' =
              { current_cell with cell_body = n :: current_cell.cell_body }
            in
            go rows_rev row_borders row_cells_rev cell' cell_count st')
  in
  go [] Border_none [] (fresh_cell st.pos (spec_at 0)) 1 st

and parse_align_env begin_pos st =
  let cell_end =
    try_
      (Math.skip_math_spaces
      *> look_ahead
           (expect_string "\\\\" <|> expect_string "\\end{" <|> expect_char '&')
      )
  in
  let filter_newlines nodes =
    let newline = Text.of_char '\n' in
    List.filter
      (function Math_op (t, _) -> not (Text.equal t newline) | _ -> true)
      nodes
  in
  let skip_ws = skip_while (fun c -> c = ' ' || c = '\n') in
  let consume_delim =
    try_ (expect_string "\\\\" *> return `Row)
    <|> try_ (expect_char '&' *> return `Cell)
    <|> expect_string "\\end{align*}" *> return `End
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
  (let* _ = skip_char '\n' in
   let* _ = skip_ws in
   go [] [])
    st

and parse_cell_text st =
  (let* pos = get_position in
   let* text = take_while1 (fun c -> (not (is_special c)) && c <> '&') in
   return (NText (pos, text)))
    st

let parse_sequence : node list t = parse_many_nodes parse_seq_item

let parse_document ~source_name input : (node list, Error.parse_error) result =
  run (parse_sequence <* eof) ~source_name input
