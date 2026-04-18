(* Atom 1.0 feed renderer. Mirror of Blogware.Feed. *)

open Xml
open Document

let rfc3339 d = Date.to_rfc3339_midnight d

let latest_date (articles : article list) : Date.t =
  match articles with
  | [] -> failwith "no articles"
  | a :: rest ->
      List.fold_left
        (fun acc art ->
          if Date.compare art.art_modified_at acc > 0 then art.art_modified_at
          else acc)
        a.art_modified_at rest

let xml_concat xs = List.fold_left ( ++ ) empty xs

let render_entry (root_url : string) (a : article) : Xml.t =
  let url = root_url ^ a.art_url in
  let categories =
    xml_concat
      (List.map
         (fun kw -> tag_attr "category" ("term=\"" ^ kw ^ "\"") empty)
         a.art_keywords)
  in
  tag "entry"
    (tag "id" (text url)
    ++ tag "title" (text (Elaborate.render_inlines_to_text a.art_title))
    ++ tag "summary" (text (Elaborate.render_inlines_to_text a.art_subtitle))
    ++ tag "published" (text (rfc3339 a.art_created_at))
    ++ tag "updated" (text (rfc3339 a.art_modified_at))
    ++ tag_attr "link" ("rel=\"alternate\" href=\"" ^ url ^ "\"") empty
    ++ tag "author" (tag "name" (text "Roman Kashitsyn"))
    ++ categories)

let render_atom_feed (root_url : string) (articles : article list) : string =
  let entries = xml_concat (List.map (render_entry root_url) articles) in
  render
    (decl
    ++ tag_attr "feed" "xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"en\""
         (tag "title" (text "MMapped blog")
         ++ tag "id" (text (root_url ^ "/"))
         ++ tag "updated" (text (rfc3339 (latest_date articles)))
         ++ tag_attr "link"
              ("rel=\"self\" href=\"" ^ root_url ^ "/feed.xml\"")
              empty
         ++ tag "author" (tag "name" (text "Roman Kashitsyn"))
         ++ entries))
