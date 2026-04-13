(* Feed tests. *)

open Blogware
open Test_framework
open Document

let make_article () : article =
  { art_slug = "hello"
  ; art_title = [Str "Hello"]
  ; art_subtitle = [Str "World"]
  ; art_created_at = Date.make ~year:2024 ~month:1 ~day:2
  ; art_modified_at = Date.make ~year:2024 ~month:1 ~day:3
  ; art_keywords = ["ocaml"; "port"]
  ; art_body = []
  ; art_url = "/posts/hello.html"
  ; art_reddit = None
  ; art_hn = None
  ; art_lobsters = None
  }

let contains haystack needle =
  let hn = String.length haystack and nn = String.length needle in
  let rec find i =
    if i + nn > hn then false
    else if String.sub haystack i nn = needle then true
    else find (i + 1)
  in
  find 0

let tests : Test_framework.t list =
  group "feed"
    [ test "atom feed starts with xml decl" (fun () ->
        let a = make_article () in
        let xml = Feed.render_atom_feed "https://example.test" [a] in
        assert_bool "starts with <?xml"
          (String.length xml >= 5 && String.sub xml 0 5 = "<?xml"))

    ; test "atom feed includes title" (fun () ->
        let xml = Feed.render_atom_feed "https://example.test" [make_article ()] in
        assert_bool "title present" (contains xml "<title>Hello</title>"))

    ; test "atom feed dates formatted" (fun () ->
        let xml = Feed.render_atom_feed "https://example.test" [make_article ()] in
        assert_bool "published date present"
          (contains xml "<published>2024-01-02T00:00:00Z</published>"))

    ; test "atom feed id uses root url" (fun () ->
        let xml = Feed.render_atom_feed "https://example.test" [make_article ()] in
        assert_bool "feed id present"
          (contains xml "<id>https://example.test/</id>"))
    ]
