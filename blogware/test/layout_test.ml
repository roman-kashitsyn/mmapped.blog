(* Layout tests. Focused on TOC extraction and similarity ranking. *)

open Blogware
open Test_framework
open Document

let txt = Text.of_string

let article_with slug keywords : article =
  let slug_t = txt slug in
  {
    art_slug = slug_t;
    art_title = [ Str slug_t ];
    art_subtitle = [ Str (txt "subtitle") ];
    art_featured = false;
    art_created_at = Date.make ~year:2024 ~month:1 ~day:1;
    art_modified_at = Date.make ~year:2024 ~month:1 ~day:1;
    art_word_count = 42;
    art_keywords = List.map txt keywords;
    art_body = [];
    art_url = txt ("/posts/" ^ slug ^ ".html");
    art_reddit = None;
    art_hn = None;
    art_lobsters = None;
  }

let all checks =
  let rec go = function
    | [] -> Pass
    | Pass :: rest -> go rest
    | (Fail _ as failed) :: _ -> failed
  in
  go checks

let tests : Test_framework.t list =
  group "layout"
    [
      test "page head includes blog posting json-ld" (fun () ->
          let article = article_with "hello" [ "ocaml"; "testing" ] in
          let head =
            Html.render (Layout.page_head "https://example.test" article)
          in
          all
            [
              assert_bool "has ld+json script"
                (Strings.is_infix_of "<script type=\"application/ld+json\">"
                   head);
              assert_bool "has schema.org context"
                (Strings.is_infix_of "\"@context\":\"https://schema.org\"" head);
              assert_bool "has blog posting type"
                (Strings.is_infix_of "\"@type\":\"BlogPosting\"" head);
              assert_bool "has canonical url"
                (Strings.is_infix_of
                   "\"url\":\"https://example.test/posts/hello.html\"" head);
              assert_bool "has mainEntityOfPage"
                (Strings.is_infix_of
                   "\"mainEntityOfPage\":{\"@type\":\"WebPage\",\"@id\":\"https://example.test/posts/hello.html\"}"
                   head);
              assert_bool "has dates"
                (Strings.is_infix_of "\"datePublished\":\"2024-01-01\"" head
                && Strings.is_infix_of "\"dateModified\":\"2024-01-01\"" head);
              assert_bool "has word count"
                (Strings.is_infix_of "\"wordCount\":42" head);
              assert_bool "has author"
                (Strings.is_infix_of
                   {|"author":{"@type":"Person","givenName":"Roman","familyName":"Kashitsyn"}|}
                   head);
              assert_bool "has keywords array"
                (Strings.is_infix_of {|"keywords":["ocaml","testing"]|} head);
            ]);
      test "post attributes render semantic time elements" (fun () ->
          let article = article_with "hello" [ "ocaml" ] in
          let attrs = Html.render (Layout.render_post_attributes article) in
          all
            [
              assert_bool "uses time for published date"
                (Strings.is_infix_of
                   {|<time datetime="2024-01-01">2024-01-01</time>|} attrs);
              assert_bool "uses time for modified date"
                (Strings.is_infix_of
                   {|<time datetime="2024-01-01">2024-01-01</time>|} attrs);
            ]);
      test "featured post entries render a marker" (fun () ->
          let article =
            { (article_with "hello" [ "ocaml" ]) with art_featured = true }
          in
          let entry = Html.render (Layout.render_post_entry article) in
          all
            [
              assert_bool "marks list item as featured"
                (Strings.is_infix_of {|<li class="featured">|} entry);
              assert_bool "marks title as left gutter anchor"
                (Strings.is_infix_of
                   {|<h2 class="article-title left-gutter-anchor featured-marker">|}
                   entry);
            ]);
      test "json-ld escapes script-breaking text" (fun () ->
          let article =
            {
              (article_with "quotes" []) with
              art_title = [ Str (Text.of_string "A \"quoted\" <title>") ];
              art_subtitle = [ Str (Text.of_string "Fish & Chips") ];
            }
          in
          let head =
            Html.render (Layout.page_head "https://example.test" article)
          in
          all
            [
              assert_bool "escapes quotes"
                (Strings.is_infix_of
                   "\"headline\":\"A \\\"quoted\\\" \\u003ctitle\\u003e\"" head);
              assert_bool "escapes ampersand"
                (Strings.is_infix_of "\"description\":\"Fish \\u0026 Chips\""
                   head);
              assert_bool "does not emit empty keywords"
                (not (Strings.is_infix_of "\"keywords\":" head));
            ]);
      test "extract_toc flat sections" (fun () ->
          let blocks =
            [
              Section (Some (txt "intro", [ Str (txt "Intro") ]), []);
              Section
                ( Some (txt "body", [ Str (txt "Body") ]),
                  [ Subsection (txt "sub1", [ Str (txt "Sub1") ], []) ] );
              Section (None, []);
            ]
          in
          let toc = Layout.extract_toc blocks in
          match toc with
          | [ s1; s2 ]
            when Text.equal_string s1.sec_entry.toc_id "intro"
                 && Text.equal_string s1.sec_entry.toc_title "Intro"
                 && s1.sec_subsections = []
                 && Text.equal_string s2.sec_entry.toc_id "body"
                 && List.length s2.sec_subsections = 1 ->
              Pass
          | _ -> Fail "unexpected TOC");
      test "similar articles by keyword" (fun () ->
          let a = article_with "a" [ "x"; "y" ] in
          let b = article_with "b" [ "x"; "y"; "z" ] in
          (* Jaccard 2/3 *)
          let c = article_with "c" [ "q" ] in
          (* Jaccard 0 *)
          let d = article_with "d" [ "x" ] in
          (* Jaccard 1/2 *)
          let articles = [ a; b; c; d ] in
          match Layout.find_similar_articles articles 0 with
          | [ r1; r2 ]
            when Text.equal_string r1.art_slug "b"
                 && Text.equal_string r2.art_slug "d" ->
              Pass
          | res -> Fail (Printf.sprintf "got %d results" (List.length res)));
    ]
