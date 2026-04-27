(* Atom 1.0 feed renderer. *)

open Xml
open Document

let txt = Text.of_string

(* --- Atom tag helpers --- *)

(* Parent tags *)
let feed_ a c = parent "feed" a c
let entry_ a c = parent "entry" a c
let title_ a c = parent "title" a c
let summary_ a c = parent "summary" a c
let id_ a c = parent "id" a c
let published_ a c = parent "published" a c
let updated_ a c = parent "updated" a c
let author_ a c = parent "author" a c
let name_ a c = parent "name" a c

(* Leaf tags *)
let link_ a = leaf "link" a
let category_ a = leaf "category" a

(* Attribute helpers *)
let xmlns_ v = attr "xmlns" v
let xml_lang_ v = attr "xml:lang" v
let rel_ v = attr "rel" v
let href_ v = attr "href" v
let term_ v = attr "term" v

(* --- Feed rendering --- *)

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
  let url = Text.append (txt root_url) a.art_url in
  let categories =
    xml_concat (List.map (fun kw -> category_ [ term_ kw ]) a.art_keywords)
  in
  entry_ []
    (id_ [] (text url)
    ++ title_ [] (text (Elaborate.inlines_to_text a.art_title))
    ++ summary_ [] (text (Elaborate.inlines_to_text a.art_subtitle))
    ++ published_ [] (text (txt (rfc3339 a.art_created_at)))
    ++ updated_ [] (text (txt (rfc3339 a.art_modified_at)))
    ++ link_ [ rel_ (txt "alternate"); href_ url ]
    ++ author_ [] (name_ [] (text (txt "Roman Kashitsyn")))
    ++ categories)

let render_atom_feed (root_url : string) (articles : article list) : string =
  let entries = xml_concat (List.map (render_entry root_url) articles) in
  render
    (decl
    ++ feed_
         [ xmlns_ (txt "http://www.w3.org/2005/Atom"); xml_lang_ (txt "en") ]
         (title_ [] (text (txt "MMapped blog"))
         ++ id_ [] (text (txt (root_url ^ "/")))
         ++ updated_ [] (text (txt (rfc3339 (latest_date articles))))
         ++ link_ [ rel_ (txt "self"); href_ (txt (root_url ^ "/feed.xml")) ]
         ++ author_ [] (name_ [] (text (txt "Roman Kashitsyn")))
         ++ entries))
