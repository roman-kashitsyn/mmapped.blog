(* Document → HTML renderer. Mirror of Blogware.Render. *)

open Html
open Document
open Syntax

(* --- Helpers --- *)

let join_classes cs = String.concat " " cs
let trim_inlines (ils : inline list) : inline list =
  let is_ws = function
    | Str t -> String.trim t = ""
    | _ -> false
  in
  let rec drop_left = function
    | [] -> []
    | x :: xs when is_ws x -> drop_left xs
    | xs -> xs
  in
  let drop_right xs = List.rev (drop_left (List.rev xs)) in
  drop_right (drop_left ils)

let split_inline_paragraphs (ils : inline list) : inline list list =
let flush cur acc =
    let trimmed = trim_inlines (List.rev cur) in
    if trimmed = [] then acc else trimmed :: acc
  in
  let rec handle_str s cur acc =
    let len = String.length s in
    let rec find idx =
      if idx + 1 >= len then None
      else if s.[idx] = '\n' && s.[idx + 1] = '\n' then Some idx
      else find (idx + 1)
    in
    match find 0 with
    | None ->
      if s = "" then (cur, acc)
      else (Str s :: cur, acc)
    | Some idx ->
      let before = String.sub s 0 idx in
      let cur = if before = "" then cur else Str before :: cur in
      let acc = flush cur acc in
      let start = idx + 2 in
      let rest =
        if start >= len then ""
        else String.sub s start (len - start)
      in
      handle_str rest [] acc
  in
  let rec go cur acc = function
    | [] -> List.rev (flush cur acc)
    | Str s :: rest ->
      let cur, acc = handle_str s cur acc in
      go cur acc rest
    | x :: rest ->
      go (x :: cur) acc rest
  in
  go [] [] ils

let plainify_paras blocks =
  List.map (function Para ils -> Plain ils | b -> b) blocks

(* Convert 1-based integer to circled-number glyph (①②③...). *)
let round_num_glyph (n : int) : string =
  (* 0x245F + n, encoded as a 3-byte UTF-8 sequence. *)
  let cp = 0x245F + n in
  let b1 = 0xE0 lor (cp lsr 12) in
  let b2 = 0x80 lor ((cp lsr 6) land 0x3F) in
  let b3 = 0x80 lor (cp land 0x3F) in
  let s = Bytes.create 3 in
  Bytes.unsafe_set s 0 (Char.chr b1);
  Bytes.unsafe_set s 1 (Char.chr b2);
  Bytes.unsafe_set s 2 (Char.chr b3);
  Bytes.unsafe_to_string s

let alignment_to_class = function
  | Col_left -> "align-l"
  | Col_right -> "align-r"
  | Col_center -> "align-c"

let border_class top bot =
  match top, bot with
  | true, true -> "border-top border-bot"
  | true, false -> "border-top"
  | false, true -> "border-bot"
  | false, false -> ""

(* --- Rendering context --- *)

type ctx = { ref_table : Document.ref_table }

let empty_ctx = { ref_table = RefTable.empty }

(* --- Inline rendering --- *)

let rec render_inline (ctx : ctx) (il : inline) : Html.t =
  match il with
  | Str t -> text t  (* typography already applied; text escapes &<> *)
  | Strong ils -> b_ [] (render_inlines ctx ils)
  | Emph ils -> em_ [] (render_inlines ctx ils)
  | Underline ils -> u_ [] (render_inlines ctx ils)
  | Small_caps ils -> span_ [class_ "smallcaps"] (render_inlines ctx ils)
  | Strikethrough ils -> span_ [class_ "strikethrough"] (render_inlines ctx ils)
  | Code (classes, ils) ->
    code_ [class_ (join_classes classes)] (render_inlines ctx ils)
  | Link (url, ils) -> a_ [href_ url] (render_inlines ctx ils)
  | Math (disp, nodes) -> Render_mathml.render_math disp nodes
  | Margin_note (anchor, ils) ->
    label_ [class_ "margin-toggle"; for_ anchor] (raw "\xE2\x8A\x95")  (* ⊕ *)
    ++ leaf "input"
         [type_ "checkbox"; id_ anchor; class_ "margin-toggle"]
    ++ span_ [class_ "marginnote"] (render_inlines ctx ils)
  | Side_note (anchor, ils) ->
    label_ [class_ "margin-toggle sidenote-number"; for_ anchor] empty
    ++ leaf "input"
         [type_ "checkbox"; id_ anchor; class_ "margin-toggle"]
    ++ span_ [class_ "sidenote"] (render_inlines ctx ils)
  | Kbd ils -> kbd_ [] (render_inlines ctx ils)
  | Sub ils -> sub_ [] (render_inlines ctx ils)
  | Sup ils -> sup_ [] (render_inlines ctx ils)
  | Quotation ils -> parent "q" [] (render_inlines ctx ils)
  | Fun ils -> span_ [class_ "fun"] (render_inlines ctx ils)
  | Math_span ils -> span_ [class_ "math"] (render_inlines ctx ils)
  | Normal ils -> span_ [class_ "normal"] (render_inlines ctx ils)
  | Anchor aid -> span_ [id_ aid] empty
  | Horizontal_rule -> hr_ []
  | Circled_ref n -> span_ [class_ "circled-ref"] (round_num_glyph n |> text)
  | Line_break -> br_ []
  | Numeric_space -> raw "&numsp;"
  | Mathml (opts, body) -> Render_mathml.render_mathml_cmd opts body
  | Image_inline (classes, path) ->
    let cls = join_classes classes in
    let img = leaf "img" [class_ cls; src_ path] in
    let is_svg =
      let lp = String.length path in
      lp >= 4
      && (let ext = String.lowercase_ascii (String.sub path (lp - 4) 4) in
          ext = ".svg")
    in
    if is_svg then p_ [class_ "svg"] img
    else img
  | Nameref label ->
    match RefTable.find_opt label ctx.ref_table with
    | Some r -> a_ [href_ r.ref_url] (text r.ref_title)
    | None -> text ("[unresolved:" ^ label ^ "]")

and render_inlines (ctx : ctx) (ils : inline list) : Html.t =
  concat (List.map (render_inline ctx) ils)

(* --- Code-block line wrapping ---
   Render the inline list once, then split the HTML string on '\n'.
   Each resulting chunk (which may have unbalanced tags) is wrapped in
   <span class="line">...</span>\n. *)

let render_code_content (ctx : ctx) (ils : inline list) : Html.t =
  let rendered = Html.render (render_inlines ctx ils) in
  let lines = String.split_on_char '\n' rendered in
  let kept = match List.rev lines with
    | [] -> []
    | "" :: rest -> List.rev rest
    | _ -> lines
  in
  concat (List.map (fun line ->
    span_ [class_ "line"] (raw line) ++ raw "\n"
  ) kept)

(* --- Table rendering --- *)

let render_table_cell ctx cell_tag (c : table_cell) : Html.t =
  parent cell_tag
    [ colspan_ (string_of_int c.tc_colspan)
    ; class_ (alignment_to_class c.tc_align)
    ]
    (render_inlines ctx c.tc_content)

let render_table_row ctx cell_tag (r : table_row) : Html.t =
  let cls = border_class r.tr_border_top r.tr_border_bottom in
  tr_ [class_ cls] (concat (List.map (render_table_cell ctx cell_tag) r.tr_cells))

let render_table (ctx : ctx) (td : table_def) : Html.t =
  let num_cols = List.length td.table_spec in
  let cls =
    "table-" ^ string_of_int num_cols
    ^ " " ^ join_classes td.table_opts
  in
  let header_html = match td.table_header with
    | Some h -> raw "<thead>" ++ thead_ [] (render_table_row ctx "th" h)
    | None -> empty
  in
  table_ [class_ cls]
    (header_html
     ++ tbody_ []
          (concat (List.map (render_table_row ctx "td") td.table_rows)))

(* --- Block rendering --- *)

let rec render_block ?(wrap_images = true) (ctx : ctx) (b : block) : Html.t =
  match b with
  | Para ils ->
    let attrs = match ils with
      | Quotation _ :: _ -> [class_ "hanging-quote"]
      | _ -> []
    in
    p_ attrs (render_inlines ctx ils) ++ nl
  | Plain ils -> render_inlines ctx ils

  | Section (header, body) ->
    let header_html = match header with
      | Some (anchor, title) ->
        let attrs = if anchor = "" then [] else [id_ anchor] in
        let link =
          if anchor = "" then render_inlines ctx title
          else a_ [href_ ("#" ^ anchor)] (render_inlines ctx title)
        in
        parent "h2" attrs link ++ nl
      | None -> empty
    in
    section_ [] (header_html ++ render_blocks ctx body) ++ nl

  | Subsection (anchor, title, body) ->
    let attrs = if anchor = "" then [] else [id_ anchor] in
    let link =
      if anchor = "" then render_inlines ctx title
      else a_ [href_ ("#" ^ anchor)] (render_inlines ctx title)
    in
    parent "h3" attrs link ++ nl ++ render_blocks ctx body

  | Code_block (classes, content) ->
    let cls = join_classes classes in
    let pre_cls =
      if cls = "" then "source" else "source " ^ cls
    in
    div_ [class_ "source-container"]
      (pre_ [class_ pre_cls]
         (code_ [] (render_code_content ctx content)))
    ++ nl

  | Verbatim_block (classes, content) ->
    let cls = join_classes classes in
    let pre_cls =
      if cls = "" then "source" else "source " ^ cls
    in
    div_ [class_ "source-container"]
      (pre_ [class_ pre_cls]
         (code_ [] (text content)))
    ++ nl

  | Bullet_list (style, items) ->
    let cls = match style with Arrows -> "arrows" | Checklist -> "checklist" in
    ul_ [class_ cls]
      (concat (List.map (fun blocks -> li_ [] (render_blocks ctx blocks)) items))
    ++ nl

  | Ordered_list items ->
    let numbered = List.mapi (fun i b -> (i + 1, b)) items in
    ol_ [class_ "circled"]
      (concat (List.map (fun (n, bs) ->
         li_ [attr "data-num-glyph" (round_num_glyph n)] (render_blocks ctx bs)
       ) numbered))
    ++ nl

  | Description_list items ->
    dl_ [class_ ""]
      (concat (List.map (fun (term, def_) ->
         dt_ [class_ ""] (render_inlines ctx term) ++ dd_ [class_ ""] (render_blocks ctx def_)
       ) items))
    ++ nl

  | Blockquote (body, attribution) ->
    let paras = split_inline_paragraphs body in
    let body_html =
      match paras with
      | [] -> p_ [] (render_inlines ctx body)
      | ps ->
        concat
          (List.map (fun ils -> p_ [] (render_inlines ctx ils)) ps)
    in
    blockquote_ [] (body_html ++ footer_ [] (render_inlines ctx attribution))
    ++ nl

  | Table td -> render_table ctx td ++ nl

  | Image (classes, path) ->
    let cls = join_classes classes in
    let img = leaf "img" [class_ cls; src_ path] in
    let is_svg =
      let lp = String.length path in
      lp >= 4
      && (let ext = String.lowercase_ascii (String.sub path (lp - 4) 4) in
          ext = ".svg")
    in
    if is_svg then p_ [class_ "svg"] img ++ nl
    else if wrap_images then p_ [] img ++ nl
    else img ++ nl

  | Figure (classes, body) ->
    figure_ [class_ (join_classes classes)]
      (render_blocks ~wrap_images:false ctx body)
    ++ nl

  | Epigraph (body, attribution) ->
    div_ [class_ "epigraph"]
      (blockquote_ []
         (p_ [] (render_inlines ctx body)
          ++ footer_ [] (render_inlines ctx attribution)))
    ++ nl

  | Abstract body ->
    div_ [class_ "abstract"] (render_blocks ctx body) ++ nl

  | Advice (anchor, ils) ->
    div_ [class_ "advice"; id_ anchor]
      (p_ [] (a_ [class_ "anchor"; href_ ("#" ^ anchor)] (raw "\xE2\x98\x9B") ++ render_inlines ctx ils))
    ++ nl

  | Details (summary, body) ->
    parent "details" [class_ ""]
      (parent "summary" [] (render_inlines ctx summary)
       ++ render_blocks ctx (plainify_paras body))
    ++ nl

  | Center body ->
    parent "center" [] (render_blocks ~wrap_images:false ctx body) ++ nl

  | HRule -> hr_ [] ++ nl

and render_blocks ?(wrap_images = true) (ctx : ctx) (bs : block list) : Html.t =
  concat (List.map (render_block ~wrap_images ctx) bs)
