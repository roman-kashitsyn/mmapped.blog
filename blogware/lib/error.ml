(* Error types and pretty formatter with source-context underlines.
   Mirror of Blogware.Error. The Haskell version uses Parsec's ParseError;
   the OCaml port has its own [Parser.parse_error] type that carries
   a source position and message. *)

(* The parser-side error type lives in Parser to avoid a cycle;
   this module only formats it. *)

type parse_error = Parser.parse_error = {
  pe_source_name : string;
  pe_pos : Parser.Pos.t;
  pe_message : string;
}

type elab_error = { ee_pos : Parser.Pos.t option; ee_message : string }

let make_elab ?pos message = { ee_pos = pos; ee_message = message }

(* --- formatting --- *)

let is_delimiter c = c = '{' || c = '}' || c = ' ' || c = '\t'

(* Extract a 1-indexed source line, or "" if out of range. *)
let get_source_line source n =
  let lines = String.split_on_char '\n' source in
  let len = List.length lines in
  if n >= 1 && n <= len then List.nth lines (n - 1) else ""

let utf8_byte_index_of_column s col =
  let len = String.length s in
  let i = ref 0 in
  let current_col = ref 1 in
  while !i < len && !current_col < col do
    let decoded = String.get_utf_8_uchar s !i in
    let step = Uchar.utf_decode_length decoded in
    i := !i + step;
    incr current_col
  done;
  min !i len

(* Compute underline span: number of non-delimiter characters from [col]. *)
let compute_span line col =
  let len = String.length line in
  let i = ref (utf8_byte_index_of_column line col) in
  let count = ref 0 in
  while !i < len && not (is_delimiter line.[!i]) do
    incr count;
    let decoded = String.get_utf_8_uchar line !i in
    let step = Uchar.utf_decode_length decoded in
    i := !i + step
  done;
  max 1 !count

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
  String.concat "\n" [ header; ""; prefix ^ src_line; carets; msg; "" ]

let format_parse_error source (e : parse_error) =
  let p = Parser.Pos.resolve source e.pe_pos in
  format_report "PARSE ERROR" source e.pe_source_name p.line p.column
    e.pe_message

let format_elab_error ~source_name source (e : elab_error) =
  match e.ee_pos with
  | None -> e.ee_message
  | Some p ->
      let p = Parser.Pos.resolve source p in
      format_report "ELABORATION ERROR" source source_name p.line p.column
        e.ee_message
