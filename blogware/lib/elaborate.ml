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

(* --- Typography --- *)

(* Apply TeX-style typographic replacements for characters that slip past
   the parser-level quotation handler (unbalanced `` or ''). Balanced
   ``...'' regions are already structured as [NQuotation] → [Quotation]
   nodes before reaching this pass and never appear in a [Str]. *)
let typographic_replacements : (string * string) list =
  [
    ("---", "\xE2\x80\x94" (* em dash — *));
    ("--", "\xE2\x80\x93" (* en dash – *));
    ("``", "\xE2\x80\x9C" (* left double quote “ *));
    ("''", "\xE2\x80\x9D" (* right double quote ” *));
    ("'", "\xE2\x80\x99" (* right single quote ’ *));
  ]

let is_typography_special c =
  match c with '-' | '`' | '\'' -> true | _ -> false

let is_whitespace c =
  match c with ' ' | '\x0C' | '\t' | '\n' | '\r' -> true | _ -> false

(* Try each replacement at the start of [s]; return (replacement, rest_len)
   on first match, or None. *)
let try_replacement_at s i =
  let rec go = function
    | [] -> None
    | (pref, rep) :: rest ->
        if Strings.has_prefix_at s i pref then Some (rep, String.length pref)
        else go rest
  in
  go typographic_replacements

let apply_typography (input : string) : string =
  if not (Strings.any input is_typography_special) then input
  else begin
    let b = Buffer.create (String.length input) in
    let len = String.length input in
    let i = ref 0 in
    while !i < len do
      let c = input.[!i] in
      if not (is_typography_special c) then begin
        Buffer.add_char b c;
        incr i
      end
      else
        begin match try_replacement_at input !i with
        | Some (rep, used) ->
            Buffer.add_string b rep;
            i := !i + used
        | None ->
            Buffer.add_char b c;
            incr i
        end
    done;
    Buffer.contents b
  end

(* --- Dingbats --- *)

let dingbat_char = function
  | "heavy-ballot-x" -> "\xE2\x9C\x97" (* ✗ *)
  | "heavy-check" -> "\xE2\x9C\x94" (* ✔ *)
  | "lower-right-pencil" -> "\xE2\x9C\x8E" (* ✎ *)
  | name -> "[dingbat:" ^ name ^ "]"

(* --- Metadata extraction --- *)

type meta = {
  m_title : string;
  m_subtitle : string;
  m_featured : bool;
  m_created_at : Date.t;
  m_modified_at : Date.t;
  m_keywords : string list;
  m_reddit : string option;
  m_hn : string option;
  m_lobsters : string option;
}

let default_meta : meta =
  let epoch = Date.make ~year:1970 ~month:1 ~day:1 in
  {
    m_title = "";
    m_subtitle = "";
    m_featured = false;
    m_created_at = epoch;
    m_modified_at = epoch;
    m_keywords = [];
    m_reddit = None;
    m_hn = None;
    m_lobsters = None;
  }

(* Parse a "YYYY-MM-DD" date; tie source position into the error. *)
let parse_day pos t : Date.t result_ =
  match Date.of_string t with
  | Some d -> Ok d
  | None -> elab_error pos ("invalid date: " ^ t ^ " (expected YYYY-MM-DD)")

(* Flatten text-like nodes back to a string for simple arg contexts. *)
let rec node_text_of_nodes ns = String.concat "" (List.map node_text ns)

and node_text = function
  | NText (_, t) -> t
  | NCmd (_, name, _, args) ->
      "\\" ^ name
      ^ String.concat ""
          (List.map
             (function
               | Arg_nodes (_, ns) -> "{" ^ node_text_of_nodes ns ^ "}"
               | _ -> "")
             args)
  | _ -> ""

(* Fold over top-level nodes collecting metadata. *)
let extract_metadata (nodes : node list) : meta result_ =
  let rec go m = function
    | [] -> Ok m
    | NCmd (_, "title", _, Arg_nodes (_, ns) :: _) :: rest ->
        go { m with m_title = node_text_of_nodes ns } rest
    | NCmd (_, "subtitle", _, Arg_nodes (_, ns) :: _) :: rest ->
        go { m with m_subtitle = node_text_of_nodes ns } rest
    | NCmd (_, "featured", _, _) :: rest -> go { m with m_featured = true } rest
    | NCmd (_, "date", _, Arg_symbol (pos, d) :: _) :: rest ->
        let* day = parse_day pos d in
        go { m with m_created_at = day; m_modified_at = day } rest
    | NCmd (_, "modified", _, Arg_symbol (pos, d) :: _) :: rest ->
        let* day = parse_day pos d in
        go { m with m_modified_at = day } rest
    | NCmd (_, "keyword", _, Arg_symbol (_, k) :: _) :: rest ->
        go { m with m_keywords = k :: m.m_keywords } rest
    | NCmd (_, "reddit", _, Arg_url (_, u) :: _) :: rest ->
        go { m with m_reddit = Some u } rest
    | NCmd (_, "hackernews", _, Arg_url (_, u) :: _) :: rest ->
        go { m with m_hn = Some u } rest
    | NCmd (_, "lobsters", _, Arg_url (_, u) :: _) :: rest ->
        go { m with m_lobsters = Some u } rest
    | _ :: rest -> go m rest
  in
  go default_meta nodes

(* Find the body of \begin{document} ... \end{document}. *)
let rec find_doc_body = function
  | [] -> []
  | NEnv (_, _, "document", _, body) :: _ -> body
  | _ :: rest -> find_doc_body rest

(* --- Block building ---
   A [flat_block] captures either a real block or a section/subsection
   marker. [wrap_sections] groups these into nested Section/Subsection
   blocks. *)

type flat_block =
  | FB of block
  | SectionMark of string * inline list
  | AnonSectionMark
  | SubsectionMark of Parser.Pos.t * string * inline list

type node_class =
  | CBlock of block
  | CSection of flat_block
  | CInline of inline
  | CSkip

(* Flatten inlines back to plain text (used for groups that appear in a
   text context, e.g. inside \title{...\b{X}...}). *)
let render_inlines_to_text (ils : inline list) : string =
  let buf = Buffer.create 64 in
  let rec add_inlines = function
    | [] -> ()
    | il :: rest ->
        add_inline il;
        add_inlines rest
  and add_inline = function
    | Str t -> Buffer.add_string buf t
    | Strong ils
    | Emph ils
    | Underline ils
    | Small_caps ils
    | Strikethrough ils
    | Kbd ils
    | Sub ils
    | Sup ils
    | Quotation ils
    | Fun ils
    | Math_span ils
    | Normal ils
    | Code (_, ils)
    | Link (_, ils)
    | Margin_note (_, ils)
    | Side_note (_, ils) ->
        add_inlines ils
    | Math _ | Anchor _ | Horizontal_rule | Circled_ref _ | Line_break
    | Numeric_space | Nameref _ | Image_inline _ ->
        ()
  in
  add_inlines ils;
  Buffer.contents buf

(* Paragraph splitting. Text containing "\n\n" is split into separate Para
   blocks. LineBreak and empty-string Str are trimmed at boundaries. *)

let is_paragraph_break = function
  | Str t -> Strings.is_infix_of "\n\n" t
  | _ -> false

let expand_breaks_il (il : inline) : inline list =
  match il with
  | Str t ->
      let rec go = function
        | [] -> []
        | [ x ] -> [ Str x ]
        | x :: rest -> Str x :: Str "\n\n" :: go rest
      in
      go (Strings.split_on t "\n\n")
  | il -> [ il ]

let trim_inlines (ils : inline list) : inline list =
  let is_ws = function Str t -> Strings.all t is_whitespace | _ -> false in
  let rec drop_left = function
    | [] -> []
    | x :: xs when is_ws x -> drop_left xs
    | xs -> xs
  in
  let drop_right xs = List.rev (drop_left (List.rev xs)) in
  drop_right (drop_left ils)

let split_on_pred (p : 'a -> bool) (xs : 'a list) : 'a list list =
  let groups = ref [] in
  let cur = ref [] in
  List.iter
    (fun x ->
      if p x then begin
        groups := List.rev !cur :: !groups;
        cur := []
      end
      else cur := x :: !cur)
    xs;
  groups := List.rev !cur :: !groups;
  List.rev !groups

(* Side-content inlines (marginnotes, sidenotes, anchors) are rendered
   inline by Go without paragraph wrapping. When a "paragraph" consists
   entirely of such inlines, emit [Plain] to avoid a spurious <p>. *)
let is_side_content = function
  | Margin_note _ | Side_note _ | Anchor _ -> true
  | _ -> false

let split_paragraphs (ils : inline list) : block list =
  let expanded = List.concat_map expand_breaks_il ils in
  let paras = split_on_pred is_paragraph_break expanded in
  List.filter_map
    (fun p ->
      match trim_inlines p with
      | [] -> None
      | trimmed ->
          if List.for_all is_side_content trimmed then Some (Plain trimmed)
          else Some (Para trimmed))
    paras

(* --- Classification ---
   classify_node is the big dispatch that decides, for a single parser
   node, whether it becomes a block, an inline, a section marker, or
   nothing. *)

let replacement_cmd_set =
  SMap.fold (fun k _ acc -> SSet.add k acc) replacements SSet.empty

let metadata_cmd_set =
  sset_of_list
    [
      "documentclass";
      "title";
      "subtitle";
      "featured";
      "date";
      "modified";
      "keyword";
      "reddit";
      "hackernews";
      "lobsters";
    ]

let rec classify_node (n : node) : node_class result_ =
  match n with
  | NText (_, t) -> Ok (CInline (Str (apply_typography t)))
  | NGroup (_, ns) -> (
      let* ils = elaborate_inlines ns in
      match ils with
      | [ il ] -> Ok (CInline il)
      | _ -> Ok (CInline (Str (render_inlines_to_text ils))))
  | NQuotation (_, ns) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Quotation ils))
  | NMath (_, disp, mnodes) -> Ok (CInline (Math (disp, mnodes)))
  | NCmd (_, "section", _, Arg_symbol (_, anchor) :: Arg_nodes (_, title) :: _)
    ->
      let* ils = elaborate_inlines title in
      Ok (CSection (SectionMark (anchor, ils)))
  | NCmd (_, "section*", _, _) -> Ok (CSection AnonSectionMark)
  | NCmd
      (pos, "subsection", _, Arg_symbol (_, anchor) :: Arg_nodes (_, title) :: _)
    ->
      let* ils = elaborate_inlines title in
      Ok (CSection (SubsectionMark (pos, anchor, ils)))
  | NCmd (_, "b", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Strong ils))
  | NCmd (_, "emph", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Emph ils))
  | NCmd (_, "u", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Underline ils))
  | NCmd (_, "textsc", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Small_caps ils))
  | NCmd (_, "strikethrough", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Strikethrough ils))
  | NCmd (_, "code", opts, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_code_inlines ns in
      Ok (CInline (Code (opts, ils)))
  | NCmd (_, "kbd", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Kbd ils))
  | NCmd (_, "sub", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Sub ils))
  | NCmd (_, "sup", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Sup ils))
  | NCmd (_, "fun", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Fun ils))
  | NCmd (_, "math", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Math_span ils))
  | NCmd (_, "normal", _, Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Normal ils))
  | NCmd (_, "center", _, Arg_nodes (_, ns) :: _) ->
      let* blocks = build_blocks ns in
      Ok (CBlock (Center blocks))
  | NCmd (_, "href", _, Arg_url (_, url) :: Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Link (url, ils)))
  | NCmd (_, "nameref", _, Arg_symbol (_, r) :: _) -> Ok (CInline (Nameref r))
  | NCmd (_, "label", _, Arg_symbol (_, anchor) :: _) ->
      Ok (CInline (Anchor anchor))
  | NCmd (_, "newline", _, _) -> Ok (CInline Line_break)
  | NCmd (_, "numspace", _, _) -> Ok (CInline Numeric_space)
  | NCmd (_, "hrule", _, _) -> Ok (CBlock HRule)
  | NCmd (_, "qed", _, _) -> Ok (CInline (Str "\xE2\x88\x8E"))
  | NCmd (_, "marginnote", _, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _)
    ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Margin_note (anchor, ils)))
  | NCmd (_, "sidenote", _, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CInline (Side_note (anchor, ils)))
  | NCmd (_, "advice", _, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _) ->
      let* ils = elaborate_inlines ns in
      Ok (CBlock (Advice (anchor, ils)))
  | NCmd (_, "epigraph", _, Arg_nodes (_, body) :: Arg_nodes (_, attrib) :: _)
    ->
      let* b_blocks = build_blocks body in
      let* a_ils = elaborate_inlines attrib in
      Ok (CBlock (Epigraph (b_blocks, a_ils)))
  | NCmd (_, "blockquote", _, Arg_nodes (_, body) :: Arg_nodes (_, attrib) :: _)
    ->
      let* b_blocks = build_blocks body in
      let* a_ils = elaborate_inlines attrib in
      Ok (CBlock (Blockquote (b_blocks, a_ils)))
  | NCmd (_, "details", _, Arg_nodes (_, summary) :: Arg_nodes (_, body) :: _)
    ->
      let* s_ils = elaborate_inlines summary in
      let* body_blocks = build_blocks body in
      Ok (CBlock (Details (s_ils, body_blocks)))
  | NCmd (_, "term", _, Arg_nodes (_, dt) :: Arg_nodes (_, dd) :: _) ->
      let* dt_ils = elaborate_inlines dt in
      let* dd_ils = elaborate_inlines dd in
      Ok (CBlock (Description_list [ (dt_ils, [ Plain dd_ils ]) ]))
  | NCmd (_, "dingbat", _, Arg_symbol (_, name) :: _) ->
      Ok (CInline (Str (dingbat_char name)))
  | NCmd (_, "circled", _, Arg_number (_, n) :: _) ->
      Ok (CInline (Circled_ref n))
  | NCmd (_, "includegraphics", opts, Arg_nodes (_, ns) :: _) ->
      Ok (CBlock (Image (opts, node_text_of_nodes ns)))
  | NCmd (pos, "item", _, _) -> elab_error pos "hanging item command"
  | NCmd (_, name, _, _) when SSet.mem name replacement_cmd_set ->
      let repl = SMap.find name replacements in
      Ok (CInline (Str repl))
  | NCmd (_, name, _, _) when SSet.mem name metadata_cmd_set -> Ok CSkip
  | NEnv (_, _, "abstract", _, body) ->
      let* bs = build_blocks body in
      Ok (CBlock (Abstract bs))
  | NEnv (_, _, "enumerate", _, body) ->
      let* items = split_list_items body in
      Ok (CBlock (Ordered_list items))
  | NEnv (_, _, "itemize", _, body) ->
      let* items = split_list_items body in
      Ok (CBlock (Bullet_list (Arrows, items)))
  | NEnv (_, _, "checklist", _, body) ->
      let* items = split_list_items body in
      Ok (CBlock (Bullet_list (Checklist, items)))
  | NEnv (_, _, "figure", opts, body) ->
      let* bs = build_blocks body in
      Ok (CBlock (Figure (opts, bs)))
  | NEnv (_, _, "description", _, body) ->
      let* items = split_description_items body in
      Ok (CBlock (Description_list items))
  | NEnv (_, _, "verbatim", opts, body) ->
      let txt =
        String.concat ""
          (List.map (function NText (_, t) -> t | _ -> "") body)
      in
      Ok (CBlock (Verbatim_block (opts, txt)))
  | NEnv (_, _, "code", opts, body) ->
      let* ils = elaborate_code_inlines body in
      Ok (CBlock (Code_block (opts, ils)))
  | NTable (_, _, name, opts, spec, rows) ->
      let* td = elaborate_table name opts spec rows in
      Ok (CBlock (Table td))
  | NCmd (pos, name, _, _) -> elab_error pos ("unknown command: \\" ^ name)
  | NEnv (pos, _, name, _, _) -> elab_error pos ("unknown environment: " ^ name)

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

(* Code env body: like [elaborate_inlines] but skips typography on text
   nodes. Inner command arguments also skip typography (matching Go's
   renderCodeText, which never applies typographic substitutions). *)
and elaborate_code_inlines (ns : node list) : inline list result_ =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | NText (_, t) :: rest -> go (Str t :: acc) rest
    | NGroup (_, body) :: rest ->
        let* ils = elaborate_code_inlines body in
        let il =
          match ils with [ il ] -> il | _ -> Str (render_inlines_to_text ils)
        in
        go (il :: acc) rest
    | NMath (_, disp, mnodes) :: rest -> go (Math (disp, mnodes) :: acc) rest
    | NQuotation (_, body) :: rest ->
        let* ils = elaborate_code_inlines body in
        go (Quotation ils :: acc) rest
    | NCmd (_, "b", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Strong ils :: acc) rest
    | NCmd (_, "emph", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Emph ils :: acc) rest
    | NCmd (_, "u", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Underline ils :: acc) rest
    | NCmd (_, "textsc", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Small_caps ils :: acc) rest
    | NCmd (_, "strikethrough", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Strikethrough ils :: acc) rest
    | NCmd (_, "code", opts, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Code (opts, ils) :: acc) rest
    | NCmd (_, "kbd", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Kbd ils :: acc) rest
    | NCmd (_, "sub", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Sub ils :: acc) rest
    | NCmd (_, "sup", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Sup ils :: acc) rest
    | NCmd (_, "href", _, Arg_url (_, url) :: Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Link (url, ils) :: acc) rest
    | NCmd (_, "fun", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Fun ils :: acc) rest
    | NCmd (_, "math", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Math_span ils :: acc) rest
    | NCmd (_, "normal", _, Arg_nodes (_, ns) :: _) :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Normal ils :: acc) rest
    | NCmd (_, "label", _, Arg_symbol (_, anchor) :: _) :: rest ->
        go (Anchor anchor :: acc) rest
    | NCmd (_, "newline", _, _) :: rest -> go (Line_break :: acc) rest
    | NCmd (_, "numspace", _, _) :: rest -> go (Numeric_space :: acc) rest
    | NCmd (_, "qed", _, _) :: rest -> go (Str "\xE2\x88\x8E" :: acc) rest
    | NCmd (_, "hrule", _, _) :: rest -> go (Horizontal_rule :: acc) rest
    | NCmd (_, "marginnote", _, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _)
      :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Margin_note (anchor, ils) :: acc) rest
    | NCmd (_, "sidenote", _, Arg_symbol (_, anchor) :: Arg_nodes (_, ns) :: _)
      :: rest ->
        let* ils = elaborate_code_inlines ns in
        go (Side_note (anchor, ils) :: acc) rest
    | NCmd (_, "dingbat", _, Arg_symbol (_, name) :: _) :: rest ->
        go (Str (dingbat_char name) :: acc) rest
    | NCmd (_, "circled", _, Arg_number (_, n) :: _) :: rest ->
        go (Circled_ref n :: acc) rest
    | NCmd (_, "nameref", _, Arg_symbol (_, r) :: _) :: rest ->
        go (Nameref r :: acc) rest
    | NCmd (_, "includegraphics", opts, Arg_nodes (_, ns) :: _) :: rest ->
        go (Image_inline (opts, node_text_of_nodes ns) :: acc) rest
    | NCmd (_, name, _, _) :: rest when SSet.mem name replacement_cmd_set ->
        go (Str (SMap.find name replacements) :: acc) rest
    | _ :: rest -> go acc rest
  in
  go [] ns

and build_flat_blocks (ns : node list) : flat_block list result_ =
  let is_block_level_only_content ils =
    let trimmed = trim_inlines ils in
    trimmed <> []
    && List.for_all
         (function
           | Margin_note _ | Side_note _ | Anchor _ | Line_break -> true
           | Str t when Strings.all t is_whitespace -> true
           | _ -> false)
         trimmed
  in
  let flush_para_rev inlines_acc blocks_rev =
    if inlines_acc = [] then blocks_rev
    else
      let ordered = List.rev inlines_acc in
      let trimmed = trim_inlines ordered in
      let has_para_break_before_first_lb =
        let rec find = function
          | [] -> false
          | Line_break :: _ -> false
          | Str t :: _ when Strings.is_infix_of "\n\n" t -> true
          | _ :: rest -> find rest
        in
        find ordered
      in
      if
        (not has_para_break_before_first_lb)
        && is_block_level_only_content trimmed
      then FB (Plain trimmed) :: blocks_rev
      else
        let paras = split_paragraphs ordered in
        List.rev_append (List.map (fun b -> FB b) paras) blocks_rev
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
  let is_item = function NCmd (_, "item", _, _) -> true | _ -> false in
  let rec split acc cur = function
    | [] -> List.rev (List.rev cur :: acc)
    | n :: rest when is_item n -> split (List.rev cur :: acc) [] rest
    | n :: rest -> split acc (n :: cur) rest
  in
  let items = split [] [] ns in
  (* Drop empty groups and build each one, then unwrap single-Para items.
     Accumulate in reverse for O(1) cons. *)
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
  let rec go = function
    | [] -> Ok []
    | NCmd (_, "term", _, Arg_nodes (_, dt) :: Arg_nodes (_, dd) :: _) :: rest
      ->
        let* dt_ils = elaborate_inlines dt in
        let* dd_blocks = build_blocks dd in
        let dd_wrapped =
          match dd_blocks with [ Para ils ] -> [ Plain ils ] | _ -> dd_blocks
        in
        let* more = go rest in
        Ok ((dt_ils, dd_wrapped) :: more)
    | _ :: rest -> go rest
  in
  go ns

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
    let rec map_m f = function
      | [] -> Ok []
      | x :: xs ->
          let* y = f x in
          let* ys = map_m f xs in
          Ok (y :: ys)
    in
    let* cells = map_m elaborate_cell r.row_cells in
    let top = r.row_borders = Border_top || r.row_borders = Border_both in
    let bot = r.row_borders = Border_bottom || r.row_borders = Border_both in
    Ok { tr_border_top = top; tr_border_bottom = bot; tr_cells = cells }
  in
  let rec map_m f = function
    | [] -> Ok []
    | x :: xs ->
        let* y = f x in
        let* ys = map_m f xs in
        Ok (y :: ys)
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
  (* Preamble blocks (before any \section) are emitted flat, not wrapped
     in a <section>, to match Go's renderGenericCmd which only opens
     <section> on SymSection/SymSectionS. *)
  Ok (preamble_blocks @ sections)

(* --- Top-level entry point --- *)

let elaborate (slug : string) (nodes : node list) : article result_ =
  let* meta = extract_metadata nodes in
  let doc_body = find_doc_body nodes in
  let* flat = build_flat_blocks doc_body in
  let* body = wrap_sections flat in
  Ok
    {
      art_slug = slug;
      art_title = [ Str (apply_typography meta.m_title) ];
      art_subtitle = [ Str (apply_typography meta.m_subtitle) ];
      art_featured = meta.m_featured;
      art_created_at = meta.m_created_at;
      art_modified_at = meta.m_modified_at;
      art_word_count = Stats.word_count body;
      art_keywords = List.sort compare meta.m_keywords;
      art_body = body;
      art_url = "/posts/" ^ slug ^ ".html";
      art_reddit = meta.m_reddit;
      art_hn = meta.m_hn;
      art_lobsters = meta.m_lobsters;
    }
