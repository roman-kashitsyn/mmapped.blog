(* TeX AST and command/environment registries. Mirror of Blogware.Syntax. *)

type pos = Parser_pos.t

(* Math display mode *)
type math_display = Math_inline | Math_display

(* Math AST *)
type math_node =
  | Math_term of math_node * math_node option * math_node option
  (* nucleus, sub, sup *)
  | Math_frac of math_node * math_node
  | Math_cmd of string * math_node list
  | Math_op of string * bool        (* operator name, stretchy *)
  | Math_num of string
  | Math_text of string
  | Math_sym of char
  | Math_group of math_node list

(* Column alignment for tabular environments *)
type col_spec = Col_left | Col_right | Col_center

(* Optional row borders *)
type row_border = Border_none | Border_top | Border_bottom | Border_both

(* TeX AST nodes *)
type node =
  | NText of pos * string
  | NCmd of pos * string * string list * arg list
  (* \cmd[opts]{arg1}{arg2} *)
  | NEnv of pos * pos * string * string list * node list
  (* \begin{env}[opts] ... \end{env} ; first pos = begin, second = end *)
  | NGroup of pos * node list
  | NQuotation of pos * node list
  (* ``...'' — balanced pair; renders as a <q> inline. *)
  | NTable of pos * pos * string * string list * col_spec list * row list
  | NMath of pos * math_display * math_node list

and arg =
  | Arg_nodes of pos * node list
  | Arg_symbol of pos * string
  | Arg_number of pos * int
  | Arg_url of pos * string
  | Arg_align of pos * col_spec list

and cell = {
  cell_pos : pos;
  cell_align : col_spec;
  cell_colspan : int;
  cell_body : node list;
}

and row = {
  row_borders : row_border;
  row_cells : cell list;
}

(* Argument type specifications for command-name-driven argument parsing.
   Prefix [At_] avoids clashing with the [arg] constructors above (notably
   [Arg_url] which exists in both). *)
type arg_type =
  | At_seq            (* {balanced sequence of nodes} *)
  | At_sym            (* {symbol token} *)
  | At_num            (* {integer literal} *)
  | At_url            (* {url string} *)
  | At_align_spec     (* {column alignment letters} *)

type math_arg_type = Math_arg_expr | Math_arg_sym

(* String map / set helpers *)
module SMap = Map.Make (String)
module SSet = Set.Make (String)

let smap_of_list xs =
  List.fold_left (fun m (k, v) -> SMap.add k v m) SMap.empty xs

let sset_of_list xs =
  List.fold_left (fun s k -> SSet.add k s) SSet.empty xs

(* Command argument type registry *)
let cmd_args : arg_type list SMap.t =
  smap_of_list
    [ "begin",           [At_sym]
    ; "end",             [At_sym]
    ; "label",           [At_sym]
    ; "dingbat",         [At_sym]
    ; "section",         [At_sym; At_seq]
    ; "section*",        []
    ; "subsection",      [At_sym; At_seq]
    ; "href",            [At_url; At_seq]
    ; "reddit",          [At_url]
    ; "hackernews",      [At_url]
    ; "lobsters",        [At_url]
    ; "documentclass",   [At_sym]
    ; "includegraphics", [At_seq]
    ; "date",            [At_sym]
    ; "details",         [At_seq; At_seq]
    ; "modified",        [At_sym]
    ; "keyword",         [At_sym]
    ; "title",           [At_seq]
    ; "subtitle",        [At_seq]
    ; "b",               [At_seq]
    ; "u",               [At_seq]
    ; "normal",          [At_seq]
    ; "emph",            [At_seq]
    ; "textsc",          [At_seq]
    ; "circled",         [At_num]
    ; "code",            [At_seq]
    ; "center",          [At_seq]
    ; "item",            []
    ; "math",            [At_seq]
    ; "sub",             [At_seq]
    ; "sup",             [At_seq]
    ; "fun",             [At_seq]
    ; "strikethrough",   [At_seq]
    ; "qed",             []
    ; "advice",          [At_sym; At_seq]
    ; "marginnote",      [At_sym; At_seq]
    ; "sidenote",        [At_sym; At_seq]
    ; "newline",         []
    ; "numspace",        []
    ; "hrule",           []
    ; "epigraph",        [At_seq; At_seq]
    ; "blockquote",      [At_seq; At_seq]
    ; "multicolumn",     [At_num; At_align_spec; At_seq]
    ; "term",            [At_seq; At_seq]
    ; "kbd",             [At_seq]
    ; "nameref",         [At_sym]
    (* Raw MathML support *)
    ; "mathml",          [At_seq]
    ; "mi",              [At_sym]
    ; "mn",              [At_seq]
    ; "mo",              [At_seq]
    ; "mo*",             [At_seq]
    ; "msup",            [At_seq; At_seq]
    ; "msub",            [At_seq; At_seq]
    ; "mtext",           [At_seq]
    ; "mrow",            [At_seq]
    ; "mtable",          [At_align_spec; At_seq]
    ; "mtr",             [At_seq]
    ; "mtd",             [At_seq]
    ; "munderover",      [At_seq; At_seq; At_seq]
    ; "msubsup",         [At_seq; At_seq; At_seq]
    ]

let math_cmds : math_arg_type list SMap.t =
  smap_of_list
    [ "frac",         [Math_arg_expr; Math_arg_expr]
    ; "binom",        [Math_arg_expr; Math_arg_expr]
    ; "operatorname", [Math_arg_sym]
    ; "left",         []
    ; "right",        []
    ]

let math_ops : SSet.t =
  sset_of_list
    [ "in"; "ni"; "notin"; "notni"
    ; "rightarrow"; "Rightarrow"; "leftarrow"; "Leftarrow"
    ; "sum"; "prod"; "log"; "oplus"
    ; "leq"; "iff"; "forall"; "exists"
    ]

(* Text replacement commands (command name → replacement text). We keep
   everything in Unicode so the elaborator stays representation-independent. *)
let replacements : string SMap.t =
  smap_of_list
    [ "ldots",      "\xE2\x80\xA6"      (* … U+2026 *)
    ; "cdots",      "\xE2\x8B\xAF"      (* ⋯ U+22EF *)
    ; "delta",      "\xCE\xB4"          (* δ U+03B4 *)
    ; "Delta",      "\xCE\x94"          (* Δ U+0394 *)
    ; "pi",         "\xCF\x80"          (* π U+03C0 *)
    ; "fracslash",  "\xE2\x88\x95"      (* ∕ U+2215 *)
    ; "prime",      "\xE2\x80\xB2"       (* ′ U+2032 *)
    ; "times",      "\xC3\x97"          (* × U+00D7 *)
    ; "itimes",     "\xE2\x81\xA2"       (* ⁢ U+2062 *)
    ; "applyFun",   "\xE2\x81\xA1"       (* ⁡ U+2061 *)
    ; "circ",       "\xE2\x88\x98"      (* ∘ U+2218 *)
    ; "in",         "\xE2\x88\x88"      (* ∈ U+2208 *)
    ; "ni",         "\xE2\x88\x8B"      (* ∋ U+220B *)
    ; "notin",      "\xE2\x88\x89"      (* ∉ U+2209 *)
    ; "inf",        "\xE2\x88\x9E"      (* ∞ U+221E *)
    ; "notni",      "\xE2\x88\x8C"      (* ∌ U+220C *)
    ; "rightarrow", "\xE2\x86\x92"      (* → U+2192 *)
    ; "Rightarrow", "\xE2\x87\x92"      (* ⇒ U+21D2 *)
    ; "leftarrow",  "\xE2\x86\x90"      (* ← U+2190 *)
    ; "Leftarrow",  "\xE2\x87\x90"      (* ⇐ U+21D0 *)
    ; "sum",        "\xE2\x88\x91"       (* ∑ U+2211 *)
    ; "oplus",      "\xE2\x8A\x95"       (* ⊕ U+2295 *)
    ; "prod",       "\xE2\x88\x8F"       (* ∏ U+220F *)
    ; "log",        "log"
    ; "int",        "\xE2\x88\xAB"       (* ∫ U+222B *)
    ; "lim",        "lim"
    ; "leq",        "\xE2\x89\xA4"      (* ≤ U+2264 *)
    ; "approx",     "\xE2\x89\x88"       (* ≈ U+2248 *)
    ; "iff",        "\xE2\x87\x94"      (* ⇔ U+21D4 *)
    ; "forall",     "\xE2\x88\x80"      (* ∀ U+2200 *)
    ; "exists",     "\xE2\x88\x83"      (* ∃ U+2203 *)
    ]

let env_names : SSet.t =
  sset_of_list
    [ "document"; "abstract"; "enumerate"; "itemize"
    ; "checklist"; "figure"; "tabular"; "tabular*"
    ; "description"; "verbatim"; "code"
    ]
