(* TeX parser tests. Minimal smoke coverage at this phase; the full suite
   from ParserTest.hs is translated later in Phase 9. *)

open Blogware
open Test_framework
open Syntax

(* --- Helpers --- *)

let parse input : (node list, Error.parse_error) result =
  Tex_parser.parse_document ~source_name:"<test>" input

(* Drop source positions from the AST so tests can compare values directly.
   We only care about structural equality at this level. *)
let rec strip_node (n : node) : node =
  let zero = Parser.Pos.make 0 in
  match n with
  | NText (_, s) -> NText (zero, s)
  | NCmd (_, name, opts, args) ->
      NCmd (zero, name, opts, List.map strip_arg args)
  | NEnv (_, _, name, opts, body) ->
      NEnv (zero, zero, name, opts, List.map strip_node body)
  | NGroup (_, body) -> NGroup (zero, List.map strip_node body)
  | NQuotation (_, body) -> NQuotation (zero, List.map strip_node body)
  | NTable (_, _, name, opts, spec, rows) ->
      NTable (zero, zero, name, opts, spec, rows)
  | NMath (_, disp, mnodes) -> NMath (zero, disp, mnodes)

and strip_arg = function
  | Arg_nodes (_, ns) -> Arg_nodes (Parser.Pos.make 0, List.map strip_node ns)
  | Arg_symbol (_, s) -> Arg_symbol (Parser.Pos.make 0, s)
  | Arg_number (_, n) -> Arg_number (Parser.Pos.make 0, n)
  | Arg_url (_, s) -> Arg_url (Parser.Pos.make 0, s)
  | Arg_align (_, sp) -> Arg_align (Parser.Pos.make 0, sp)

let zero = Parser.Pos.make 0

let parse_expect name input expected : Test_framework.t =
  test name (fun () ->
      match parse input with
      | Error e -> Fail ("parse error: " ^ e.pe_message)
      | Ok nodes ->
          let stripped = List.map strip_node nodes in
          if stripped = expected then Pass else Fail "AST mismatch")

let parse_fails name input : Test_framework.t =
  test name (fun () ->
      match parse input with
      | Error _ -> Pass
      | Ok _ -> Fail "expected parse error")

let parse_ok input =
  match parse input with Ok nodes -> Ok nodes | Error e -> Error e.pe_message

let scan_with p input =
  let open Parser in
  run (p <* eof) ~source_name:"<test>" input

(* --- Tests --- *)

let tests : Test_framework.t list =
  group "parser"
    [
      test "position resolve counts UTF-8 code points" (fun () ->
          let pos = Parser.Pos.make 3 in
          let resolved = Parser.Pos.resolve "aéx" pos in
          match assert_equal_int 1 resolved.line with
          | Fail _ as e -> e
          | Pass -> assert_equal_int 3 resolved.column);
      test "position resolve resets column after newline with UTF-8" (fun () ->
          let pos = Parser.Pos.make 5 in
          let resolved = Parser.Pos.resolve "é\nβx" pos in
          match assert_equal_int 2 resolved.line with
          | Fail _ as e -> e
          | Pass -> assert_equal_int 2 resolved.column);
      test "scan matches stateful token as one slice" (fun () ->
          let step state c =
            match (state, c) with
            | `start, '-' -> Some `minus
            | `minus, c when c >= '0' && c <= '9' -> Some `digits
            | `digits, c when c >= '0' && c <= '9' -> Some `digits
            | _ -> None
          in
          let accept = function `digits -> true | `start | `minus -> false in
          match scan_with (Parser.scan `start ~step ~accept) "-123" with
          | Ok s -> assert_equal_string "-123" s
          | Error e -> Fail ("scan error: " ^ e.pe_message));
      test "scan rejects non-accepting partial prefix" (fun () ->
          let step state c =
            match (state, c) with
            | `start, '-' -> Some `minus
            | `minus, c when c >= '0' && c <= '9' -> Some `digits
            | `digits, c when c >= '0' && c <= '9' -> Some `digits
            | _ -> None
          in
          let accept = function `digits -> true | `start | `minus -> false in
          match scan_with (Parser.scan `start ~step ~accept) "-" with
          | Error _ -> Pass
          | Ok s -> Fail ("expected scan failure, got " ^ s));
      test "table empty first cell keeps table-body position" (fun () ->
          let input = "\\begin{tabular}{c}\\\\\\end{tabular}" in
          match parse_ok input with
          | Error msg -> Fail ("parse error: " ^ msg)
          | Ok
              [
                NTable
                  (_, _, _, _, _, [ { row_cells = [ { cell_pos; _ } ]; _ } ]);
              ] ->
              assert_equal_int 18 cell_pos
          | Ok _ -> Fail "unexpected AST");
      test "table empty row after separator keeps row-start position" (fun () ->
          let input = "\\begin{tabular}{c}x\\\\\\\\\\end{tabular}" in
          match parse_ok input with
          | Error msg -> Fail ("parse error: " ^ msg)
          | Ok
              [
                NTable
                  (_, _, _, _, _, [ _; { row_cells = [ { cell_pos; _ } ]; _ } ]);
              ] ->
              assert_equal_int 21 cell_pos
          | Ok _ -> Fail "unexpected AST");
      parse_expect "empty input" "" [];
      parse_expect "plain text" "hello" [ NText (zero, "hello") ];
      parse_expect "bare command" "\\qed" [ NCmd (zero, "qed", [], []) ];
      parse_expect "command with symbol arg" "\\label{foo}"
        [ NCmd (zero, "label", [], [ Arg_symbol (zero, "foo") ]) ];
      parse_expect "escaped backslash" "\\\\" [ NText (zero, "\\") ];
      parse_expect "escaped percent" "\\%" [ NText (zero, "%") ];
      parse_expect "comment is skipped" "% a comment\nhello"
        [ NText (zero, "hello") ];
      parse_expect "group with nested text" "{abc}"
        [ NGroup (zero, [ NText (zero, "abc") ]) ];
      parse_fails "unmatched end" "\\end{foo}";
      test "align* basic" (fun () ->
          let input = "\\begin{align*}\na &= b \\\\\nc &= d\n\\end{align*}" in
          match parse_ok input with
          | Error msg -> Fail ("parse error: " ^ msg)
          | Ok [ NMath (_, Math_display, [ Math_align (specs, rows) ]) ] -> (
              match (specs, rows) with
              | ( [ Col_right; Col_left ],
                  [
                    [
                      [ Math_text "a" ]; [ Math_op ("=", false); Math_text "b" ];
                    ];
                    [
                      [ Math_text "c" ]; [ Math_op ("=", false); Math_text "d" ];
                    ];
                  ] ) ->
                  Pass
              | _ -> Fail "unexpected align structure")
          | Ok _ -> Fail "unexpected AST");
      test "align* default three-column alignment" (fun () ->
          let input = "\\begin{align*}\na & = & b\n\\end{align*}" in
          match parse_ok input with
          | Error msg -> Fail ("parse error: " ^ msg)
          | Ok [ NMath (_, Math_display, [ Math_align (specs, _) ]) ] ->
              assert_equal_string "r,c,l"
                (String.concat ","
                   (List.map
                      (function
                        | Col_right -> "r" | Col_center -> "c" | Col_left -> "l")
                      specs))
          | Ok _ -> Fail "unexpected AST");
      test "align* default four-column alignment" (fun () ->
          let input = "\\begin{align*}\na & = & b & c\n\\end{align*}" in
          match parse_ok input with
          | Error msg -> Fail ("parse error: " ^ msg)
          | Ok [ NMath (_, Math_display, [ Math_align (specs, _) ]) ] ->
              assert_equal_string "r,c,c,l"
                (String.concat ","
                   (List.map
                      (function
                        | Col_right -> "r" | Col_center -> "c" | Col_left -> "l")
                      specs))
          | Ok _ -> Fail "unexpected AST");
      test "align* trailing row separator" (fun () ->
          let input = "\\begin{align*}\na &= b \\\\\n\\end{align*}" in
          match parse_ok input with
          | Error msg -> Fail ("parse error: " ^ msg)
          | Ok [ NMath (_, Math_display, [ Math_align (_, rows) ]) ] ->
              assert_equal_int 1 (List.length rows)
          | Ok _ -> Fail "unexpected AST");
    ]
