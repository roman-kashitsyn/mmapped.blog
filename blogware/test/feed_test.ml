(* Feed tests. *)

open Blogware
open Test_framework
open Document

let hello_article : article =
  {
    art_slug = "hello";
    art_title = [ Str "Hello" ];
    art_subtitle = [ Str "World" ];
    art_featured = false;
    art_created_at = Date.make ~year:2024 ~month:1 ~day:2;
    art_modified_at = Date.make ~year:2024 ~month:1 ~day:3;
    art_word_count = 2;
    art_keywords = [ "ocaml"; "port" ];
    art_body = [];
    art_url = "/posts/hello.html";
    art_reddit = None;
    art_hn = None;
    art_lobsters = None;
  }

let tests : Test_framework.t list =
  let xml = Feed.render_atom_feed "https://example.test" [ hello_article ] in
  group "feed"
    [
      test "atom feed starts with xml decl" (fun () ->
          assert_bool "starts with <?xml"
            (String.starts_with ~prefix:"<?xml" xml));
      test "atom feed includes title" (fun () ->
          assert_bool "title present"
            (Strings.is_infix_of "<title>Hello</title>" xml));
      test "atom feed dates formatted" (fun () ->
          assert_bool "published date present"
            (Strings.is_infix_of "<published>2024-01-02T00:00:00Z</published>"
               xml));
      test "atom feed id uses root url" (fun () ->
          assert_bool "feed id present"
            (Strings.is_infix_of "<id>https://example.test/</id>" xml));
    ]
