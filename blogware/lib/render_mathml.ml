(* Renders Syntax.math_node trees into MathML elements using the Html builder. *)

open Html
open Syntax

let is_math_special c = match c with '<' | '>' | '&' -> true | _ -> false

let escape_math_text (t : Text.t) (buf : Buffer.t) : unit =
  if not (Text.exists is_math_special t) then Text.output_to_buffer buf t
  else
    Text.iter
      (fun c ->
        match c with
        | '<' -> Buffer.add_string buf "&lt;"
        | '>' -> Buffer.add_string buf "&gt;"
        | '&' -> Buffer.add_string buf "&amp;"
        | c -> Buffer.add_char buf c)
      t

let mathcal_codepoint = function
  | 'A' -> Some 0x1D49C
  | 'B' -> Some 0x212C
  | 'C' -> Some 0x1D49E
  | 'D' -> Some 0x1D49F
  | 'E' -> Some 0x2130
  | 'F' -> Some 0x2131
  | 'G' -> Some 0x1D4A2
  | 'H' -> Some 0x210B
  | 'I' -> Some 0x2110
  | 'J' -> Some 0x1D4A5
  | 'K' -> Some 0x1D4A6
  | 'L' -> Some 0x2112
  | 'M' -> Some 0x2133
  | 'N' -> Some 0x1D4A9
  | 'O' -> Some 0x1D4AA
  | 'P' -> Some 0x1D4AB
  | 'Q' -> Some 0x1D4AC
  | 'R' -> Some 0x211B
  | 'S' -> Some 0x1D4AE
  | 'T' -> Some 0x1D4AF
  | 'U' -> Some 0x1D4B0
  | 'V' -> Some 0x1D4B1
  | 'W' -> Some 0x1D4B2
  | 'X' -> Some 0x1D4B3
  | 'Y' -> Some 0x1D4B4
  | 'Z' -> Some 0x1D4B5
  | 'a' -> Some 0x1D4B6
  | 'b' -> Some 0x1D4B7
  | 'c' -> Some 0x1D4B8
  | 'd' -> Some 0x1D4B9
  | 'e' -> Some 0x212F
  | 'f' -> Some 0x1D4BB
  | 'g' -> Some 0x210A
  | 'h' -> Some 0x1D4BD
  | 'i' -> Some 0x1D4BE
  | 'j' -> Some 0x1D4BF
  | 'k' -> Some 0x1D4C0
  | 'l' -> Some 0x1D4C1
  | 'm' -> Some 0x1D4C2
  | 'n' -> Some 0x1D4C3
  | 'o' -> Some 0x2134
  | 'p' -> Some 0x1D4C5
  | 'q' -> Some 0x1D4C6
  | 'r' -> Some 0x1D4C7
  | 's' -> Some 0x1D4C8
  | 't' -> Some 0x1D4C9
  | 'u' -> Some 0x1D4CA
  | 'v' -> Some 0x1D4CB
  | 'w' -> Some 0x1D4CC
  | 'x' -> Some 0x1D4CD
  | 'y' -> Some 0x1D4CE
  | 'z' -> Some 0x1D4CF
  | _ -> None

let render_mathcal_text t =
  let buf = Buffer.create (Text.length t) in
  Text.iter
    (fun c ->
      match mathcal_codepoint c with
      | Some cp -> Buffer.add_utf_8_uchar buf (Uchar.of_int cp)
      | None -> Buffer.add_char buf c)
    t;
  mi_ [] (escape_math_text (Text.of_string (Buffer.contents buf)))

(* Map bit-index -> tag helper.
     bit 2 = big-op, bit 1 = has-sub, bit 0 = has-sup *)
let col_align_attrs (specs : col_spec list) : attribute list =
  if specs = [] then []
  else
    let spec_to_text = function
      | Col_left -> Text.of_string "left"
      | Col_right -> Text.of_string "right"
      | Col_center -> Text.of_string "center"
    in
    [
      attr "columnalign"
        (Text.append
           (Text.concat (Text.of_char ' ') (List.map spec_to_text specs))
           (Text.of_char ' '));
    ]

(* --- Main math-node renderer --- *)

let rec render_math_node (n : math_node) : Html.t =
  match n with
  | Math_text t -> mi_ [] (escape_math_text t)
  | Math_num s -> mn_ [] (raw s)
  | Math_op (op, stretchy) ->
      if stretchy then mo_ [] (escape_math_text op)
      else
        mo_ [ attr "stretchy" (Text.of_string "false") ] (escape_math_text op)
  | Math_sym c -> mi_ [] (raw (Text.of_char c))
  | Math_group ns -> mrow_ [] (concat (List.map render_math_node ns))
  | Math_cmd (sym, args) -> render_math_cmd sym args
  | Math_frac (num, denom) ->
      mfrac_ []
        (mrow_ [] (render_math_node num) ++ mrow_ [] (render_math_node denom))
  | Math_term (nucleus, msub, msup) -> render_math_term nucleus msub msup
  | Math_align (specs, rows) ->
      mtable_ (col_align_attrs specs)
        (concat
           (List.map
              (fun row ->
                mtr_ []
                  (concat
                     (List.map
                        (fun cell ->
                          mtd_ []
                            (mrow_ [] (concat (List.map render_math_node cell))))
                        row)))
              rows))

and render_math_cmd sym args =
  let render_op op stretchy =
    if stretchy then mo_ [] (escape_math_text op)
    else mo_ [ attr "stretchy" (Text.of_string "false") ] (escape_math_text op)
  in
  match (sym, args) with
  | S_frac, [ num; denom ] ->
      mrow_ []
        (mfrac_ []
           (mrow_ [] (render_math_node num) ++ mrow_ [] (render_math_node denom)))
  | S_binom, [ n; k ] ->
      mrow_ []
        (mo_ [] (raw (Text.of_string "("))
        ++ mfrac_
             [ attr "linethickness" (Text.of_string "0") ]
             (mrow_ [] (render_math_node n) ++ mrow_ [] (render_math_node k))
        ++ mo_ [] (raw (Text.of_string ")")))
  | S_operatorname, [ Math_op (s, _) ] -> mi_ [] (escape_math_text s)
  | S_mathrm, [ Math_op (s, _) ] ->
      mi_ [ attr "mathvariant" (Text.of_string "normal") ] (escape_math_text s)
  | S_mathcal, [ Math_op (s, _) ] -> render_mathcal_text s
  | S_left, [ Math_op (op, stretchy) ] -> render_op op stretchy
  | S_right, [ Math_op (op, stretchy) ] -> render_op op stretchy
  | _, [] ->
      let repl =
        match replacement_text sym with
        | Some r -> r
        | None -> sym_to_string sym
      in
      mo_ [] (raw (Text.of_string repl))
  | _, _ ->
      mo_ [] (raw (Text.of_string (sym_to_string sym)))
      ++ concat (List.map render_math_node args)

and render_math_term nucleus msub msup =
  let n = render_math_node nucleus in
  let sub_sup =
    match nucleus with
    | Math_cmd ((S_sum | S_prod | S_int | S_lim), _) ->
        (munder_, mover_, munderover_)
    | _ -> (msub_, msup_, msubsup_)
  in
  match (sub_sup, msub, msup) with
  | _, None, None -> n
  | (tag, _, _), Some sub, None -> tag [] (n ++ render_math_node sub)
  | (_, tag, _), None, Some sup -> tag [] (n ++ render_math_node sup)
  | (_, _, tag), Some sub, Some sup ->
      tag [] (n ++ render_math_node sub ++ render_math_node sup)

(* Render a full math element. *)
let render_math (disp : math_display) (nodes : math_node list) : Html.t =
  let disp_attr =
    match disp with
    | Math_display -> [ attr "display" (Text.of_string "block") ]
    | Math_inline -> []
  in
  math_
    (attr "xmlns" (Text.of_string "http://www.w3.org/1998/Math/MathML")
    :: class_ (Text.of_string "math")
    :: disp_attr)
    (concat (List.map render_math_node nodes))
