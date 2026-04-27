(* Semantic document model. *)

(* Reuse math types and column spec from Syntax *)
type math_display = Syntax.math_display
type math_node = Syntax.math_node
type col_spec = Syntax.col_spec

(* Inline elements *)
type inline =
  | Str of Text.t (* plain text, typography already applied *)
  | Strong of inline list
  | Emph of inline list
  | Underline of inline list
  | Small_caps of inline list
  | Strikethrough of inline list
  | Code of Text.t list * inline list (* css classes, body *)
  | Link of Text.t * inline list (* url, body *)
  | Math of math_display * math_node list (* preserved for MathML rendering *)
  | Margin_note of Text.t * inline list (* anchor, body *)
  | Side_note of Text.t * inline list (* anchor, body *)
  | Kbd of inline list
  | Sub of inline list
  | Sup of inline list
  | Quotation of inline list (* ``...'' → <q>...</q> *)
  | Cite of inline list
  | Fun of inline list (* \fun → <span class="fun"> *)
  | Math_span of inline list (* \math → <span class="math"> *)
  | Normal of inline list (* \normal → <span class="normal"> *)
  | Anchor of Text.t (* id for \label *)
  | Horizontal_rule
  | Circled_ref of int
  | Line_break
  | Numeric_space
  | Nameref of Text.t (* label for \nameref *)
  | Image_inline of
      Text.t list
      * Text.t (* css classes, src path (for inline/table contexts) *)

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
  table_opts : Text.t list;
}

(* Block-level elements *)
type block =
  | Para of inline list
  | Plain of inline list (* inlines without paragraph wrapping *)
  | Section of
      (Text.t * inline list) option
      * block list (* None = anonymous, Some (anchor, title) = named *)
  | Subsection of Text.t * inline list * block list (* anchor, title, body *)
  | Code_block of
      Text.t list
      * inline list (* css classes, formatted body with line spans *)
  | Verbatim_block of
      Text.t list * Text.t (* css classes, raw text (no line spans) *)
  | Bullet_list of list_style * block list list
  | Ordered_list of block list list
  | Description_list of (inline list * block list) list
  | Blockquote of block list * inline list (* body, attribution *)
  | Epigraph of block list * inline list (* body, attribution *)
  | Table of table_def
  | Image of Text.t list * Text.t (* css classes, src path *)
  | Figure of Text.t list * block list (* css classes, body *)
  | Abstract of block list
  | Advice of Text.t * inline list (* anchor, content *)
  | Details of inline list * block list (* summary, body *)
  | Center of block list
  | Figcaption of inline list
  | HRule

(* Reference table for nameref resolution *)
type reference = { ref_title : Text.t; ref_url : Text.t }

module RefTable = Text.Map

type ref_table = reference RefTable.t

(* Article metadata extracted during elaboration *)
type article = {
  art_slug : Text.t;
  art_title : inline list;
  art_subtitle : inline list;
  art_featured : bool;
  art_created_at : Date.t;
  art_modified_at : Date.t;
  art_word_count : int;
  art_keywords : Text.t list;
  art_body : block list;
  art_url : Text.t;
  art_reddit : Text.t option;
  art_hn : Text.t option;
  art_lobsters : Text.t option;
}
