(* Math-mode parser. Mirror of Blogware.Parser.Math. *)

open Parser_state
open Syntax

(* Symbolic chars allowed in command names. Same as the main parser. *)
let is_symbolic c =
  (c >= 'a' && c <= 'z')
  || (c >= 'A' && c <= 'Z')
  || (c >= '0' && c <= '9')
  || c = '*' || c = '-' || c = '.'

let is_letter c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

let is_digit c = c >= '0' && c <= '9'

let is_math_op c =
  c = '+' || c = '-' || c = '&' || c = '=' || c = ',' || c = ';'
  || c = '[' || c = ']' || c = '|' || c = '(' || c = ')'
  || c = '\n' || c = '<' || c = '>' || c = ':'

let skip_math_spaces : unit t = skip_many (satisfy (fun c -> c = ' '))

(* Whether a node is "operator-like", meaning a following '-' should be
   parsed as a unary minus rather than as a binary operator. *)
let is_operator_like = function
  | Math_op _ -> true
  | Math_cmd ("left", _) -> true
  | _ -> false

(* Parse \{ or \} as an escaped brace character (used by \left/\right). *)
let parse_escaped_brace : string t =
  let* _ = char '\\' in
  let* c = one_of "{}" in
  return (String.make 1 c)

(* Parse a negative number: leading '-' followed by digits. The whole thing
   is wrapped in [try_] so that a bare '-' followed by a non-digit (i.e. a
   subtraction operator) does not consume the dash. *)
let parse_negative_number : math_node t =
  try_ (
    let* _ = char '-' in
    let* digits = many1 (satisfy is_digit) in
    let s = "-" ^ string_of_chars digits in
    return (Math_num s)
  )

let parse_math_number : math_node t =
  let* digits = many1 (satisfy is_digit) in
  return (Math_num (string_of_chars digits))

let parse_math_operator : math_node t =
  let* c = satisfy is_math_op in
  return (Math_op (String.make 1 c, false))

let parse_math_symbol : math_node t =
  let* c = satisfy is_letter in
  return (Math_text (String.make 1 c))

(* Mutually recursive parsers. Each body is written as [fun st -> (...) st]
   so OCaml's [let rec] sees a syntactic function. *)
let rec parse_m_list ~end_p st =
  let rec go acc st =
    match end_p st with
    | POk (_, st', c) -> POk (List.rev acc, st', c)
    | PFail (_, _, true) as e -> e
    | PFail (_, _, false) ->
      match parse_math_term_with_sub_sup ~end_p st with
      | PFail _ as e -> e
      | POk (term, st', c1) ->
        (match go (term :: acc) st' with
         | POk (xs, st'', c2) -> POk (xs, st'', c1 || c2)
         | PFail (p, m, c2) -> PFail (p, m, c1 || c2))
  in
  go [] st

and parse_math_term_with_sub_sup ~end_p st =
  (let* nucleus = parse_math_atom ~end_p in
   collect_sub_sup ~end_p nucleus) st

and collect_sub_sup ~end_p nuc st =
  (let* msub = option_maybe (char '_') in
   match msub with
   | Some _ ->
     let* sub_node = parse_math_atom ~end_p in
     let* msup = option_maybe (char '^') in
     (match msup with
      | Some _ ->
        let* sup_node = parse_math_atom ~end_p in
        return (Math_term (nuc, Some sub_node, Some sup_node))
      | None -> return (Math_term (nuc, Some sub_node, None)))
   | None ->
     let* msup = option_maybe (char '^') in
     (match msup with
      | Some _ ->
        let* sup_node = parse_math_atom ~end_p in
        let* msub2 = option_maybe (char '_') in
        (match msub2 with
         | Some _ ->
           let* sub_node = parse_math_atom ~end_p in
           return (Math_term (nuc, Some sub_node, Some sup_node))
         | None -> return (Math_term (nuc, None, Some sup_node)))
      | None -> return nuc)) st

and parse_math_atom ~end_p st =
  (let* () = skip_math_spaces in
   let alts =
     [ parse_math_group ~end_p
     ; parse_math_control
     ; parse_math_number
     ; parse_math_operator
     ; parse_math_symbol
     ]
   in
   choice alts) st

and parse_math_group ~end_p:_ st =
  (let* _ = char '{' in
   let* nodes = parse_m_list ~end_p:(let* _ = char '}' in return ()) in
   return (Math_group nodes)) st

and parse_math_control st =
  (let* _ = char '\\' in
   let* esc = option_maybe (one_of "%{}\\^_") in
   match esc with
   | Some c -> return (Math_op (String.make 1 c, false))
   | None ->
     let* c = look_ahead any_char in
     if c = ']' then unexpected "\\] (unmatched display math delimiter)"
     else
       let* name_chars = many1 (satisfy is_symbolic) in
       let name = string_of_chars name_chars in
       (match SMap.find_opt name math_cmds with
        | Some _ when name = "left" || name = "right" ->
          let* () = skip_math_spaces in
          let* op =
            try_ parse_escaped_brace
            <|> (let* c = satisfy is_math_op in return (String.make 1 c))
          in
          return (Math_cmd (name, [Math_op (op, true)]))
        | Some arg_types ->
          let rec collect = function
            | [] -> return []
            | t :: rest ->
              let* a = parse_math_cmd_arg t in
              let* xs = collect rest in
              return (a :: xs)
          in
          let* args = collect arg_types in
          return (Math_cmd (name, args))
        | None -> return (Math_cmd (name, [])))) st

and parse_math_cmd_arg t st =
  (match t with
   | Math_arg_expr ->
     let* () = skip_math_spaces in
     let* _ = char '{' in
     let* nodes = parse_m_list ~end_p:(let* _ = char '}' in return ()) in
     return (Math_group nodes)
   | Math_arg_sym ->
     let* () = skip_math_spaces in
     let* _ = char '{' in
     let* sym_chars = many1 (satisfy is_symbolic) in
     let sym = string_of_chars sym_chars in
     let* _ = char '}' in
     return (Math_op (sym, false))) st

(* Parse the body of a math environment.
   - display=true → ends at \]
   - display=false → ends at $ *)
let parse_math_body ~display : math_node list t =
  let end_p =
    if display then
      try_ (let* () = skip_math_spaces in let* _ = string "\\]" in return ())
    else
      try_ (let* () = skip_math_spaces in let* _ = char '$' in return ())
  in
  parse_m_list ~end_p
