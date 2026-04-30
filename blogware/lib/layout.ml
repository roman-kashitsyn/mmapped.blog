(* Page templates. *)

open Html
open Document

let txt = Text.of_string
let ( ^^ ) = Text.append

(* --- Table of contents --- *)

type toc_entry = { toc_id : Text.t; toc_title : Text.t }
type toc_section = { sec_entry : toc_entry; sec_subsections : toc_entry list }

let extract_toc (blocks : block list) : toc_section list =
  List.filter_map
    (function
      | Section (Some (anchor, title), body) ->
          let entry =
            {
              toc_id = anchor;
              toc_title =
                txt (Html.render (Render.render_inlines Render.empty_ctx title));
            }
          in
          let subs =
            List.filter_map
              (function
                | Subsection (a, t, _) ->
                    Some
                      {
                        toc_id = a;
                        toc_title =
                          txt
                            (Html.render
                               (Render.render_inlines Render.empty_ctx t));
                      }
                | _ -> None)
              body
          in
          Some { sec_entry = entry; sec_subsections = subs }
      | _ -> None)
    blocks

let add_article_refs (tbl : ref_table) (all_articles : article list) : ref_table =
  List.fold_left
    (fun acc a ->
      RefTable.add a.art_slug
        {
          ref_title =
            txt
              (Html.render
                 (Render.render_inlines Render.empty_ctx a.art_title));
          ref_url = a.art_url;
        }
        acc)
    tbl all_articles

let add_note_refs (tbl : ref_table) (all_notes : note list) : ref_table =
  List.fold_left
    (fun acc (n : note) ->
      RefTable.add n.note_slug
        {
          ref_title =
            txt
              (Html.render
                 (Render.render_inlines Render.empty_ctx n.note_title));
          ref_url = n.note_url;
        }
        acc)
    tbl all_notes

let add_toc_refs (tbl : ref_table) (toc : toc_section list) : ref_table =
  List.fold_left
    (fun acc section ->
      let acc =
        RefTable.add section.sec_entry.toc_id
          {
            ref_title = section.sec_entry.toc_title;
            ref_url = txt "#" ^^ section.sec_entry.toc_id;
          }
          acc
      in
      List.fold_left
        (fun acc sub ->
          RefTable.add sub.toc_id
            { ref_title = sub.toc_title; ref_url = txt "#" ^^ sub.toc_id }
            acc)
        acc section.sec_subsections)
    tbl toc

let build_ref_table (all_articles : article list) (all_notes : note list)
    (article : article) : ref_table =
  let toc = extract_toc article.art_body in
  let tbl = add_article_refs RefTable.empty all_articles in
  let tbl = add_note_refs tbl all_notes in
  add_toc_refs tbl toc

(* Build a ref_table that spans both articles and notes, plus local TOC. *)
let build_note_ref_table (all_articles : article list) (all_notes : note list)
    (note : note) : ref_table =
  let tbl = add_article_refs RefTable.empty all_articles in
  let tbl = add_note_refs tbl all_notes in
  let toc = extract_toc note.note_body in
  add_toc_refs tbl toc

let build_global_ref_table (all_articles : article list) (all_notes : note list)
    : ref_table =
  let tbl = add_article_refs RefTable.empty all_articles in
  add_note_refs tbl all_notes

(* --- Similar articles (Jaccard keyword similarity with tiebreaker) --- *)

let find_similar_articles (articles : article list) (idx : int) : article list =
  let arr = Array.of_list articles in
  let n = Array.length arr in
  let target = arr.(idx) in
  let target_kws = Text.Set.of_list target.art_keywords in
  let target_kw_count = Text.Set.cardinal target_kws in
  let candidates = ref [] in
  for i = 0 to n - 1 do
    if i <> idx then begin
      let a = arr.(i) in
      let common =
        List.length
          (List.filter (fun k -> Text.Set.mem k target_kws) a.art_keywords)
      in
      let total = List.length a.art_keywords + target_kw_count - common in
      if total > 0 then begin
        let sim =
          (float_of_int common /. float_of_int total)
          -. (0.00001 *. float_of_int (abs (i - idx)))
        in
        if sim >= 0.4 then candidates := (sim, a) :: !candidates
      end
    end
  done;
  let sorted =
    let arr = Array.of_list !candidates in
    Array.sort (fun (a, _) (b, _) -> compare b a) arr;
    Array.to_list arr
  in
  let rec take n = function
    | [] -> []
    | _ when n <= 0 -> []
    | (_, a) :: rest -> a :: take (n - 1) rest
  in
  take 5 sorted

(* --- Structured data --- *)

let post_json_ld (type s) (module B : Json.Builder with type t = s)
    (root_url : string) (article : article) : s =
  let url = txt root_url ^^ article.art_url in
  let author =
    B.obj
      [|
        ("@type", B.str (txt "Person"));
        ("givenName", B.str (txt "Roman"));
        ("familyName", B.str (txt "Kashitsyn"));
      |]
  in
  let fields =
    Dynarray.of_array
      [|
        ("@context", B.str (txt "https://schema.org"));
        ("@type", B.str (txt "BlogPosting"));
        ("headline", B.str (Elaborate.inlines_to_text article.art_title));
        ("url", B.str url);
        ( "mainEntityOfPage",
          B.obj [| ("@type", B.str (txt "WebPage")); ("@id", B.str url) |] );
        ("datePublished", B.str (txt (Date.to_string article.art_created_at)));
        ("dateModified", B.str (txt (Date.to_string article.art_modified_at)));
        ("wordCount", B.num article.art_word_count);
        ("license", B.str (txt "http://creativecommons.org/licenses/by/4.0/"));
        ("author", author);
        ("publisher", author);
      |]
  in
  if not (List.is_empty article.art_subtitle) then
    Dynarray.add_last fields
      ("description", B.str (Elaborate.inlines_to_text article.art_subtitle));
  if not (List.is_empty article.art_keywords) then
    Dynarray.add_last fields
      ( "keywords",
        article.art_keywords |> List.map B.str |> Array.of_list |> B.arr );
  B.obj (Dynarray.to_array fields)

let render_json_ld (root_url : string) (article : article) : Html.t =
  parent "script"
    [ type_ (txt "application/ld+json") ]
    (nl ++ post_json_ld (module Json.Render) root_url article ++ nl)

(* --- Page head --- *)

let page_head (root_url : string) (article : article) : Html.t =
  let description_meta =
    if article.art_subtitle = [] then empty
    else
      leaf "meta"
        [
          name_ (txt "description");
          content_
            (txt
               (Html.render
                  (Render.render_inlines Render.empty_ctx article.art_subtitle)));
        ]
  in
  head_ []
    (leaf "meta" [ charset_ (txt "UTF-8") ]
    ++ leaf "meta"
         [
           content_ (txt "width=device-width, initial-scale=1");
           name_ (txt "viewport");
         ]
    ++ leaf "meta" [ name_ (txt "author"); content_ (txt "Roman Kashitsyn") ]
    ++ leaf "meta"
         [
           name_ (txt "keywords");
           content_ (Text.concat (txt ",") article.art_keywords);
         ]
    ++ description_meta
    ++ title_ [] (Render.render_inlines Render.empty_ctx article.art_title)
    ++ link_ [ rel_ (txt "stylesheet"); href_ (txt "/css/mmapped.css") ]
    ++ link_ [ rel_ (txt "icon"); href_ (txt "/images/favicon.svg") ]
    ++ link_
         [
           rel_ (txt "mask-icon");
           href_ (txt "/images/mask-icon.svg");
           attr "color" (txt "#000000");
         ]
    ++ link_
         [
           rel_ (txt "alternate");
           type_ (txt "application/atom+xml");
           href_ (txt "/feed.xml");
         ]
    ++ link_ [ rel_ (txt "canonical"); href_ (txt root_url ^^ article.art_url) ]
    ++ render_json_ld root_url article)

(* --- Site header / footer --- *)

let logo_img =
  img_
    [
      class_ (txt "logo grayscale");
      src_ (txt "/images/logo.svg");
      alt_ (txt "logo: circled capital letter M");
    ]

let site_header : Html.t =
  header_ []
    (nav_ []
       (ul_ []
          (li_ []
             (a_
                [ class_ (txt "blog-title"); href_ (txt "/index.html") ]
                (logo_img ++ text (txt "mmap(blog)")))
          ++ li_ []
               (a_ [ href_ (txt "/posts.html") ] (escape_html (txt "Posts")))
          ++ li_ []
               (a_
                  [ href_ (txt "/notes/index.html") ]
                  (escape_html (txt "Notes")))
          ++ li_ []
               (a_ [ href_ (txt "/feed.xml") ] (escape_html (txt "Feed")))
          )))
  ++ hr_ []

let site_footer : Html.t =
  nl ++ hr_ []
  ++ footer_
       [ role_ (txt "contentinfo") ]
       (span_ [] (text (txt "©Roman Kashitsyn"))
       ++ nbsp
       ++ a_
            [
              rel_ (txt "license");
              href_ (txt "http://creativecommons.org/licenses/by/4.0/");
              attr "title"
                (txt
                   "This work is licensed under a Creative Commons Attribution \
                    4.0 International License");
            ]
            (leaf "img"
               [
                 alt_ (txt "Creative Commons License");
                 attr "style"
                   (txt
                      "border-width:0;width:80px;height:15px;text-decoration:none;");
                 src_ (txt "https://i.creativecommons.org/l/by/4.0/80x15.png");
               ])
       ++ br_ [] ++ nl
       ++ a_
            [
              class_ (txt "github-link");
              href_ (txt "https://github.com/roman-kashitsyn/mmapped.blog");
            ]
            (text (txt "Source Code"))
       ++ text (txt " · ")
       ++ a_
            [
              href_
                (txt
                   "https://github.com/roman-kashitsyn/mmapped.blog/issues/new");
            ]
            (text (txt "Report Issue")))

(* --- Post attributes (dates and social links) --- *)

let render_date (d : Date.t) : Html.t =
  let s = txt (Date.to_string d) in
  time_ [ datetime_ s ] (escape_html s)

let render_social_link link icon title_text alt_text extra_class : Html.t =
  match link with
  | None -> empty
  | Some url ->
      a_
        [
          class_ (txt "icon-link");
          href_ url;
          attr "title" (txt title_text);
          rel_ (txt "nofollow noopener noreferrer");
          attr "target" (txt "_blank");
        ]
        (leaf "img"
           [
             class_
               (txt
                  ("social-icon"
                  ^ if extra_class = "" then "" else " " ^ extra_class));
             src_ (txt icon);
             alt_ (txt alt_text);
           ])

let render_keyword_link (kw : Text.t) : Html.t =
  a_
    [ class_ (txt "keyword-link"); href_ (txt "/notes/" ^^ kw ^^ txt ".html") ]
    (escape_html kw)

let render_keywords (keywords : Text.t list) : Html.t =
  if keywords = [] then empty
  else
    span_
      [ class_ (txt "post-keywords") ]
      (concat (List.map render_keyword_link keywords))

let render_post_attributes (article : article) : Html.t =
  span_
    [ class_ (txt "post-attrs") ]
    (span_
       [ class_ (txt "attr-date"); attr "title" (txt "First published") ]
       (span_ [ class_ (txt "icon") ] (text (txt "✑"))
       ++ render_date article.art_created_at)
    ++ (if Date.equal article.art_modified_at article.art_created_at then empty
        else
          span_
            [ class_ (txt "attr-date"); attr "title" (txt "Last modified") ]
            (span_ [ class_ (txt "icon") ] (text (txt "✂"))
            ++ render_date article.art_modified_at))
    ++ render_keywords article.art_keywords
    ++ span_
         [ class_ (txt "post-icons") ]
         (render_social_link article.art_hn "/images/y18.svg"
            "Discuss on Hacker News" "Hacker News" ""
         ++ render_social_link article.art_reddit "/images/Reddit-Icon.svg"
              "Discuss on Reddit" "Reddit" ""
         ++ render_social_link article.art_lobsters "/images/Lobsters-Icon.svg"
              "Discuss on Lobste.rs" "Lobsters" "lobsters-icon"))

(* --- Table of contents rendering --- *)

let render_toc (sections : toc_section list) : Html.t =
  if sections = [] then empty
  else
    let render_toc_sub sub =
      li_
        [ class_ (txt "toc toc-level-2") ]
        (a_ [ href_ (txt "#" ^^ sub.toc_id) ] (escape_html sub.toc_title))
    in
    let render_toc_section s =
      li_
        [ class_ (txt "toc toc-level-1") ]
        (a_
           [ href_ (txt "#" ^^ s.sec_entry.toc_id) ]
           (escape_html s.sec_entry.toc_title)
        ++
        if s.sec_subsections = [] then empty
        else
          ul_
            [ class_ (txt "toc toc-level-2") ]
            (concat (List.map render_toc_sub s.sec_subsections)))
    in
    hr_ [] ++ nl
    ++ ul_
         [ class_ (txt "toc toc-level-1") ]
         (concat (List.map render_toc_section sections))
    ++ hr_ [] ++ nl

(* --- Compact article list (used on index page and "Similar articles") --- *)

let render_compact_entry (a : article) : Html.t =
  let title_attrs =
    let base = [ class_ (txt "compact-title"); href_ a.art_url ] in
    let subtitle = Elaborate.inlines_to_text a.art_subtitle in
    if Text.is_empty subtitle then base else base @ [ attr "title" subtitle ]
  in
  li_ []
    (a_ title_attrs (Render.render_inlines Render.empty_ctx a.art_title)
    ++ span_ [ class_ (txt "compact-date") ] (render_date a.art_created_at))

let render_compact_list (heading : string) (articles : article list) : Html.t =
  if articles = [] then empty
  else
    h2_ [] (escape_html (txt heading))
    ++ ul_
         [ class_ (txt "article-list") ]
         (concat (List.map render_compact_entry articles))

(* --- Similar and navigation --- *)

let render_similar : article list -> Html.t = function
  | [] -> empty
  | articles -> section_ [] (render_compact_list "Similar articles" articles)

(* --- Full post page --- *)

let render_post_page (root_url : string) (article : article)
    (toc : toc_section list) (similar : article list) (body : Html.t) : Html.t =
  doctype ++ nl
  ++ html_
       [ lang_ (txt "en") ]
       (page_head root_url article
       ++ body_ []
            (site_header
            ++ article_ []
                 (h1_
                    [ class_ (txt "article-title") ]
                    (a_
                       [ href_ article.art_url ]
                       (Render.render_inlines Render.empty_ctx article.art_title))
                 ++ render_post_attributes article
                 ++ nl ++ render_toc toc ++ nl ++ body ++ nl)
            ++ render_similar similar ++ nl ++ site_footer))
  ++ nl

(* --- Post list page --- *)

let render_post_entry (a : article) : Html.t =
  let item_classes =
    if a.art_featured then [ class_ (txt "featured") ] else []
  in
  let title_class =
    if a.art_featured then
      txt "article-title left-gutter-anchor featured-marker"
    else txt "article-title"
  in
  li_ item_classes
    (h2_
       [ class_ title_class ]
       (a_
          [ href_ a.art_url ]
          (span_ [] (Render.render_inlines Render.empty_ctx a.art_title)))
    ++ div_
         [ class_ (txt "article-subtitle") ]
         (Render.render_inlines Render.empty_ctx a.art_subtitle)
    ++ render_post_attributes a)

let list_page_head (title_text : string) : Html.t =
  head_ []
    (leaf "meta" [ charset_ (txt "UTF-8") ]
    ++ leaf "meta"
         [
           content_ (txt "width=device-width, initial-scale=1");
           name_ (txt "viewport");
         ]
    ++ leaf "meta" [ name_ (txt "author"); content_ (txt "Roman Kashitsyn") ]
    ++ title_ [] (escape_html (txt title_text))
    ++ link_ [ rel_ (txt "stylesheet"); href_ (txt "/css/mmapped.css") ]
    ++ link_ [ rel_ (txt "icon"); href_ (txt "/images/favicon.svg") ]
    ++ link_
         [
           rel_ (txt "mask-icon");
           href_ (txt "/images/mask-icon.svg");
           attr "color" (txt "#000000");
         ]
    ++ link_
         [
           rel_ (txt "alternate");
           type_ (txt "application/atom+xml");
           href_ (txt "/feed.xml");
         ])

(* Differs from [page_head] and [list_page_head]: includes the
   tdm-reservation meta and five font preloads, omits keywords/description/
   alternate feed/canonical. *)
let standalone_page_head (title : Html.t) : Html.t =
  let preload path ty =
    link_
      [
        rel_ (txt "preload");
        href_ (txt path);
        attr "as" (txt "font");
        type_ (txt ty);
        attr "crossorigin" Text.empty;
      ]
  in
  head_ []
    (leaf "meta" [ charset_ (txt "UTF-8") ]
    ++ leaf "meta"
         [
           content_ (txt "width=device-width, initial-scale=1");
           name_ (txt "viewport");
         ]
    ++ leaf "meta" [ name_ (txt "tdm-reservation"); content_ (txt "0") ]
    ++ leaf "meta" [ name_ (txt "author"); content_ (txt "Roman Kashitsyn") ]
    ++ title_ [] title
    ++ preload "/fonts/LibertinusSans-Regular.woff2" "font/woff2"
    ++ preload "/fonts/LibertinusSans-Bold.woff2" "font/woff2"
    ++ preload "/fonts/LibertinusSerif-Regular.woff2" "font/woff2"
    ++ preload "/fonts/LibertinusSerif-Bold.woff2" "font/woff2"
    ++ link_ [ rel_ (txt "stylesheet"); href_ (txt "/css/mmapped.css") ]
    ++ link_ [ rel_ (txt "icon"); href_ (txt "/images/favicon.svg") ]
    ++ link_
         [
           rel_ (txt "mask-icon");
           href_ (txt "/images/mask-icon.svg");
           attr "color" (txt "#000000");
         ])

let render_post_list_page (title_text : string) (articles : article list) :
    Html.t =
  doctype ++ nl
  ++ html_
       [ lang_ (txt "en") ]
       (list_page_head title_text
       ++ body_ []
            (site_header
            ++ section_
                 [ class_ (txt "post-list") ]
                 (if articles = [] then empty
                  else
                    ul_
                      [ class_ (txt "posts") ]
                      (concat (List.map render_post_entry articles)))
            ++ site_footer)
       ++ nl)

let render_standalone_page (title : Html.t) (url : string) (body : Html.t) :
    Html.t =
  doctype ++ nl
  ++ html_
       [ lang_ (txt "en") ]
       (standalone_page_head title
       ++ body_ []
            (site_header
            ++ article_ []
                 (h1_
                    [ class_ (txt "article-title") ]
                    (a_ [ href_ (txt url) ] title)
                 ++ body)
            ++ site_footer))
  ++ nl

(* --- Note list page --- *)

let render_note_entry (n : note) : Html.t =
  li_ []
    (a_
       [ class_ (txt "compact-title"); href_ n.note_url ]
       (Render.render_inlines Render.empty_ctx n.note_title)
    ++ span_ [ class_ (txt "compact-date") ] (render_date n.note_modified_at))

let render_note_list_page (notes : note list) : Html.t =
  doctype ++ nl
  ++ html_
       [ lang_ (txt "en") ]
       (list_page_head "Notes"
       ++ body_ []
            (site_header
            ++ section_
                 [ class_ (txt "post-list") ]
                 (h1_ [ class_ (txt "article-title") ] (escape_html (txt "Notes"))
                 ++ (if notes = [] then empty
                     else
                       ul_
                         [ class_ (txt "article-list") ]
                         (concat (List.map render_note_entry notes))))
            ++ site_footer)
       ++ nl)

(* --- Note page --- *)

let note_page_head (note : note) : Html.t =
  head_ []
    (leaf "meta" [ charset_ (txt "UTF-8") ]
    ++ leaf "meta"
         [
           content_ (txt "width=device-width, initial-scale=1");
           name_ (txt "viewport");
         ]
    ++ leaf "meta" [ name_ (txt "author"); content_ (txt "Roman Kashitsyn") ]
    ++ title_ [] (Render.render_inlines Render.empty_ctx note.note_title)
    ++ link_ [ rel_ (txt "stylesheet"); href_ (txt "/css/mmapped.css") ]
    ++ link_ [ rel_ (txt "icon"); href_ (txt "/images/favicon.svg") ]
    ++ link_
         [
           rel_ (txt "mask-icon");
           href_ (txt "/images/mask-icon.svg");
           attr "color" (txt "#000000");
         ])

let render_note_attributes (note : note) : Html.t =
  span_
    [ class_ (txt "post-attrs") ]
    (span_
       [ class_ (txt "attr-date"); attr "title" (txt "First published") ]
       (span_ [ class_ (txt "icon") ] (text (txt "✑"))
       ++ render_date note.note_created_at)
    ++
    if Date.equal note.note_modified_at note.note_created_at then empty
    else
      span_
        [ class_ (txt "attr-date"); attr "title" (txt "Last modified") ]
        (span_ [ class_ (txt "icon") ] (text (txt "✂"))
        ++ render_date note.note_modified_at))

let render_note_page (note : note) (body : Html.t)
    (referencing_articles : article list) : Html.t =
  let articles_section =
    render_compact_list "Articles" referencing_articles
  in
  doctype ++ nl
  ++ html_
       [ lang_ (txt "en") ]
       (note_page_head note
       ++ body_ []
            (site_header
            ++ article_ []
                 (h1_
                    [ class_ (txt "article-title") ]
                    (a_
                       [ href_ note.note_url ]
                       (Render.render_inlines Render.empty_ctx note.note_title))
                 ++ render_note_attributes note
                 ++ nl ++ body ++ nl)
            ++ section_ [] articles_section
            ++ site_footer))
  ++ nl

(* --- Index page --- *)

let render_index_page (body : Html.t) (featured : article list)
    (latest : article list) : Html.t =
  doctype ++ nl
  ++ html_
       [ lang_ (txt "en") ]
       (list_page_head "mmap(blog)"
       ++ body_ []
            (site_header
            ++ article_ []
                 (body
                 ++ section_ [] (render_compact_list "Featured" featured)
                 ++ section_ [] (render_compact_list "Latest" latest))
            ++ site_footer))
  ++ nl
