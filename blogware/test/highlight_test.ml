open Blogware
open Test_framework
open Document

let txt = Text.of_string

let tests : Test_framework.t list =
  group "highlight"
    [
      test "scanner movement" (fun () ->
          let sc = Highlight.scanner_of_string "abc" in
          match Highlight.peek sc with
          | Some 'a' ->
              ignore (Highlight.bump sc);
              Highlight.advance sc 2;
              assert_bool "scanner reaches EOF" (Highlight.is_eof sc)
          | _ -> Fail "expected first character");
      test "delimited string stops at newline" (fun () ->
          let sc = Highlight.scanner_of_string "\"abc\ndef" in
          let start, stop =
            Highlight.consume_delimited sc ~quote:'"' ~allow_newline:false
          in
          let consumed = Highlight.slice_string sc start stop in
          assert_equal_string "\"abc" consumed);
      test "block comment recovers at EOF" (fun () ->
          let sc = Highlight.scanner_of_string "/* open" in
          let start, stop = Highlight.consume_block_comment sc in
          let consumed = Highlight.slice_string sc start stop in
          assert_equal_string "/* open" consumed);
      test "spans convert to highlighted inlines" (fun () ->
          let sc = Highlight.scanner_of_string "func" in
          let spans = [ Highlight.span ~span_role:Hl_keyword sc 0 4 ] in
          match Highlight.spans_to_inlines spans with
          | [ Highlighted (Hl_keyword, [ Str t ]) ] ->
              assert_equal_string "func" (Text.to_string t)
          | _ -> Fail "expected highlighted keyword inline");
      test "highlighted spans are split at newlines" (fun () ->
          let spans =
            [
              { Highlight.span_role = Some Hl_comment; span_text = txt "a\nb" };
            ]
          in
          match Highlight.spans_to_inlines spans with
          | [
           Highlighted (Hl_comment, [ Str a ]);
           Str nl;
           Highlighted (Hl_comment, [ Str b ]);
          ]
            when Text.equal_string a "a" && Text.equal_string nl "\n"
                 && Text.equal_string b "b" ->
              Pass
          | _ -> Fail "expected newline outside highlight spans");
      test "empty spans are skipped" (fun () ->
          let spans = [ { Highlight.span_role = None; span_text = txt "" } ] in
          assert_equal_int 0 (List.length (Highlight.spans_to_inlines spans)));
    ]
