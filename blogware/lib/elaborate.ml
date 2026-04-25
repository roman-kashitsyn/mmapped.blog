(* Elaborator. Mirror of Blogware.Elaborate.

   Transforms a flat [Syntax.node list] (the parser's output) into a
   high-level [Document.article], dispatching on command name. This is the
   largest module in the port. The logic is a faithful translation of the
   Haskell original, with Haskell's [Data.Sequence] replaced by [list]
   everywhere. *)

open Syntax
open Document

(* --- Error plumbing --- *)

type 'a result_ = ('a, Error.elab_error) result

let elab_error (pos : Parser.Pos.t) (msg : string) : 'a result_ =
  Error { Error.ee_pos = Some pos; ee_message = msg }

(* Bind for the elaboration result monad. *)
let ( let* ) (r : 'a result_) (f : 'a -> 'b result_) : 'b result_ =
  match r with Ok x -> f x | Error _ as e -> e

let return x = Ok x

let map_m (f : 'a -> 'b result_) (xs : 'a list) : 'b list result_ =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | x :: xs ->
        let* y = f x in
        go (y :: acc) xs
  in
  go [] xs

(* Text shortcuts *)

let text = Text.of_string
let ( ^^ ) = Text.append

let concat_text_map (f : 'a -> Text.t) (xs : 'a list) : Text.t =
  let rec go acc = function
    | [] -> Text.concat Text.empty (List.rev acc)
    | x :: xs -> go (f x :: acc) xs
  in
  go [] xs

(* --- Typography --- *)

let typographic_replacements : (string * string) list =
  [
    ("---", "\xE2\x80\x94" (* em dash — *));
    ("--", "\xE2\x80\x93" (* en dash – *));
    ("``", "\xE2\x80\x9C" (* left double quote *));
    ("''", "\xE2\x80\x9D" (* right double quote *));
    ("'", "\xE2\x80\x99" (* right single quote *));
  ]

let is_typography_special c =
  match c with '-' | '`' | '\'' -> true | _ -> false

let is_whitespace c =
  match c with ' ' | '\x0C' | '\t' | '\n' | '\r' -> true | _ -> false

let try_replacement_at s i =
  let rec go = function
    | [] -> None
    | (pref, rep) :: rest ->
        if Strings.has_prefix_at s i pref then Some (rep, String.length pref)
        else go rest
  in
  go typographic_replacements

let apply_typography (input : Text.t) : Text.t =
  if not (Text.exists is_typography_special input) then input
  else begin
    (* Using raw strings here is significantly faster than juggling Text.t. *)
    let input, pos, len = Text.to_substr input in
    let b = Buffer.create (len + 20) in
    let i = ref 0 in
    while !i < len do
      let idx = !i + pos in
      let c = input.[idx] in
      if not (is_typography_special c) then begin
        Buffer.add_char b c;
        incr i
      end
      else
        begin match try_replacement_at input idx with
        | Some (rep, used) ->
            Buffer.add_string b rep;
            i := !i + used
        | None ->
            Buffer.add_char b c;
            incr i
        end
    done;
    text (Buffer.contents b)
  end

(* --- Dingbats --- *)

let dingbat_char name =
  if Text.equal_string name "heavy-ballot-x" then text "\xE2\x9C\x97"
  else if Text.equal_string name "heavy-check" then text "\xE2\x9C\x94"
  else if Text.equal_string name "lower-right-pencil" then text "\xE2\x9C\x8E"
  else text "[dingbat:" ^^ name ^^ text "]"

(* --- Metadata extraction --- *)

type meta = {
  m_title : Text.t;
  m_subtitle : Text.t;
  m_featured : bool;
  m_created_at : Date.t;
  m_modified_at : Date.t;
  m_keywords : Text.t list;
  m_reddit : Text.t option;
  m_hn : Text.t option;
  m_lobsters : Text.t option;
}

let default_meta : meta =
  let epoch = Date.make ~year:1970 ~month:1 ~day:1 in
  {
    m_title = Text.empty;
    m_subtitle = Text.empty;
    m_featured = false;
    m_created_at = epoch;
    m_modified_at = epoch;
    m_keywords = [];
    m_reddit = None;
    m_hn = None;
    m_lobsters = None;
  }

let parse_day pos t : Date.t result_ =
  let s = Text.to_string t in
  match Date.of_string s with
  | Some d -> Ok d
  | None -> elab_error pos ("invalid date: " ^ s ^ " (expected YYYY-MM-DD)")

(* Flatten text-like nodes back to a string for simple arg contexts. *)
let rec node_text_of_nodes ns = concat_text_map node_text ns

and node_text = function
  | NText (_, t) -> t
  | NCmd (_, sym, _, args) ->
      let rec go acc = function
        | [] -> Text.concat Text.empty (List.rev acc)
        | Arg_nodes (_, ns) :: rest ->
            go (text "}" :: node_text_of_nodes ns :: text "{" :: acc) rest
        | _ :: rest -> go acc rest
      in
      go [ text ("\\" ^ sym_to_string sym) ] args
  | _ -> Text.empty

(* Fold over top-level nodes collecting metadata. *)
let extract_metadata (nodes : node list) : meta result_ =
  let rec go m = function
    | [] -> Ok m
    | NCmd (_, sym, _, args) :: rest -> (
        match (sym, args) with
        | S_title, Arg_nodes (_, ns) :: _ ->
            go { m with m_title = node_text_of_nodes ns } rest
        | S_subtitle, Arg_nodes (_, ns) :: _ ->
            go { m with m_subtitle = node_text_of_nodes ns } rest
        | S_featured, _ -> go { m with m_featured = true } rest
        | S_date, Arg_symbol (pos, d) :: _ ->
            let* day = parse_day pos d in
            go { m with m_created_at = day; m_modified_at = day } rest
        | S_modified, Arg_symbol (pos, d) :: _ ->
            let* day = parse_day pos d in
            go { m with m_modified_at = day } rest
        | S_keyword, Arg_symbol (_, k) :: _ ->
            go { m with m_keywords = k :: m.m_keywords } rest
        | S_reddit, Arg_url (_, u) :: _ -> go { m with m_reddit = Some u } rest
        | S_hackernews, Arg_url (_, u) :: _ -> go { m with m_hn = Some u } rest
        | S_lobsters, Arg_url (_, u) :: _ ->
            go { m with m_lobsters = Some u } rest
        | _ -> go m rest)
    | _ :: rest -> go m rest
  in
  go default_meta nodes

(* Find the body of \begin{document} ... \end{document}. *)
let rec find_doc_body = function
  | [] -> []
  | NEnv (_, _, S_document, _, body) :: _ -> body
  | _ :: rest -> find_doc_body rest

(* --- Block building --- *)

type flat_block =
  | FB of block
  | SectionMark of Text.t * inline list
  | AnonSectionMark
  | SubsectionMark of Parser.Pos.t * Text.t * inline list

type node_class =
  | CBlock of block
  | CSection of flat_block
  | CInline of inline
  | CSkip

let rec inline_to_text = function
  | Str t -> t
  | Strong ils
  | Emph ils
  | Underline ils
  | Small_caps ils
  | Strikethrough ils
  | Kbd ils
  | Sub ils
  | Sup ils
  | Quotation ils
  | Cite ils
  | Fun ils
  | Math_span ils
  | Normal ils
  | Code (_, ils)
  | Link (_, ils)
  | Margin_note (_, ils)
  | Side_note (_, ils) ->
      inlines_to_text ils
  | Math _ | Anchor _ | Horizontal_rule | Circled_ref _ | Line_break
  | Numeric_space | Nameref _ | Image_inline _ ->
      Text.empty

and inlines_to_text (ils : inline list) : Text.t =
  concat_text_map inline_to_text ils

let text_has_double_newline (t : Text.t) : bool =
  let s, pos, len = Text.to_substr t in
  if len < 2 then false
  else
    let i = ref pos in
    let stop = pos + len - 1 in
    let found = ref false in
    while (not !found) && !i < stop do
      if String.unsafe_get s !i = '\n' && String.unsafe_get s (!i + 1) = '\n'
      then found := true
      else incr i
    done;
    !found

let trim_inlines (ils : inline list) : inline list =
  let is_ws = function Str t -> Text.for_all is_whitespace t | _ -> false in
  let rec drop_left = function
    | [] -> []
    | x :: xs when is_ws x -> drop_left xs
    | xs -> xs
  in
  let drop_right xs = List.rev (drop_left (List.rev xs)) in
  drop_right (drop_left ils)

let is_side_content = function
  | Margin_note _ | Side_note _ | Anchor _ -> true
  | _ -> false

let paragraph_block trimmed =
  if List.for_all is_side_content trimmed then Plain trimmed else Para trimmed

let flush_paragraph_rev inlines_rev blocks_rev =
  match trim_inlines (List.rev inlines_rev) with
  | [] -> blocks_rev
  | trimmed -> paragraph_block trimmed :: blocks_rev

let add_text_to_paragraphs t inlines_rev blocks_rev =
  if not (text_has_double_newline t) then (Str t :: inlines_rev, blocks_rev)
  else
    let s, pos, len = Text.to_substr t in
    let stop = pos + len in
    let rec loop start i inlines_rev blocks_rev =
      if i + 1 >= stop then
        (Str (Text.of_substr s start (stop - start)) :: inlines_rev, blocks_rev)
      else if String.unsafe_get s i = '\n' && String.unsafe_get s (i + 1) = '\n'
      then
        let inlines_rev =
          Str (Text.of_substr s start (i - start)) :: inlines_rev
        in
        let blocks_rev = flush_paragraph_rev inlines_rev blocks_rev in
        loop (i + 2) (i + 2) [] blocks_rev
      else loop start (i + 1) inlines_rev blocks_rev
    in
    loop pos pos inlines_rev blocks_rev

let split_paragraphs (ils : inline list) : block list =
  let rec go inlines_rev blocks_rev = function
    | [] -> List.rev (flush_paragraph_rev inlines_rev blocks_rev)
    | Str t :: rest ->
        let inlines_rev, blocks_rev =
          add_text_to_paragraphs t inlines_rev blocks_rev
        in
        go inlines_rev blocks_rev rest
    | il :: rest -> go (il :: inlines_rev) blocks_rev rest
  in
  go [] [] ils

(* --- Classification --- *)

let rec classify_node (n : node) : node_class result_ =
  match n with
  | NText (_, t) -> Ok (CInline (Str (apply_typography t)))
  | NGroup (_, ns) -> (
      let* ils = elaborate_inlines ns in
      match ils with
      | [ il ] -> Ok (CInline il)
      | _ -> Ok (CInline (Str (inlines_to_text ils))))
  | NQuotation (_, ns) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Quotation ils))
  | NMath (_, disp, mnodes) -> Ok (CInline (Math (disp, mnodes)))
  | NCmd (pos, sym, opts, args) -> classify_cmd pos sym opts args
  | NEnv (pos, _, sym, opts, body) -> classify_env pos sym opts body
  | NTable (_, _, _sym, opts, spec, rows) ->
      let name = sym_to_string _sym in
      let* td = elaborate_table name opts spec rows in
      Ok (CBlock (Table td))

and classify_cmd pos sym opts args =
  match (sym, args) with
  | S_section, Arg_symbol (_, anchor) :: Arg_nodes (_, title) :: _ ->
      let* ils = elaborate_inlines title in
      Ok (CSection (SectionMark (anchor, ils)))
  | S_section_star, _ -> Ok (CSection AnonSectionMark)
  | S_subsection, Arg_symbol (_, anchor) :: Arg_nodes (_, title) :: _ ->
      let* ils = elaborate_inlines title in
      Ok (CSection (SubsectionMark (pos, anchor, ils)))
  | S_b, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Strong ils))
  | S_emph, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Emph ils))
  | S_u, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Underline ils))
  | S_textsc, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Small_caps ils))
  | S_strikethrough, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Strikethrough ils))
  | S_code, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_code_inlines ns in
      Ok (CInline (Code (opts, ils)))
  | S_kbd, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Kbd ils))
  | S_sub, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Sub ils))
  | S_sup, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Sup ils))
  | S_fun, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Fun ils))
  | S_math, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Math_span ils))
  | S_normal, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Normal ils))
  | S_center, Arg_nodes (_, ns) :: _ ->
      let* blocks = build_blocks ns in
      Ok (CBlock (Center blocks))
  | S_href, Arg_url (_, url) :: Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Link (url, ils)))
  | S_nameref, Arg_symbol (_, r) :: _ -> Ok (CInline (Nameref r))
  | S_label, Arg_symbol (_, anchor) :: _ -> Ok (CInline (Anchor anchor))
  | S_newline, _ -> Ok (CInline Line_break)
  | S_numspace, _ -> Ok (CInline Numeric_space)
  | S_hrule, _ -> Ok (CBlock HRule)
  | S_qed, _ -> Ok (CInline (Str (text "\xE2\x88\x8E")))
  | S_marginnote, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Margin_note (anchor, ils)))
  | S_sidenote, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Side_note (anchor, ils)))
  | S_advice, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CBlock (Advice (anchor, ils)))
  | S_epigraph, Arg_nodes (_, body) :: Arg_nodes (_, attrib) :: _ ->
      let* b_blocks = build_blocks body in
      let* a_ils = elaborate_inlines attrib in
      Ok (CBlock (Epigraph (b_blocks, a_ils)))
  | S_blockquote, Arg_nodes (_, body) :: Arg_nodes (_, attrib) :: _ ->
      let* b_blocks = build_blocks body in
      let* a_ils = elaborate_inlines attrib in
      Ok (CBlock (Blockquote (b_blocks, a_ils)))
  | S_cite, Arg_nodes (_, body) :: _ ->
      let* ils = elaborate_inlines body in
      Ok (CInline (Cite ils))
  | S_figcaption, Arg_nodes (_, ns) :: _ ->
      let* ils = elaborate_inlines ns in
      Ok (CBlock (Figcaption ils))
  | S_details, Arg_nodes (_, summary) :: Arg_nodes (_, body) :: _ ->
      let* s_ils = elaborate_inlines summary in
      let* body_blocks = build_blocks body in
      Ok (CBlock (Details (s_ils, body_blocks)))
  | S_term, Arg_nodes (_, dt) :: Arg_nodes (_, dd) :: _ ->
      let* dt_ils = elaborate_inlines dt in
      let* dd_ils = elaborate_inlines dd in
      Ok (CBlock (Description_list [ (dt_ils, [ Plain dd_ils ]) ]))
  | S_dingbat, Arg_symbol (_, name) :: _ ->
      Ok (CInline (Str (dingbat_char name)))
  | S_circled, Arg_number (_, n) :: _ -> Ok (CInline (Circled_ref n))
  | S_includegraphics, Arg_nodes (_, ns) :: _ ->
      Ok (CBlock (Image (opts, node_text_of_nodes ns)))
  | S_item, _ -> elab_error pos "hanging item command"
  | _ -> (
      match replacement_text sym with
      | Some repl -> Ok (CInline (Str (text repl)))
      | None ->
          if is_metadata_cmd sym then Ok CSkip
          else elab_error pos ("unknown command: \\" ^ sym_to_string sym))

and classify_env pos sym opts body =
  match sym with
  | S_abstract ->
      let* bs = build_blocks body in
      Ok (CBlock (Abstract bs))
  | S_enumerate ->
      let* items = split_list_items body in
      Ok (CBlock (Ordered_list items))
  | S_itemize ->
      let* items = split_list_items body in
      Ok (CBlock (Bullet_list (Arrows, items)))
  | S_checklist ->
      let* items = split_list_items body in
      Ok (CBlock (Bullet_list (Checklist, items)))
  | S_figure ->
      let* bs = build_blocks body in
      Ok (CBlock (Figure (opts, bs)))
  | S_description ->
      let* items = split_description_items body in
      Ok (CBlock (Description_list items))
  | S_verbatim ->
      let txt =
        concat_text_map (function NText (_, t) -> t | _ -> Text.empty) body
      in
      Ok (CBlock (Verbatim_block (opts, txt)))
  | S_code ->
      let* ils = elaborate_code_inlines body in
      Ok (CBlock (Code_block (opts, ils)))
  | _ -> elab_error pos ("unknown environment: " ^ sym_to_string sym)

and elaborate_inlines (ns : node list) : inline list result_ =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | n :: rest -> (
        let* cls = classify_node n in
        match cls with
        | CInline il -> go (il :: acc) rest
        | CBlock (Image (opts, path)) ->
            go (Image_inline (opts, path) :: acc) rest
        | _ -> go acc rest)
  in
  go [] ns

and elaborate_code_inlines (ns : node list) : inline list result_ =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | NText (_, t) :: rest -> go (Str t :: acc) rest
    | NGroup (_, body) :: rest ->
        let* ils = elaborate_code_inlines body in
        let il =
          match ils with [ il ] -> il | _ -> Str (inlines_to_text ils)
        in
        go (il :: acc) rest
    | NMath (_, disp, mnodes) :: rest -> go (Math (disp, mnodes) :: acc) rest
    | NQuotation (_, body) :: rest ->
        let* ils = elaborate_code_inlines body in
        go (Quotation ils :: acc) rest
    | NCmd (_, sym, opts, args) :: rest -> (
        match (sym, args) with
        | S_b, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Strong ils :: acc) rest
        | S_emph, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Emph ils :: acc) rest
        | S_u, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Underline ils :: acc) rest
        | S_textsc, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Small_caps ils :: acc) rest
        | S_strikethrough, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Strikethrough ils :: acc) rest
        | S_code, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Code (opts, ils) :: acc) rest
        | S_kbd, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Kbd ils :: acc) rest
        | S_sub, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Sub ils :: acc) rest
        | S_sup, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Sup ils :: acc) rest
        | S_href, Arg_url (_, url) :: Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Link (url, ils) :: acc) rest
        | S_fun, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Fun ils :: acc) rest
        | S_math, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Math_span ils :: acc) rest
        | S_normal, Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Normal ils :: acc) rest
        | S_label, Arg_symbol (_, anchor) :: _ -> go (Anchor anchor :: acc) rest
        | S_newline, _ -> go (Line_break :: acc) rest
        | S_numspace, _ -> go (Numeric_space :: acc) rest
        | S_qed, _ -> go (Str (text "\xE2\x88\x8E") :: acc) rest
        | S_hrule, _ -> go (Horizontal_rule :: acc) rest
        | S_marginnote, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Margin_note (anchor, ils) :: acc) rest
        | S_sidenote, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _ ->
            let* ils = elaborate_code_inlines ns in
            go (Side_note (anchor, ils) :: acc) rest
        | S_dingbat, Arg_symbol (_, name) :: _ ->
            go (Str (dingbat_char name) :: acc) rest
        | S_circled, Arg_number (_, n) :: _ -> go (Circled_ref n :: acc) rest
        | S_nameref, Arg_symbol (_, r) :: _ -> go (Nameref r :: acc) rest
        | S_includegraphics, Arg_nodes (_, ns) :: _ ->
            go (Image_inline (opts, node_text_of_nodes ns) :: acc) rest
        | _ -> (
            match replacement_text sym with
            | Some repl -> go (Str (text repl) :: acc) rest
            | None -> go acc rest))
    | _ :: rest -> go acc rest
  in
  go [] ns

and build_flat_blocks (ns : node list) : flat_block list result_ =
  let is_block_level_only_content ils =
    ils <> []
    && List.for_all
         (function
           | Margin_note _ | Side_note _ | Anchor _ | Line_break -> true
           | Str t when Text.for_all is_whitespace t -> true
           | _ -> false)
         ils
  in
  let has_para_break_before_first_lb =
    let rec find = function
      | [] -> false
      | Line_break :: _ -> false
      | Str t :: rest -> text_has_double_newline t || find rest
      | _ :: rest -> find rest
    in
    find
  in
  let prepend_blocks_rev blocks blocks_rev =
    List.fold_left (fun acc b -> FB b :: acc) blocks_rev blocks
  in
  let flush_para_rev inlines_acc blocks_rev =
    if inlines_acc = [] then blocks_rev
    else
      let ordered = List.rev inlines_acc in
      let trimmed = trim_inlines ordered in
      if
        (not (has_para_break_before_first_lb ordered))
        && is_block_level_only_content trimmed
      then FB (Plain trimmed) :: blocks_rev
      else
        let paras = split_paragraphs ordered in
        prepend_blocks_rev paras blocks_rev
  in
  let rec go inlines_acc blocks_rev = function
    | [] -> Ok (List.rev (flush_para_rev inlines_acc blocks_rev))
    | n :: rest -> (
        let* cls = classify_node n in
        match cls with
        | CBlock blk ->
            go [] (FB blk :: flush_para_rev inlines_acc blocks_rev) rest
        | CSection mark ->
            go [] (mark :: flush_para_rev inlines_acc blocks_rev) rest
        | CInline il -> go (il :: inlines_acc) blocks_rev rest
        | CSkip -> go inlines_acc blocks_rev rest)
  in
  go [] [] ns

and build_blocks (ns : node list) : block list result_ =
  let* fbs = build_flat_blocks ns in
  Ok (List.filter_map (function FB b -> Some b | _ -> None) fbs)

and split_list_items (ns : node list) : block list list result_ =
  let is_item = function NCmd (_, S_item, _, _) -> true | _ -> false in
  let rec split acc cur = function
    | [] -> List.rev (List.rev cur :: acc)
    | n :: rest when is_item n -> split (List.rev cur :: acc) [] rest
    | n :: rest -> split acc (n :: cur) rest
  in
  let items = split [] [] ns in
  let rec build_rev acc = function
    | [] -> Ok acc
    | [] :: rest -> build_rev acc rest
    | group :: rest -> (
        let* bs = build_blocks group in
        let wrapped =
          match bs with
          | [ Para ils ] -> [ Plain ils ]
          | Para ils :: rest -> Plain ils :: rest
          | _ -> bs
        in
        match wrapped with
        | [] -> build_rev acc rest
        | _ -> build_rev (wrapped :: acc) rest)
  in
  let* rev_items = build_rev [] items in
  Ok (List.rev rev_items)

and split_description_items (ns : node list) :
    (inline list * block list) list result_ =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | NCmd (_, S_term, _, Arg_nodes (_, dt) :: Arg_nodes (_, dd) :: _) :: rest
      ->
        let* dt_ils = elaborate_inlines dt in
        let* dd_blocks = build_blocks dd in
        let dd_wrapped =
          match dd_blocks with [ Para ils ] -> [ Plain ils ] | _ -> dd_blocks
        in
        go ((dt_ils, dd_wrapped) :: acc) rest
    | _ :: rest -> go acc rest
  in
  go [] ns

and elaborate_table _name opts spec rows : table_def result_ =
  let name = _name in
  let header_row, body_rows =
    match rows with
    | r :: rs when name = "tabular" -> (Some r, rs)
    | _ -> (None, rows)
  in
  let elaborate_cell (c : cell) : table_cell result_ =
    let* content = elaborate_inlines c.cell_body in
    Ok
      {
        tc_colspan = c.cell_colspan;
        tc_align = c.cell_align;
        tc_content = content;
      }
  in
  let elaborate_row (r : row) : table_row result_ =
    let* cells = map_m elaborate_cell r.row_cells in
    let top = r.row_borders = Border_top || r.row_borders = Border_both in
    let bot = r.row_borders = Border_bottom || r.row_borders = Border_both in
    Ok { tr_border_top = top; tr_border_bottom = bot; tr_cells = cells }
  in
  let* header =
    match header_row with
    | None -> Ok None
    | Some r ->
        let* r' = elaborate_row r in
        Ok (Some r')
  in
  let* body = map_m elaborate_row body_rows in
  Ok
    {
      table_spec = spec;
      table_header = header;
      table_rows = body;
      table_opts = opts;
    }

(* --- Section wrapping --- *)

let is_section_mark = function
  | SectionMark _ | AnonSectionMark -> true
  | _ -> false

let is_subsection_mark = function SubsectionMark _ -> true | _ -> false

let extract_blocks fbs =
  List.filter_map (function FB b -> Some b | _ -> None) fbs

let break_on (p : 'a -> bool) (xs : 'a list) : 'a list * 'a list =
  let rec go acc = function
    | [] -> (List.rev acc, [])
    | x :: rest when p x -> (List.rev acc, x :: rest)
    | x :: rest -> go (x :: acc) rest
  in
  go [] xs

let check_no_subsections (fbs : flat_block list) : unit result_ =
  let rec find = function
    | [] -> None
    | SubsectionMark (pos, _, _) :: _ -> Some pos
    | _ :: rest -> find rest
  in
  match find fbs with
  | Some pos -> elab_error pos "\\subsection not allowed in anonymous section"
  | None -> Ok ()

let rec group_subsections : flat_block list -> block list = function
  | [] -> []
  | SubsectionMark (_, anchor, title) :: rest ->
      let content, more = break_on is_subsection_mark rest in
      Subsection (anchor, title, extract_blocks content)
      :: group_subsections more
  | _ :: rest -> group_subsections rest

let wrap_subsections (fbs : flat_block list) : block list result_ =
  let pre, rest = break_on is_subsection_mark fbs in
  Ok (List.rev_append (List.rev (extract_blocks pre)) (group_subsections rest))

let rec group_sections : flat_block list -> block list result_ = function
  | [] -> Ok []
  | mark :: bs ->
      let content, rest = break_on is_section_mark bs in
      let* sec =
        match mark with
        | SectionMark (anchor, title) ->
            let* body = wrap_subsections content in
            Ok (Section (Some (anchor, title), body))
        | AnonSectionMark ->
            let* () = check_no_subsections content in
            Ok (Section (None, extract_blocks content))
        | _ -> failwith "impossible: non-section mark after filter"
      in
      let* more = group_sections rest in
      Ok (sec :: more)

let wrap_sections (fbs : flat_block list) : block list result_ =
  let preamble, rest = break_on is_section_mark fbs in
  let* () = check_no_subsections preamble in
  let* sections = group_sections rest in
  let preamble_blocks = extract_blocks preamble in
  Ok (preamble_blocks @ sections)

(* --- Top-level entry point --- *)

let elaborate (slug : string) (nodes : node list) : article result_ =
  let* meta = extract_metadata nodes in
  let doc_body = find_doc_body nodes in
  let* flat = build_flat_blocks doc_body in
  let* body = wrap_sections flat in
  Ok
    {
      art_slug = text slug;
      art_title = [ Str (apply_typography meta.m_title) ];
      art_subtitle = [ Str (apply_typography meta.m_subtitle) ];
      art_featured = meta.m_featured;
      art_created_at = meta.m_created_at;
      art_modified_at = meta.m_modified_at;
      art_word_count = Stats.word_count body;
      art_keywords = List.sort Text.compare meta.m_keywords;
      art_body = body;
      art_url = text ("/posts/" ^ slug ^ ".html");
      art_reddit = meta.m_reddit;
      art_hn = meta.m_hn;
      art_lobsters = meta.m_lobsters;
    }
