(* Layout tests. Focused on TOC extraction and similarity ranking. *)

open Blogware
open Test_framework
open Document

let article_with slug keywords : article =
  { art_slug = slug
  ; art_title = [Str slug]
  ; art_subtitle = []
  ; art_created_at = Date.make ~year:2024 ~month:1 ~day:1
  ; art_modified_at = Date.make ~year:2024 ~month:1 ~day:1
  ; art_keywords = keywords
  ; art_body = []
  ; art_url = "/posts/" ^ slug ^ ".html"
  ; art_reddit = None; art_hn = None; art_lobsters = None
  }

let tests : Test_framework.t list =
  group "layout"
    [ test "extract_toc flat sections" (fun () ->
        let blocks = [
          Section (Some ("intro", [Str "Intro"]), []);
          Section (Some ("body", [Str "Body"]),
                   [Subsection ("sub1", [Str "Sub1"], [])]);
          Section (None, []);
        ] in
        let toc = Layout.extract_toc blocks in
        match toc with
        | [s1; s2] when
            s1.sec_entry.toc_id = "intro"
            && s1.sec_entry.toc_title = "Intro"
            && s1.sec_subsections = []
            && s2.sec_entry.toc_id = "body"
            && List.length s2.sec_subsections = 1 -> Pass
        | _ -> Fail "unexpected TOC")

    ; test "similar articles by keyword" (fun () ->
        let a = article_with "a" ["x"; "y"] in
        let b = article_with "b" ["x"; "y"; "z"] in  (* Jaccard 2/3 *)
        let c = article_with "c" ["q"] in            (* Jaccard 0 *)
        let d = article_with "d" ["x"] in            (* Jaccard 1/2 *)
        let articles = [a; b; c; d] in
        match Layout.find_similar_articles articles 0 with
        | [r1; r2] when r1.art_slug = "b" && r2.art_slug = "d" -> Pass
        | res -> Fail (Printf.sprintf "got %d results" (List.length res)))
    ]
