(* Semantic document model. Mirror of Blogware.Document. *)

(* Reuse math types and column spec from Syntax *)
type math_display = Syntax.math_display
type math_node = Syntax.math_node
type col_spec = Syntax.col_spec
type mathml_tree = Syntax.node list

(* Inline elements *)
type inline =
  | Str of string (* plain text, typography already applied *)
  | Strong of inline list
  | Emph of inline list
  | Underline of inline list
  | Small_caps of inline list
  | Strikethrough of inline list
  | Code of string list * inline list (* css classes, body *)
  | Link of string * inline list (* url, body *)
  | Math of math_display * math_node list (* preserved for MathML rendering *)
  | Margin_note of string * inline list (* anchor, body *)
  | Side_note of string * inline list (* anchor, body *)
  | Kbd of inline list
  | Sub of inline list
  | Sup of inline list
  | Quotation of inline list (* ``...'' → <q>...</q> *)
  | Fun of inline list (* \fun → <span class="fun"> *)
  | Math_span of inline list (* \math → <span class="math"> *)
  | Normal of inline list (* \normal → <span class="normal"> *)
  | Anchor of string (* id for \label *)
  | Horizontal_rule
  | Circled_ref of int
  | Line_break
  | Numeric_space
  | Nameref of string (* label for \nameref *)
  | Mathml of
      string list * mathml_tree (* direct MathML snippet options + body *)
  | Image_inline of
      string list
      * string (* css classes, src path (for inline/table contexts) *)

(* List style for bullet lists *)
type list_style = Arrows | Checklist

(* Table cell *)
type table_cell = {
  tc_colspan : int;
  tc_align : col_spec;
  tc_content : inline list;
}

(* Table row *)
type table_row = {
  tr_border_top : bool;
  tr_border_bottom : bool;
  tr_cells : table_cell list;
}

(* Full table *)
type table_def = {
  table_spec : col_spec list;
  table_header : table_row option;
  table_rows : table_row list;
  table_opts : string list;
}

(* Block-level elements *)
type block =
  | Para of inline list
  | Plain of inline list (* inlines without paragraph wrapping *)
  | Section of
      (string * inline list) option
      * block list (* None = anonymous, Some (anchor, title) = named *)
  | Subsection of string * inline list * block list (* anchor, title, body *)
  | Code_block of
      string list
      * inline list (* css classes, formatted body with line spans *)
  | Verbatim_block of
      string list * string (* css classes, raw text (no line spans) *)
  | Bullet_list of list_style * block list list
  | Ordered_list of block list list
  | Description_list of (inline list * block list) list
  | Blockquote of inline list * inline list (* body, attribution *)
  | Epigraph of inline list * inline list (* body, attribution *)
  | Table of table_def
  | Image of string list * string (* css classes, src path *)
  | Figure of string list * block list (* css classes, body *)
  | Abstract of block list
  | Advice of string * inline list (* anchor, content *)
  | Details of inline list * block list (* summary, body *)
  | Center of block list
  | HRule

(* Reference table for nameref resolution *)
type reference = { ref_title : string; ref_url : string }

module RefTable = Map.Make (String)

type ref_table = reference RefTable.t

(* Article metadata extracted during elaboration *)
type article = {
  art_slug : string;
  art_title : inline list;
  art_subtitle : inline list;
  art_created_at : Date.t;
  art_modified_at : Date.t;
  art_keywords : string list;
  art_body : block list;
  art_url : string;
  art_reddit : string option;
  art_hn : string option;
  art_lobsters : string option;
}
