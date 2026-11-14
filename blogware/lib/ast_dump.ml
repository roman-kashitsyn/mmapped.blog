(* S-expression dump of the parser's output.

   The format is the contract of the differential test between this parser
   and the Rust one in crates/rftex-syntax (see its lower/dump module): both
   sides print the same bytes for the same input. Change them together.

   Layout rule: atoms follow the opening parenthesis on the same line, and
   every nested list starts a new line indented by two spaces. *)

open Syntax

type sexp = Atom of string | List of sexp list

let quote (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let atom s = Atom s
let str s = Atom (quote s)
let text t = str (Text.to_string t)
let int n = Atom (string_of_int n)
let pos (p : pos) = int (Parser.Pos.offset p)
let list head items = List (Atom head :: items)

let spec_string (spec : col_spec list) : string =
  String.concat ""
    (List.map
       (function Col_left -> "l" | Col_right -> "r" | Col_center -> "c")
       spec)

let border_name = function
  | Border_none -> "none"
  | Border_top -> "top"
  | Border_bottom -> "bottom"
  | Border_both -> "both"

let opts_sexp (opts : Text.t list) : sexp = list "opts" (List.map text opts)

let rec math_sexp : math_node -> sexp = function
  | Math_term (nucleus, sub, sup) ->
      let script = function None -> atom "_" | Some n -> math_sexp n in
      list "term" [ math_sexp nucleus; script sub; script sup ]
  | Math_frac (a, b) -> list "frac" [ math_sexp a; math_sexp b ]
  | Math_cmd (sym, args) ->
      list "mcmd" (atom (sym_to_string sym) :: List.map math_sexp args)
  | Math_op (t, stretchy) -> list (if stretchy then "sop" else "op") [ text t ]
  | Math_num t -> list "num" [ text t ]
  | Math_text t -> list "mtext" [ text t ]
  | Math_sym c -> list "msym" [ str (String.make 1 c) ]
  | Math_group nodes -> list "mgroup" (List.map math_sexp nodes)
  | Math_align (spec, rows) ->
      let cell nodes = list "cell" (List.map math_sexp nodes) in
      let row cells = list "row" (List.map cell cells) in
      list "align" (str (spec_string spec) :: List.map row rows)

let rec node_sexp : node -> sexp = function
  | NText (p, t) -> list "text" [ pos p; text t ]
  | NCmd (p, sym, opts, args) ->
      list "cmd"
        (pos p
        :: atom (sym_to_string sym)
        :: opts_sexp opts :: List.map arg_sexp args)
  | NEnv (b, e, sym, opts, body) ->
      list "env"
        (pos b :: pos e
        :: atom (sym_to_string sym)
        :: opts_sexp opts :: List.map node_sexp body)
  | NGroup (p, body) -> list "group" (pos p :: List.map node_sexp body)
  | NQuotation (p, body) -> list "quote" (pos p :: List.map node_sexp body)
  | NTable (b, e, sym, opts, spec, rows) ->
      list "table"
        (pos b :: pos e
        :: atom (sym_to_string sym)
        :: opts_sexp opts
        :: str (spec_string spec)
        :: List.map row_sexp rows)
  | NMath (p, display, nodes) ->
      let mode =
        match display with Math_inline -> "inline" | Math_display -> "display"
      in
      list "math" (pos p :: atom mode :: List.map math_sexp nodes)

and arg_sexp : arg -> sexp = function
  | Arg_nodes (p, nodes) -> list "nodes" (pos p :: List.map node_sexp nodes)
  | Arg_symbol (p, t) -> list "sym" [ pos p; text t ]
  | Arg_number (p, n) -> list "num" [ pos p; int n ]
  | Arg_url (p, t) -> list "url" [ pos p; text t ]
  | Arg_align (p, spec) -> list "align" [ pos p; str (spec_string spec) ]

and row_sexp (r : row) : sexp =
  list "row" (atom (border_name r.row_borders) :: List.map cell_sexp r.row_cells)

(* [cell_pos] is left out on purpose: it only feeds error messages and
   records an artifact of the row state machine, not a syntax position. *)
and cell_sexp (c : cell) : sexp =
  list "cell"
    (str (spec_string [ c.cell_align ])
    :: int c.cell_colspan
    :: List.map node_sexp c.cell_body)

let rec print_sexp (b : Buffer.t) (indent : int) : sexp -> unit = function
  | Atom s -> Buffer.add_string b s
  | List items ->
      Buffer.add_char b '(';
      List.iteri
        (fun i item ->
          begin match item with
          | Atom _ -> if i > 0 then Buffer.add_char b ' '
          | List _ ->
              Buffer.add_char b '\n';
              Buffer.add_string b (String.make (indent + 2) ' ')
          end;
          print_sexp b (indent + 2) item)
        items;
      Buffer.add_char b ')'

let dump_document (nodes : node list) : string =
  let b = Buffer.create 4096 in
  List.iter
    (fun n ->
      print_sexp b 0 (node_sexp n);
      Buffer.add_char b '\n')
    nodes;
  Buffer.contents b
