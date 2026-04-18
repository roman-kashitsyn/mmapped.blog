(* Elaborate tests. Covers typography and end-to-end small pipelines. *)

open Blogware
open Test_framework

let typo input expected : Test_framework.t =
  test ("typography/" ^ input) (fun () ->
      assert_equal_string expected (Elaborate.apply_typography input))

let elab_ok name input check_blocks : Test_framework.t =
  test name (fun () ->
      match Tex_parser.parse_document ~source_name:"<test>" input with
      | Error e -> Fail ("parse error: " ^ e.pe_message)
      | Ok nodes -> (
          match Elaborate.elaborate "slug" nodes with
          | Error e -> Fail ("elab error: " ^ e.Error.ee_message)
          | Ok art -> check_blocks art.art_body))

let elab_article_ok name input check_article : Test_framework.t =
  test name (fun () ->
      match Tex_parser.parse_document ~source_name:"<test>" input with
      | Error e -> Fail ("parse error: " ^ e.pe_message)
      | Ok nodes -> (
          match Elaborate.elaborate "slug" nodes with
          | Error e -> Fail ("elab error: " ^ e.Error.ee_message)
          | Ok art -> check_article art))

open Document

let tests : Test_framework.t list =
  group "elaborate"
    [
      typo "foo" "foo";
      typo "a---b" "a\xE2\x80\x94b";
      typo "a--b" "a\xE2\x80\x93b";
      typo "``hello''" "\xE2\x80\x9Chello\xE2\x80\x9D";
      typo "it's" "it\xE2\x80\x99s";
      typo "x-y" "x-y" (* single dash untouched *);
      elab_ok "single paragraph" "\\begin{document}hello\\end{document}"
        (fun blocks ->
          match blocks with
          | [ Para [ Str "hello" ] ] -> Pass
          | _ -> Fail "expected one para (flat preamble)");
      elab_ok "two paragraphs" "\\begin{document}one\n\ntwo\\end{document}"
        (fun blocks ->
          match blocks with
          | [ Para [ Str "one" ]; Para [ Str "two" ] ] -> Pass
          | _ -> Fail "expected two paragraphs (flat preamble)");
      elab_ok "section wrap"
        "\\begin{document}\\section{id}{Title}body\\end{document}"
        (fun blocks ->
          match blocks with
          | [ Section (Some ("id", [ Str "Title" ]), [ Para [ Str "body" ] ]) ]
            ->
              Pass
          | _ -> Fail "expected named section with body");
      elab_ok "anonymous preamble before section"
        "\\begin{document}pre\\section{id}{T}body\\end{document}" (fun blocks ->
          match blocks with
          | [
           Para [ Str "pre" ];
           Section (Some ("id", [ Str "T" ]), [ Para [ Str "body" ] ]);
          ] ->
              Pass
          | _ -> Fail "expected flat preamble + named section");
      elab_ok "strong inline" "\\begin{document}\\b{bold}\\end{document}"
        (fun blocks ->
          match blocks with
          | [ Para [ Strong [ Str "bold" ] ] ] -> Pass
          | _ -> Fail "expected strong inline");
      elab_ok "hrule block" "\\begin{document}\\hrule\\end{document}"
        (fun blocks ->
          match blocks with [ HRule ] -> Pass | _ -> Fail "expected hrule");
      elab_ok "itemize list"
        "\\begin{document}\\begin{itemize}\\item a\\item \
         b\\end{itemize}\\end{document}" (fun blocks ->
          match blocks with
          | [ Bullet_list (Arrows, items) ] when List.length items = 2 -> Pass
          | _ -> Fail "expected bullet list with 2 items");
      elab_article_ok "featured metadata"
        "\\featured\n\\begin{document}hello\\end{document}" (fun article ->
          assert_bool "marks article as featured" article.art_featured);
    ]
