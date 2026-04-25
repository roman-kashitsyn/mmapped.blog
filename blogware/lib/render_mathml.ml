(* MathML renderer. Mirror of Blogware.Render.MathML.

   Renders Syntax.math_node trees (produced by Parser_math) into MathML
   elements using the Html builder. *)

open Html
open Syntax

(* MathML text escaping: only <, >, &. Matches Blogware.Render.MathML's
   escapeMathText exactly. *)

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

(* Map bit-index -> tag helper. Encoding (from the Haskell source):
     bit 2 = big-op, bit 1 = has-sub, bit 0 = has-sup *)
let sub_sup_tag idx =
  match idx with
  | 0b010 -> msub_
  | 0b001 -> msup_
  | 0b011 -> msubsup_
  | 0b110 -> munder_
  | 0b101 -> mover_
  | 0b111 -> munderover_
  | _ -> mrow_

let nucleus_is_big_op = function
  | Math_cmd (sym, _) -> is_big_op sym
  | _ -> false

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
  | S_operatorname, [ Math_op (s, stretchy) ] -> render_op s stretchy
  | S_mathrm, [ Math_op (s, _) ] ->
      mi_ [ attr "mathvariant" (Text.of_string "normal") ] (escape_math_text s)
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
  match (msub, msup) with
  | None, None -> render_math_node nucleus
  | _ ->
      let is_big = nucleus_is_big_op nucleus in
      let idx =
        (if is_big then 4 else 0)
        + (match msub with Some _ -> 2 | None -> 0)
        + match msup with Some _ -> 1 | None -> 0
      in
      let tag = sub_sup_tag idx in
      tag []
        (render_math_node nucleus
        ++ (match msub with Some n -> render_math_node n | None -> empty)
        ++ match msup with Some n -> render_math_node n | None -> empty)

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
