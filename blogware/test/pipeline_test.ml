(* Pipeline tests — exercise the parser + elaborator + error formatter
   together. Focused on the display of parse and elaboration errors, so
   that regressions in error rendering (source snippet, caret underline,
   header layout) are caught. *)

open Blogware
open Test_framework

let parse src = Tex_parser.parse_document ~source_name:"<test>" src

let elaborate_src src =
  match parse src with
  | Error _ -> assert false
  | Ok nodes -> Elaborate.elaborate "test" nodes

let assert_parse_error_msg src expected : check =
  match parse src with
  | Ok _ -> Fail "expected parse error, got Ok"
  | Error err -> assert_equal_string expected (Error.format_parse_error src err)

let assert_elab_error_msg src expected : check =
  match elaborate_src src with
  | Ok _ -> Fail "expected elab error, got Ok"
  | Error err ->
      assert_equal_string expected
        (Error.format_elab_error ~source_name:"<test>" src err)

let tests : Test_framework.t list =
  group "pipeline"
    [
      test "parse error: mismatched env" (fun () ->
          assert_parse_error_msg
            "\\begin{document}\n\
             \\begin{itemize}\n\
             \\end{enumerate}\n\
             \\end{document}\n"
            (String.concat "\n"
               [
                 "-- PARSE ERROR -------------------------------------- <test>";
                 "";
                 " 3 | \\end{enumerate}";
                 "          ^^^^^^^^^";
                 "expected \\end{itemize} but found \\end{enumerate}";
                 "";
               ]));
      test "parse error: unbalanced end" (fun () ->
          assert_parse_error_msg "Hello \\end{document}\n"
            (String.concat "\n"
               [
                 "-- PARSE ERROR -------------------------------------- <test>";
                 "";
                 " 1 | Hello \\end{document}";
                 "               ^";
                 "unexpected \\end without matching \\begin";
                 "";
               ]));
      test "parse error: UTF-8 prefix keeps caret alignment" (fun () ->
          assert_parse_error_msg "é \\end{document}\n"
            (String.concat "\n"
               [
                 "-- PARSE ERROR -------------------------------------- <test>";
                 "";
                 " 1 | é \\end{document}";
                 "           ^";
                 "unexpected \\end without matching \\begin";
                 "";
               ]));
      test "parse error: invalid multicolumn keeps source position" (fun () ->
          assert_parse_error_msg
            "\\begin{tabular}{c}\n\
             \\multicolumn{2}{lr}{x}\n\
             \\end{tabular}\n"
            (String.concat "\n"
               [
                 "-- PARSE ERROR -------------------------------------- <test>";
                 "";
                 " 2 | \\multicolumn{2}{lr}{x}";
                 "     ^^^^^^^^^^^^";
                 "\\multicolumn requires {N}{alignment}{content}";
                 "";
               ]));
      test "elab error: unknown command" (fun () ->
          assert_elab_error_msg
            "\\documentclass{article}\n\
             \\title{T}\n\
             \\date{2025-01-01}\n\
             \\begin{document}\n\
             Hello \\foobar{x}\n\
             \\end{document}\n"
            (String.concat "\n"
               [
                 "-- ELABORATION ERROR -------------------------------- <test>";
                 "";
                 " 5 | Hello \\foobar{x}";
                 "           ^^^^^^^";
                 "unknown command: \\foobar";
                 "";
               ]));
      test "elab error: unknown environment" (fun () ->
          assert_elab_error_msg
            "\\documentclass{article}\n\
             \\title{T}\n\
             \\date{2025-01-01}\n\
             \\begin{document}\n\
             \\begin{fancybox}\n\
             text\n\
             \\end{fancybox}\n\
             \\end{document}\n"
            (String.concat "\n"
               [
                 "-- ELABORATION ERROR -------------------------------- <test>";
                 "";
                 " 5 | \\begin{fancybox}";
                 "     ^^^^^^";
                 "unknown environment: fancybox";
                 "";
               ]));
      test "elab error: invalid date" (fun () ->
          assert_elab_error_msg
            "\\documentclass{article}\n\
             \\title{T}\n\
             \\date{not-a-date}\n\
             \\begin{document}\n\
             Hello\n\
             \\end{document}\n"
            (String.concat "\n"
               [
                 "-- ELABORATION ERROR -------------------------------- <test>";
                 "";
                 " 3 | \\date{not-a-date}";
                 "           ^^^^^^^^^^";
                 "invalid date: not-a-date (expected YYYY-MM-DD)";
                 "";
               ]));
    ]
