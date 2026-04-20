(* Document → HTML renderer. Mirror of Blogware.Render. *)

open Html
open Document
open Syntax

(* --- Helpers --- *)

let txt = Text.of_string
let join_classes cs = Text.concat (Text.of_char ' ') cs

let class_attr_if_nonempty cls =
  if Text.is_empty cls then [] else [ class_ cls ]

let plainify_paras blocks =
  List.map (function Para ils -> Plain ils | b -> b) blocks

let trim_quote_html (s : string) : Text.t =
  let len = String.length s in
  let rec left i =
    if i >= len then len
    else
      match s.[i] with
      | ' ' | '\t' | '\x0C' | '\n' | '\r' -> left (i + 1)
      | _ -> i
  in
  let rec right i =
    if i < 0 then -1
    else
      match s.[i] with
      | ' ' | '\t' | '\x0C' | '\n' | '\r' -> right (i - 1)
      | _ -> i
  in
  let i = left 0 in
  let j = right (len - 1) in
  if j < i then Text.empty else Text.of_substr s i (j - i + 1)

(* Convert 1-based integer to circled-number glyph (①②③...). *)
let round_num_glyph (n : int) : Text.t =
  let buf = Buffer.create 3 in
  Buffer.add_utf_8_uchar buf (Uchar.of_int (0x245F + n));
  Text.of_string (Buffer.contents buf)

let alignment_to_class = function
  | Col_left -> txt "align-l"
  | Col_right -> txt "align-r"
  | Col_center -> txt "align-c"

let border_class top bot =
  match (top, bot) with
  | true, true -> txt "border-top border-bot"
  | true, false -> txt "border-top"
  | false, true -> txt "border-bot"
  | false, false -> Text.empty

(* --- Rendering context --- *)

type ctx = { ref_table : Document.ref_table }

let empty_ctx = { ref_table = RefTable.empty }

(* --- Inline rendering --- *)

let rec render_inline (ctx : ctx) (il : inline) : Html.t =
  match il with
  | Str t -> text t (* typography already applied; text escapes &<> *)
  | Strong ils -> b_ [] (render_inlines ctx ils)
  | Emph ils -> em_ [] (render_inlines ctx ils)
  | Underline ils -> u_ [] (render_inlines ctx ils)
  | Small_caps ils ->
      span_ [ class_ (txt "smallcaps") ] (render_inlines ctx ils)
  | Strikethrough ils ->
      span_ [ class_ (txt "strikethrough") ] (render_inlines ctx ils)
  | Code (classes, ils) ->
      code_
        (class_attr_if_nonempty (join_classes classes))
        (render_inlines ctx ils)
  | Link (url, ils) -> a_ [ href_ url ] (render_inlines ctx ils)
  | Math (disp, nodes) -> Render_mathml.render_math disp nodes
  | Margin_note (anchor, ils) ->
      label_
        [ class_ (txt "margin-toggle"); for_ anchor ]
        (raw (txt "\xE2\x8A\x95"))
      (* ⊕ *)
      ++ leaf "input"
           [ type_ (txt "checkbox"); id_ anchor; class_ (txt "margin-toggle") ]
      ++ span_ [ class_ (txt "marginnote") ] (render_inlines ctx ils)
  | Side_note (anchor, ils) ->
      label_ [ class_ (txt "margin-toggle sidenote-number"); for_ anchor ] empty
      ++ leaf "input"
           [ type_ (txt "checkbox"); id_ anchor; class_ (txt "margin-toggle") ]
      ++ span_ [ class_ (txt "sidenote") ] (render_inlines ctx ils)
  | Kbd ils -> kbd_ [] (render_inlines ctx ils)
  | Sub ils -> sub_ [] (render_inlines ctx ils)
  | Sup ils -> sup_ [] (render_inlines ctx ils)
  | Quotation ils -> parent "q" [] (render_inlines ctx ils)
  | Fun ils -> span_ [ class_ (txt "fun") ] (render_inlines ctx ils)
  | Math_span ils -> span_ [ class_ (txt "math") ] (render_inlines ctx ils)
  | Normal ils -> span_ [ class_ (txt "normal") ] (render_inlines ctx ils)
  | Anchor aid -> span_ [ id_ aid ] empty
  | Horizontal_rule -> hr_ []
  | Circled_ref n ->
      span_ [ class_ (txt "circled-ref") ] (round_num_glyph n |> text)
  | Line_break -> br_ []
  | Numeric_space -> raw (txt "&numsp;")
  | Image_inline (classes, path) ->
      let cls = join_classes classes in
      let img = leaf "img" (class_attr_if_nonempty cls @ [ src_ path ]) in
      if String.equal (Filename.extension (Text.to_string path)) ".svg" then
        p_ [ class_ (txt "svg") ] img
      else img
  | Nameref label -> (
      match RefTable.find_opt label ctx.ref_table with
      | Some r -> a_ [ href_ r.ref_url ] (text r.ref_title)
      | None ->
          text (Text.concat Text.empty [ txt "[unresolved:"; label; txt "]" ]))

and render_inlines (ctx : ctx) (ils : inline list) : Html.t =
  concat (List.map (render_inline ctx) ils)

(* --- Code-block line wrapping ---
   Render the inline list once, then split the HTML string on '\n'.
   Each resulting chunk (which may have unbalanced tags) is wrapped in
   <span class="line">...</span>\n. *)

let render_code_content (ctx : ctx) (ils : inline list) : Html.t =
  let rendered = Html.render (render_inlines ctx ils) in
  let lines = String.split_on_char '\n' rendered in
  let kept =
    match List.rev lines with
    | [] -> []
    | "" :: rest -> List.rev rest
    | _ -> lines
  in
  concat
    (List.map
       (fun line ->
         span_ [ class_ (txt "line") ] (raw (txt line)) ++ raw (txt "\n"))
       kept)

(* --- Table rendering --- *)

let render_table_cell ctx cell_tag (c : table_cell) : Html.t =
  parent cell_tag
    [
      colspan_ (txt (string_of_int c.tc_colspan));
      class_ (alignment_to_class c.tc_align);
    ]
    (render_inlines ctx c.tc_content)

let render_table_row ctx cell_tag (r : table_row) : Html.t =
  let cls = border_class r.tr_border_top r.tr_border_bottom in
  tr_
    (class_attr_if_nonempty cls)
    (concat (List.map (render_table_cell ctx cell_tag) r.tr_cells))

let render_table (ctx : ctx) (td : table_def) : Html.t =
  let num_cols = List.length td.table_spec in
  let cls =
    Text.concat Text.empty
      [
        txt "table-";
        txt (string_of_int num_cols);
        txt " ";
        join_classes td.table_opts;
      ]
  in
  let header_html =
    match td.table_header with
    | Some h -> raw (txt "<thead>") ++ thead_ [] (render_table_row ctx "th" h)
    | None -> empty
  in
  table_
    (class_attr_if_nonempty cls)
    (header_html
    ++ tbody_ [] (concat (List.map (render_table_row ctx "td") td.table_rows)))

(* --- Block rendering --- *)

let rec render_quote_block (ctx : ctx) (b : block) : Html.t =
  match b with
  | Para ils ->
      let attrs =
        match ils with
        | Quotation _ :: _ -> [ class_ (txt "hanging-quote") ]
        | _ -> []
      in
      let content = Html.render (render_inlines ctx ils) |> trim_quote_html in
      p_ attrs (raw content)
  | Plain ils -> render_inlines ctx ils
  | b -> render_block ctx b

and render_quote_blocks (ctx : ctx) (bs : block list) : Html.t =
  concat (List.map (render_quote_block ctx) bs)

and render_block ?(wrap_images = true) (ctx : ctx) (b : block) : Html.t =
  match b with
  | Para ils ->
      let attrs =
        match ils with
        | Quotation _ :: _ -> [ class_ (txt "hanging-quote") ]
        | _ -> []
      in
      p_ attrs (render_inlines ctx ils) ++ nl
  | Plain ils -> render_inlines ctx ils
  | Section (header, body) ->
      let header_html =
        match header with
        | Some (anchor, title) ->
            let attrs = if Text.is_empty anchor then [] else [ id_ anchor ] in
            let link =
              if Text.is_empty anchor then render_inlines ctx title
              else
                a_
                  [ href_ (Text.append (txt "#") anchor) ]
                  (render_inlines ctx title)
            in
            parent "h2" attrs link ++ nl
        | None -> empty
      in
      section_ [] (header_html ++ render_blocks ctx body) ++ nl
  | Subsection (anchor, title, body) ->
      let attrs = if Text.is_empty anchor then [] else [ id_ anchor ] in
      let link =
        if Text.is_empty anchor then render_inlines ctx title
        else
          a_ [ href_ (Text.append (txt "#") anchor) ] (render_inlines ctx title)
      in
      parent "h3" attrs link ++ nl ++ render_blocks ctx body
  | Code_block (classes, content) ->
      let cls = join_classes classes in
      let pre_cls =
        if Text.is_empty cls then txt "source"
        else Text.concat Text.empty [ txt "source "; cls ]
      in
      div_
        [ class_ (txt "source-container") ]
        (pre_ [ class_ pre_cls ] (code_ [] (render_code_content ctx content)))
      ++ nl
  | Verbatim_block (classes, content) ->
      let cls = join_classes classes in
      let pre_cls =
        if Text.is_empty cls then txt "source"
        else Text.concat Text.empty [ txt "source "; cls ]
      in
      div_
        [ class_ (txt "source-container") ]
        (pre_ [ class_ pre_cls ] (code_ [] (text content)))
      ++ nl
  | Bullet_list (style, items) ->
      let cls =
        match style with Arrows -> txt "arrows" | Checklist -> txt "checklist"
      in
      ul_
        [ class_ cls ]
        (concat
           (List.map (fun blocks -> li_ [] (render_blocks ctx blocks)) items))
      ++ nl
  | Ordered_list items ->
      let numbered = List.mapi (fun i b -> (i + 1, b)) items in
      ol_
        [ class_ (txt "circled") ]
        (concat
           (List.map
              (fun (n, bs) ->
                li_
                  [ attr "data-num-glyph" (round_num_glyph n) ]
                  (render_blocks ctx bs))
              numbered))
      ++ nl
  | Description_list items ->
      dl_ []
        (concat
           (List.map
              (fun (term, def_) ->
                dt_ [] (render_inlines ctx term)
                ++ dd_ [] (render_blocks ctx def_))
              items))
      ++ nl
  | Blockquote (body, attribution) ->
      blockquote_ []
        (render_quote_blocks ctx body
        ++ footer_ [] (render_inlines ctx attribution))
      ++ nl
  | Table td -> render_table ctx td ++ nl
  | Image (classes, path) ->
      let cls = join_classes classes in
      let img = leaf "img" (class_attr_if_nonempty cls @ [ src_ path ]) in
      let is_svg =
        String.equal (Filename.extension (Text.to_string path)) ".svg"
      in
      if is_svg then p_ [ class_ (txt "svg") ] img ++ nl
      else if wrap_images then p_ [] img ++ nl
      else img ++ nl
  | Figure (classes, body) ->
      figure_
        (class_attr_if_nonempty (join_classes classes))
        (render_blocks ~wrap_images:false ctx body)
      ++ nl
  | Epigraph (body, attribution) ->
      div_
        [ class_ (txt "epigraph") ]
        (blockquote_ []
           (render_quote_blocks ctx body
           ++ footer_ [] (render_inlines ctx attribution)))
      ++ nl
  | Abstract body ->
      div_ [ class_ (txt "abstract") ] (render_blocks ctx body) ++ nl
  | Advice (anchor, ils) ->
      div_
        [ class_ (txt "advice"); id_ anchor ]
        (p_ []
           (a_
              [
                class_ (txt "anchor left-gutter-anchor advice-anchor");
                href_ (Text.append (txt "#") anchor);
                attr "aria-label" (txt "Link to this advice");
              ]
              empty
           ++ render_inlines ctx ils))
      ++ nl
  | Details (summary, body) ->
      parent "details" []
        (parent "summary" [] (render_inlines ctx summary)
        ++ render_blocks ctx (plainify_paras body))
      ++ nl
  | Center body ->
      parent "center" [] (render_blocks ~wrap_images:false ctx body) ++ nl
  | HRule -> hr_ [] ++ nl

and render_blocks ?(wrap_images = true) (ctx : ctx) (bs : block list) : Html.t =
  concat (List.map (render_block ~wrap_images ctx) bs)
