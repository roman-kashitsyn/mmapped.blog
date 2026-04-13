(* Parser tests. Minimal smoke coverage at this phase; the full suite
   from ParserTest.hs is translated later in Phase 9. *)

open Blogware
open Test_framework
open Syntax

(* --- Helpers --- *)

let parse input : (node list, Error.parse_error) result =
  Parser.parse_document ~source_name:"<test>" input

(* Drop source positions from the AST so tests can compare values directly.
   We only care about structural equality at this level. *)
let rec strip_node (n : node) : node =
  let zero = Parser_pos.make "" 0 0 in
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
  | Arg_nodes (_, ns) -> Arg_nodes (Parser_pos.make "" 0 0, List.map strip_node ns)
  | Arg_symbol (_, s) -> Arg_symbol (Parser_pos.make "" 0 0, s)
  | Arg_number (_, n) -> Arg_number (Parser_pos.make "" 0 0, n)
  | Arg_url (_, s) -> Arg_url (Parser_pos.make "" 0 0, s)
  | Arg_align (_, sp) -> Arg_align (Parser_pos.make "" 0 0, sp)

let zero = Parser_pos.make "" 0 0

let parse_expect name input expected : Test_framework.t =
  test name (fun () ->
    match parse input with
    | Error e -> Fail ("parse error: " ^ e.pe_message)
    | Ok nodes ->
      let stripped = List.map strip_node nodes in
      if stripped = expected then Pass
      else Fail "AST mismatch")

let parse_fails name input : Test_framework.t =
  test name (fun () ->
    match parse input with
    | Error _ -> Pass
    | Ok _ -> Fail "expected parse error")

(* --- Tests --- *)

let tests : Test_framework.t list =
  group "parser"
    [ parse_expect "empty input" "" []

    ; parse_expect "plain text"
        "hello"
        [NText (zero, "hello")]

    ; parse_expect "bare command"
        "\\qed"
        [NCmd (zero, "qed", [], [])]

    ; parse_expect "command with symbol arg"
        "\\label{foo}"
        [NCmd (zero, "label", [], [Arg_symbol (zero, "foo")])]

    ; parse_expect "escaped backslash"
        "\\\\"
        [NText (zero, "\\")]

    ; parse_expect "escaped percent"
        "\\%"
        [NText (zero, "%")]

    ; parse_expect "comment is skipped"
        "% a comment\nhello"
        [NText (zero, "hello")]

    ; parse_expect "group with nested text"
        "{abc}"
        [NGroup (zero, [NText (zero, "abc")])]

    ; parse_fails "unmatched end"
        "\\end{foo}"
    ]
