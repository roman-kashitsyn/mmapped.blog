(* MathML renderer. Mirror of Blogware.Render.MathML.

   Renders Syntax.math_node trees (produced by Parser_math) into MathML
   elements using the Html builder. Also handles the raw \mathml{...}
   escape hatch that lets authors write MathML directly. *)

open Html
open Syntax

(* Big operators that should use munder/mover instead of msub/msup. *)
let big_ops : SSet.t = sset_of_list [ "sum"; "prod"; "int"; "lim" ]

(* MathML text escaping: only <, >, &. Matches Blogware.Render.MathML's
   escapeMathText exactly. *)
let escape_math_text (s : string) : string =
  let needs =
    let r = ref false in
    String.iter (fun c -> if c = '<' || c = '>' || c = '&' then r := true) s;
    !r
  in
  if not needs then s
  else begin
    let b = Buffer.create (String.length s + 8) in
    String.iter
      (fun c ->
        match c with
        | '<' -> Buffer.add_string b "&lt;"
        | '>' -> Buffer.add_string b "&gt;"
        | '&' -> Buffer.add_string b "&amp;"
        | c -> Buffer.add_char b c)
      s;
    Buffer.contents b
  end

(* Map bit-index → tag helper. Encoding (from the Haskell source):
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
  | Math_cmd (name, _) -> SSet.mem name big_ops
  | _ -> false

(* --- Main math-node renderer --- *)

let rec render_math_node (n : math_node) : Html.t =
  match n with
  | Math_text t -> mi_ [] (raw (escape_math_text t))
  | Math_num s -> mn_ [] (raw s)
  | Math_op (op, stretchy) ->
      if stretchy then mo_ [] (raw (escape_math_text op))
      else mo_ [ attr "stretchy" "false" ] (raw (escape_math_text op))
  | Math_sym c -> mi_ [] (raw (String.make 1 c))
  | Math_group ns -> mrow_ [] (concat (List.map render_math_node ns))
  | Math_cmd (name, args) -> render_math_cmd name args
  | Math_frac (num, denom) ->
      mfrac_ []
        (mrow_ [] (render_math_node num) ++ mrow_ [] (render_math_node denom))
  | Math_term (nucleus, msub, msup) -> render_math_term nucleus msub msup

and render_math_cmd name args =
  match (name, args) with
  | "frac", [ num; denom ] ->
      mrow_ []
        (mfrac_ []
           (mrow_ [] (render_math_node num) ++ mrow_ [] (render_math_node denom)))
  | "binom", [ n; k ] ->
      mrow_ []
        (mo_ [] (raw "(")
        ++ mfrac_
             [ attr "linethickness" "0" ]
             (mrow_ [] (render_math_node n) ++ mrow_ [] (render_math_node k))
        ++ mo_ [] (raw ")"))
  | "operatorname", [ Math_op (s, stretchy) ] ->
      if stretchy then mo_ [] (raw (escape_math_text s))
      else mo_ [ attr "stretchy" "false" ] (raw (escape_math_text s))
  | "left", [ Math_op (op, stretchy) ] ->
      if stretchy then mo_ [] (raw (escape_math_text op))
      else mo_ [ attr "stretchy" "false" ] (raw (escape_math_text op))
  | "right", [ Math_op (op, stretchy) ] ->
      if stretchy then mo_ [] (raw (escape_math_text op))
      else mo_ [ attr "stretchy" "false" ] (raw (escape_math_text op))
  | _, [] ->
      let repl =
        match SMap.find_opt name replacements with Some r -> r | None -> name
      in
      mo_ [] (raw repl)
  | _, _ -> mo_ [] (raw name) ++ concat (List.map render_math_node args)

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
    | Math_display -> [ attr "display" "block" ]
    | Math_inline -> []
  in
  math_
    (attr "xmlns" "http://www.w3.org/1998/Math/MathML"
    :: class_ "math" :: disp_attr)
    (concat (List.map render_math_node nodes))

(* --- Raw \mathml{...} support ---
   Authors can embed MathML directly using \mathml with a nested tree of
   \mi, \mn, \mo, \msup, etc. We walk that Node tree here. *)

let col_align_attrs (specs : col_spec list) : attribute list =
  if specs = [] then []
  else
    let spec_to_text = function
      | Col_left -> "left"
      | Col_right -> "right"
      | Col_center -> "center"
    in
    [
      attr "columnalign" (String.concat " " (List.map spec_to_text specs) ^ " ");
    ]

let rec render_mathml_node (n : node) : Html.t =
  match n with
  | NText _ -> empty
  | NMath (_, _, mnodes) -> mrow_ [] (concat (List.map render_math_node mnodes))
  | NCmd (_, "mi", _, Arg_symbol (_, s) :: _) ->
      mi_ [] (raw (escape_math_text s))
  | NCmd (_, "mn", _, Arg_nodes (_, ns) :: _) ->
      mn_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, "mo", _, Arg_nodes (_, ns) :: _) ->
      mo_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, "mo*", _, Arg_nodes (_, ns) :: _) ->
      mo_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, "mtext", _, Arg_nodes (_, ns) :: _) ->
      mtext_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, "mrow", _, Arg_nodes (_, ns) :: _) ->
      mrow_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, "msup", _, Arg_nodes (_, base) :: Arg_nodes (_, sup) :: _) ->
      msup_ []
        (concat (List.map render_mathml_node base)
        ++ concat (List.map render_mathml_node sup))
  | NCmd (_, "msub", _, Arg_nodes (_, base) :: Arg_nodes (_, sub) :: _) ->
      msub_ []
        (concat (List.map render_mathml_node base)
        ++ concat (List.map render_mathml_node sub))
  | NCmd
      ( _,
        "msubsup",
        _,
        Arg_nodes (_, base) :: Arg_nodes (_, sub) :: Arg_nodes (_, sup) :: _ )
    ->
      msubsup_ []
        (concat (List.map render_mathml_node base)
        ++ concat (List.map render_mathml_node sub)
        ++ concat (List.map render_mathml_node sup))
  | NCmd
      ( _,
        "munderover",
        _,
        Arg_nodes (_, base) :: Arg_nodes (_, u) :: Arg_nodes (_, o) :: _ ) ->
      munderover_ []
        (concat (List.map render_mathml_node base)
        ++ concat (List.map render_mathml_node u)
        ++ concat (List.map render_mathml_node o))
  | NCmd (_, "mtable", _, Arg_align (_, spec) :: Arg_nodes (_, ns) :: _) ->
      mtable_ (col_align_attrs spec) (concat (List.map render_mathml_node ns))
  | NCmd (_, "mtr", _, Arg_nodes (_, ns) :: _) ->
      mtr_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, "mtd", _, Arg_nodes (_, ns) :: _) ->
      mtd_ [] (concat (List.map render_mathml_node ns))
  | NCmd (_, name, _, _) -> (
      match SMap.find_opt name replacements with
      | Some repl -> raw repl
      | None -> empty)
  | _ -> empty

let render_mathml_cmd (opts : string list) (body : node list) : Html.t =
  let disp_attr =
    if List.mem "block" opts then [ attr "display" "block" ] else []
  in
  math_
    (attr "xmlns" "http://www.w3.org/1998/Math/MathML"
    :: class_ "math" :: disp_attr)
    (concat (List.map render_mathml_node body))
