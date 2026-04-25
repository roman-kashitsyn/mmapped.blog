(* TeX AST and command/environment registries. Mirror of Blogware.Syntax. *)

type pos = Parser.Pos.t

(* Math display mode *)
type math_display = Math_inline | Math_display

(* Column alignment for tabular environments *)
type col_spec = Col_left | Col_right | Col_center

(* Resolved command/environment/math-command name. Parsed strings are
   mapped to [sym] once during parsing so that downstream passes can
   pattern-match directly instead of comparing strings. *)
type sym =
  (* TeX commands *)
  | S_begin
  | S_end
  | S_label
  | S_dingbat
  | S_section
  | S_section_star
  | S_subsection
  | S_href
  | S_reddit
  | S_hackernews
  | S_lobsters
  | S_documentclass
  | S_includegraphics
  | S_date
  | S_details
  | S_modified
  | S_keyword
  | S_title
  | S_subtitle
  | S_featured
  | S_b
  | S_u
  | S_normal
  | S_emph
  | S_textsc
  | S_circled
  | S_code
  | S_center
  | S_item
  | S_math
  | S_sub
  | S_sup
  | S_fun
  | S_strikethrough
  | S_qed
  | S_advice
  | S_marginnote
  | S_sidenote
  | S_newline
  | S_numspace
  | S_hrule
  | S_epigraph
  | S_blockquote
  | S_cite
  | S_multicolumn
  | S_term
  | S_kbd
  | S_nameref
  (* environments *)
  | S_document
  | S_abstract
  | S_enumerate
  | S_itemize
  | S_checklist
  | S_figure
  | S_tabular
  | S_tabular_star
  | S_description
  | S_verbatim
  | S_align_star
  (* math commands *)
  | S_frac
  | S_binom
  | S_operatorname
  | S_mathrm
  | S_left
  | S_right
  (* text replacement commands *)
  | S_ldots
  | S_cdots
  | S_delta
  | S_delta_upper
  | S_pi
  | S_fracslash
  | S_prime
  | S_times
  | S_itimes
  | S_applyFun
  | S_circ
  | S_in
  | S_ni
  | S_notin
  | S_inf
  | S_notni
  | S_rightarrow
  | S_rightarrow_upper
  | S_leftarrow
  | S_leftarrow_upper
  | S_sum
  | S_oplus
  | S_prod
  | S_log
  | S_int
  | S_lim
  | S_leq
  | S_approx
  | S_iff
  | S_forall
  | S_exists
  (* unknown name *)
  | S_other of Text.t

module SMap = Text.Map

let smap_of_list xs =
  List.fold_left (fun m (k, v) -> SMap.add (Text.of_string k) v m) SMap.empty xs

(* Master name→sym table. *)
let sym_table : sym SMap.t =
  smap_of_list
    [
      (* commands *)
      ("begin", S_begin);
      ("end", S_end);
      ("label", S_label);
      ("dingbat", S_dingbat);
      ("section", S_section);
      ("section*", S_section_star);
      ("subsection", S_subsection);
      ("href", S_href);
      ("reddit", S_reddit);
      ("hackernews", S_hackernews);
      ("lobsters", S_lobsters);
      ("documentclass", S_documentclass);
      ("includegraphics", S_includegraphics);
      ("date", S_date);
      ("details", S_details);
      ("modified", S_modified);
      ("keyword", S_keyword);
      ("title", S_title);
      ("subtitle", S_subtitle);
      ("featured", S_featured);
      ("b", S_b);
      ("u", S_u);
      ("normal", S_normal);
      ("emph", S_emph);
      ("textsc", S_textsc);
      ("circled", S_circled);
      ("code", S_code);
      ("center", S_center);
      ("item", S_item);
      ("math", S_math);
      ("sub", S_sub);
      ("sup", S_sup);
      ("fun", S_fun);
      ("strikethrough", S_strikethrough);
      ("qed", S_qed);
      ("advice", S_advice);
      ("marginnote", S_marginnote);
      ("sidenote", S_sidenote);
      ("newline", S_newline);
      ("numspace", S_numspace);
      ("hrule", S_hrule);
      ("epigraph", S_epigraph);
      ("blockquote", S_blockquote);
      ("cite", S_cite);
      ("multicolumn", S_multicolumn);
      ("term", S_term);
      ("kbd", S_kbd);
      ("nameref", S_nameref);
      (* environments *)
      ("document", S_document);
      ("abstract", S_abstract);
      ("enumerate", S_enumerate);
      ("itemize", S_itemize);
      ("checklist", S_checklist);
      ("figure", S_figure);
      ("tabular", S_tabular);
      ("tabular*", S_tabular_star);
      ("description", S_description);
      ("verbatim", S_verbatim);
      ("align*", S_align_star);
      (* math commands *)
      ("frac", S_frac);
      ("binom", S_binom);
      ("operatorname", S_operatorname);
      ("mathrm", S_mathrm);
      ("left", S_left);
      ("right", S_right);
      (* replacements *)
      ("ldots", S_ldots);
      ("cdots", S_cdots);
      ("delta", S_delta);
      ("Delta", S_delta_upper);
      ("pi", S_pi);
      ("fracslash", S_fracslash);
      ("prime", S_prime);
      ("times", S_times);
      ("itimes", S_itimes);
      ("applyFun", S_applyFun);
      ("circ", S_circ);
      ("in", S_in);
      ("ni", S_ni);
      ("notin", S_notin);
      ("inf", S_inf);
      ("notni", S_notni);
      ("rightarrow", S_rightarrow);
      ("Rightarrow", S_rightarrow_upper);
      ("leftarrow", S_leftarrow);
      ("Leftarrow", S_leftarrow_upper);
      ("sum", S_sum);
      ("oplus", S_oplus);
      ("prod", S_prod);
      ("log", S_log);
      ("int", S_int);
      ("lim", S_lim);
      ("leq", S_leq);
      ("approx", S_approx);
      ("iff", S_iff);
      ("forall", S_forall);
      ("exists", S_exists);
    ]

let resolve_sym (name : Text.t) : sym =
  match SMap.find_opt name sym_table with Some s -> s | None -> S_other name

let sym_to_string = function
  | S_begin -> "begin"
  | S_end -> "end"
  | S_label -> "label"
  | S_dingbat -> "dingbat"
  | S_section -> "section"
  | S_section_star -> "section*"
  | S_subsection -> "subsection"
  | S_href -> "href"
  | S_reddit -> "reddit"
  | S_hackernews -> "hackernews"
  | S_lobsters -> "lobsters"
  | S_documentclass -> "documentclass"
  | S_includegraphics -> "includegraphics"
  | S_date -> "date"
  | S_details -> "details"
  | S_modified -> "modified"
  | S_keyword -> "keyword"
  | S_title -> "title"
  | S_subtitle -> "subtitle"
  | S_featured -> "featured"
  | S_b -> "b"
  | S_u -> "u"
  | S_normal -> "normal"
  | S_emph -> "emph"
  | S_textsc -> "textsc"
  | S_circled -> "circled"
  | S_code -> "code"
  | S_center -> "center"
  | S_item -> "item"
  | S_math -> "math"
  | S_sub -> "sub"
  | S_sup -> "sup"
  | S_fun -> "fun"
  | S_strikethrough -> "strikethrough"
  | S_qed -> "qed"
  | S_advice -> "advice"
  | S_marginnote -> "marginnote"
  | S_sidenote -> "sidenote"
  | S_newline -> "newline"
  | S_numspace -> "numspace"
  | S_hrule -> "hrule"
  | S_epigraph -> "epigraph"
  | S_blockquote -> "blockquote"
  | S_cite -> "cite"
  | S_multicolumn -> "multicolumn"
  | S_term -> "term"
  | S_kbd -> "kbd"
  | S_nameref -> "nameref"
  | S_document -> "document"
  | S_abstract -> "abstract"
  | S_enumerate -> "enumerate"
  | S_itemize -> "itemize"
  | S_checklist -> "checklist"
  | S_figure -> "figure"
  | S_tabular -> "tabular"
  | S_tabular_star -> "tabular*"
  | S_description -> "description"
  | S_verbatim -> "verbatim"
  | S_align_star -> "align*"
  | S_frac -> "frac"
  | S_binom -> "binom"
  | S_operatorname -> "operatorname"
  | S_mathrm -> "mathrm"
  | S_left -> "left"
  | S_right -> "right"
  | S_ldots -> "ldots"
  | S_cdots -> "cdots"
  | S_delta -> "delta"
  | S_delta_upper -> "Delta"
  | S_pi -> "pi"
  | S_fracslash -> "fracslash"
  | S_prime -> "prime"
  | S_times -> "times"
  | S_itimes -> "itimes"
  | S_applyFun -> "applyFun"
  | S_circ -> "circ"
  | S_in -> "in"
  | S_ni -> "ni"
  | S_notin -> "notin"
  | S_inf -> "inf"
  | S_notni -> "notni"
  | S_rightarrow -> "rightarrow"
  | S_rightarrow_upper -> "Rightarrow"
  | S_leftarrow -> "leftarrow"
  | S_leftarrow_upper -> "Leftarrow"
  | S_sum -> "sum"
  | S_oplus -> "oplus"
  | S_prod -> "prod"
  | S_log -> "log"
  | S_int -> "int"
  | S_lim -> "lim"
  | S_leq -> "leq"
  | S_approx -> "approx"
  | S_iff -> "iff"
  | S_forall -> "forall"
  | S_exists -> "exists"
  | S_other s -> Text.to_string s

(* Math AST *)
type math_node =
  | Math_term of math_node * math_node option * math_node option
  (* nucleus, sub, sup *)
  | Math_frac of math_node * math_node
  | Math_cmd of sym * math_node list
  | Math_op of Text.t * bool (* operator name, stretchy *)
  | Math_num of Text.t
  | Math_text of Text.t
  | Math_sym of char
  | Math_group of math_node list
  | Math_align of col_spec list * math_node list list list

(* Optional row borders *)
type row_border = Border_none | Border_top | Border_bottom | Border_both

(* TeX AST nodes *)
type node =
  | NText of pos * Text.t
  | NCmd of pos * sym * Text.t list * arg list
  (* \cmd[opts]{arg1}{arg2} *)
  | NEnv of pos * pos * sym * Text.t list * node list
  (* \begin{env}[opts] ... \end{env} ; first pos = begin, second = end *)
  | NGroup of pos * node list
  | NQuotation of pos * node list
  (* ``...'' — balanced pair; renders as a <q> inline. *)
  | NTable of pos * pos * sym * Text.t list * col_spec list * row list
  | NMath of pos * math_display * math_node list

and arg =
  | Arg_nodes of pos * node list
  | Arg_symbol of pos * Text.t
  | Arg_number of pos * int
  | Arg_url of pos * Text.t
  | Arg_align of pos * col_spec list

and cell = {
  cell_pos : pos;
  cell_align : col_spec;
  cell_colspan : int;
  cell_body : node list;
}

and row = { row_borders : row_border; row_cells : cell list }

(* Argument type specifications for command-name-driven argument parsing.
   Prefix [At_] avoids clashing with the [arg] constructors above (notably
   [Arg_url] which exists in both). *)
type arg_type =
  | At_seq (* {balanced sequence of nodes} *)
  | At_sym (* {symbol token} *)
  | At_num (* {integer literal} *)
  | At_url (* {url string} *)
  | At_align_spec (* {column alignment letters} *)

type math_arg_type = Math_arg_expr | Math_arg_sym

(* Command argument type registry *)
let cmd_args : arg_type list SMap.t =
  smap_of_list
    [
      ("begin", [ At_sym ]);
      ("end", [ At_sym ]);
      ("label", [ At_sym ]);
      ("dingbat", [ At_sym ]);
      ("section", [ At_sym; At_seq ]);
      ("section*", []);
      ("subsection", [ At_sym; At_seq ]);
      ("href", [ At_url; At_seq ]);
      ("reddit", [ At_url ]);
      ("hackernews", [ At_url ]);
      ("lobsters", [ At_url ]);
      ("documentclass", [ At_sym ]);
      ("includegraphics", [ At_seq ]);
      ("date", [ At_sym ]);
      ("details", [ At_seq; At_seq ]);
      ("modified", [ At_sym ]);
      ("keyword", [ At_sym ]);
      ("title", [ At_seq ]);
      ("subtitle", [ At_seq ]);
      ("b", [ At_seq ]);
      ("u", [ At_seq ]);
      ("normal", [ At_seq ]);
      ("emph", [ At_seq ]);
      ("textsc", [ At_seq ]);
      ("circled", [ At_num ]);
      ("code", [ At_seq ]);
      ("center", [ At_seq ]);
      ("item", []);
      ("math", [ At_seq ]);
      ("sub", [ At_seq ]);
      ("sup", [ At_seq ]);
      ("fun", [ At_seq ]);
      ("strikethrough", [ At_seq ]);
      ("qed", []);
      ("advice", [ At_sym; At_seq ]);
      ("marginnote", [ At_sym; At_seq ]);
      ("sidenote", [ At_sym; At_seq ]);
      ("newline", []);
      ("numspace", []);
      ("hrule", []);
      ("epigraph", [ At_seq; At_seq ]);
      ("blockquote", [ At_seq; At_seq ]);
      ("cite", [ At_seq ]);
      ("multicolumn", [ At_num; At_align_spec; At_seq ]);
      ("term", [ At_seq; At_seq ]);
      ("kbd", [ At_seq ]);
      ("nameref", [ At_sym ]);
    ]

let math_cmds : math_arg_type list SMap.t =
  smap_of_list
    [
      ("frac", [ Math_arg_expr; Math_arg_expr ]);
      ("binom", [ Math_arg_expr; Math_arg_expr ]);
      ("operatorname", [ Math_arg_sym ]);
      ("mathrm", [ Math_arg_sym ]);
      ("left", []);
      ("right", []);
    ]

(* Text replacement commands. Returns [Some text] for symbols that
   should be replaced with the given Unicode text. *)
let replacement_text : sym -> string option = function
  | S_ldots -> Some "\xE2\x80\xA6" (* … U+2026 *)
  | S_cdots -> Some "\xE2\x8B\xAF" (* ⋯ U+22EF *)
  | S_delta -> Some "\xCE\xB4" (* δ U+03B4 *)
  | S_delta_upper -> Some "\xCE\x94" (* Δ U+0394 *)
  | S_pi -> Some "\xCF\x80" (* π U+03C0 *)
  | S_fracslash -> Some "\xE2\x88\x95" (* ∕ U+2215 *)
  | S_prime -> Some "\xE2\x80\xB2" (* ′ U+2032 *)
  | S_times -> Some "\xC3\x97" (* × U+00D7 *)
  | S_itimes -> Some "\xE2\x81\xA2" (* ⁢ U+2062 *)
  | S_applyFun -> Some "\xE2\x81\xA1" (* ⁡ U+2061 *)
  | S_circ -> Some "\xE2\x88\x98" (* ∘ U+2218 *)
  | S_in -> Some "\xE2\x88\x88" (* ∈ U+2208 *)
  | S_ni -> Some "\xE2\x88\x8B" (* ∋ U+220B *)
  | S_notin -> Some "\xE2\x88\x89" (* ∉ U+2209 *)
  | S_inf -> Some "\xE2\x88\x9E" (* ∞ U+221E *)
  | S_notni -> Some "\xE2\x88\x8C" (* ∌ U+220C *)
  | S_rightarrow -> Some "\xE2\x86\x92" (* → U+2192 *)
  | S_rightarrow_upper -> Some "\xE2\x87\x92" (* ⇒ U+21D2 *)
  | S_leftarrow -> Some "\xE2\x86\x90" (* ← U+2190 *)
  | S_leftarrow_upper -> Some "\xE2\x87\x90" (* ⇐ U+21D0 *)
  | S_sum -> Some "\xE2\x88\x91" (* ∑ U+2211 *)
  | S_oplus -> Some "\xE2\x8A\x95" (* ⊕ U+2295 *)
  | S_prod -> Some "\xE2\x88\x8F" (* ∏ U+220F *)
  | S_log -> Some "log"
  | S_int -> Some "\xE2\x88\xAB" (* ∫ U+222B *)
  | S_lim -> Some "lim"
  | S_leq -> Some "\xE2\x89\xA4" (* ≤ U+2264 *)
  | S_approx -> Some "\xE2\x89\x88" (* ≈ U+2248 *)
  | S_iff -> Some "\xE2\x87\x94" (* ⇔ U+21D4 *)
  | S_forall -> Some "\xE2\x88\x80" (* ∀ U+2200 *)
  | S_exists -> Some "\xE2\x88\x83" (* ∃ U+2203 *)
  | _ -> None

(* Metadata commands that are consumed during metadata extraction
   and should be silently skipped during block building. *)
let is_metadata_cmd = function
  | S_documentclass | S_title | S_subtitle | S_featured | S_date | S_modified
  | S_keyword | S_reddit | S_hackernews | S_lobsters ->
      true
  | _ -> false

(* Big math operators that use munder/mover. *)
let is_big_op = function S_sum | S_prod | S_int | S_lim -> true | _ -> false
