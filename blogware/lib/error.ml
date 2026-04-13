(* Error types and pretty formatter with source-context underlines.
   Mirror of Blogware.Error. The Haskell version uses Parsec's ParseError;
   the OCaml port has its own [Parser_state.parse_error] type that carries
   a source position and message. *)

(* The parser-side error type lives in Parser_state to avoid a cycle;
   we re-export the formatting helpers here against an abstract record. *)

type parse_error = {
  pe_pos : Parser_pos.t;
  pe_message : string;
}

type elab_error = {
  ee_pos : Parser_pos.t option;
  ee_message : string;
}

let make_elab ?pos message = { ee_pos = pos; ee_message = message }

(* --- formatting --- *)

let is_delimiter c =
  c = '{' || c = '}' || c = ' ' || c = '\t'

(* Extract a 1-indexed source line, or "" if out of range. *)
let get_source_line source n =
  let lines = String.split_on_char '\n' source in
  let len = List.length lines in
  if n >= 1 && n <= len then List.nth lines (n - 1) else ""

(* Compute underline span: number of non-delimiter characters from [col]. *)
let compute_span line col =
  let drop = if col - 1 >= String.length line then "" else String.sub line (col - 1) (String.length line - col + 1) in
  let rec count i =
    if i >= String.length drop then i
    else if is_delimiter drop.[i] then i
    else count (i + 1)
  in
  max 1 (count 0)

(* Header line: "-- CATEGORY ---- filename" padded to 60 cols. *)
let format_header category file_name =
  let start = "-- " ^ category ^ " " in
  let end_ = " " ^ file_name in
  let width = 60 in
  let dash_count = max 4 (width - String.length start - String.length end_) in
  start ^ String.make dash_count '-' ^ end_

let format_report category source file_name line_num col msg =
  let src_line = get_source_line source line_num in
  let span_len = compute_span src_line col in
  let line_str = string_of_int line_num in
  let pad = String.make (max 0 (2 - String.length line_str)) ' ' in
  let prefix = pad ^ line_str ^ " | " in
  let prefix_len = String.length prefix in
  let carets =
    String.make (prefix_len + col - 1) ' ' ^ String.make span_len '^'
  in
  let header = format_header category file_name in
  String.concat "\n" [header; ""; prefix ^ src_line; carets; msg; ""]

let format_parse_error source (e : parse_error) =
  let p = e.pe_pos in
  format_report "PARSE ERROR" source
    (Parser_pos.source_name p) (Parser_pos.line p) (Parser_pos.column p)
    e.pe_message

let format_elab_error source (e : elab_error) =
  match e.ee_pos with
  | None -> e.ee_message
  | Some p ->
    format_report "ELABORATION ERROR" source
      (Parser_pos.source_name p) (Parser_pos.line p) (Parser_pos.column p)
      e.ee_message
