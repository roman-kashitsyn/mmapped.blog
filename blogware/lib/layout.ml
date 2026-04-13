(* Page templates. Mirror of Blogware.Layout. *)

open Html
open Document

(* --- Table of contents --- *)

type toc_entry = {
  toc_id : string;
  toc_title : string;
}

type toc_section = {
  sec_entry : toc_entry;
  sec_subsections : toc_entry list;
}

let extract_toc (blocks : block list) : toc_section list =
  List.filter_map (function
    | Section (Some (anchor, title), body) ->
      let entry = {
        toc_id = anchor;
        toc_title = Html.render (Render.render_inlines Render.empty_ctx title);
      } in
      let subs = List.filter_map (function
        | Subsection (a, t, _) ->
          Some { toc_id = a; toc_title = Html.render (Render.render_inlines Render.empty_ctx t) }
        | _ -> None
      ) body in
      Some { sec_entry = entry; sec_subsections = subs }
    | _ -> None
  ) blocks

let build_ref_table (all_articles : article list) (article : article) : ref_table =
  let tbl =
    List.fold_left (fun acc a ->
      RefTable.add a.art_slug
        { ref_title = Html.render (Render.render_inlines Render.empty_ctx a.art_title)
        ; ref_url = a.art_url
        } acc
    ) RefTable.empty all_articles
  in
  let toc = extract_toc article.art_body in
  List.fold_left (fun acc section ->
    let acc =
      RefTable.add section.sec_entry.toc_id
        { ref_title = section.sec_entry.toc_title
        ; ref_url = "#" ^ section.sec_entry.toc_id
        } acc
    in
    List.fold_left (fun acc sub ->
      RefTable.add sub.toc_id
        { ref_title = sub.toc_title
        ; ref_url = "#" ^ sub.toc_id
        } acc
    ) acc section.sec_subsections
  ) tbl toc

(* --- Similar articles (Jaccard keyword similarity with tiebreaker) --- *)

let find_similar_articles (articles : article list) (idx : int) : article list =
  let arr = Array.of_list articles in
  let n = Array.length arr in
  let target = arr.(idx) in
  let target_kws = target.art_keywords in
  let candidates = ref [] in
  for i = 0 to n - 1 do
    if i <> idx then begin
      let a = arr.(i) in
      let common =
        List.length (List.filter (fun k -> List.mem k target_kws) a.art_keywords)
      in
      let total =
        List.length a.art_keywords + List.length target_kws - common
      in
      if total > 0 then begin
        let sim =
          float_of_int common /. float_of_int total
          -. 0.00001 *. float_of_int (abs (i - idx))
        in
        if sim >= 0.4 then
          candidates := (sim, a) :: !candidates
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

(* --- Page head --- *)

let page_head (root_url : string) (article : article) : Html.t =
  let description_meta =
    if article.art_subtitle = [] then empty
    else
      leaf "meta"
        [ name_ "description"
        ; content_ (Html.render (Render.render_inlines Render.empty_ctx article.art_subtitle))
        ]
  in
  head_ []
    ( leaf "meta" [charset_ "UTF-8"]
      ++ leaf "meta" [content_ "width=device-width, initial-scale=1"; name_ "viewport"]
      ++ leaf "meta" [name_ "author"; content_ "Roman Kashitsyn"]
      ++ leaf "meta"
           [ name_ "keywords"
           ; content_ (String.concat "," article.art_keywords)
           ]
      ++ description_meta
      ++ title_ [] (Render.render_inlines Render.empty_ctx article.art_title)
      ++ link_ [rel_ "stylesheet"; href_ "/css/tufte.css"]
      ++ link_ [rel_ "icon"; href_ "/images/favicon.svg"]
      ++ link_ [rel_ "mask-icon"; href_ "/images/mask-icon.svg"; attr "color" "#000000"]
      ++ link_ [rel_ "alternate"; type_ "application/atom+xml"; href_ "/feed.xml"]
      ++ link_ [rel_ "canonical"; href_ (root_url ^ article.art_url)]
    )

(* --- Site header / footer --- *)

let site_header : Html.t =
  header_ []
    (nav_ []
       (ul_ []
          ( li_ [] (a_ [class_ "blog-title"; href_ "/index.html"] (raw "mmap(blog)"))
            ++ li_ [] (a_ [href_ "/posts.html"] (raw "Posts"))
            ++ li_ [] (a_ [href_ "/about.html"] (raw "About"))
            ++ li_ [] (a_ [href_ "/feed.xml"] (raw "Atom Feed"))
          )))

let site_footer : Html.t =
  footer_ []
    ( span_ [] (raw "&copy;Roman Kashitsyn")
      ++ raw "&nbsp;\n"
      ++ a_
           [ rel_ "license"
           ; href_ "http://creativecommons.org/licenses/by/4.0/"
           ; attr "style" "vertical-align: text-top;"
           ; attr "title" "This work is licensed under a Creative Commons Attribution 4.0 International License"
           ]
           (leaf "img"
              [ alt_ "Creative Commons License"
              ; attr "style" "border-width:0;width:80px;height:15px;text-decoration:none;"
              ; src_ "https://i.creativecommons.org/l/by/4.0/80x15.png"
              ])
      ++ br_ []
      ++ nl
      ++ a_
           [class_ "github-link"; href_ "https://github.com/roman-kashitsyn/mmapped.blog"]
           (raw "Source Code")
    )

(* --- Post attributes (dates and social links) --- *)

let format_date (d : Date.t) : string = Date.to_string d

let render_social_link link icon title_text alt_text extra_class : Html.t =
  match link with
  | None -> empty
  | Some url ->
    a_
      [ class_ "icon-link"
      ; href_ url
      ; attr "title" title_text
      ; rel_ "nofollow"
      ; attr "target" "_blank"
      ]
      (leaf "img"
         [ class_
             ("social-icon"
              ^ (if extra_class = "" then "" else " " ^ extra_class))
         ; src_ icon
         ; alt_ alt_text
         ])

let render_post_attributes (article : article) : Html.t =
  span_ [class_ "post-attrs"]
    ( span_ [attr "title" "First published"]
        ( raw "\xE2\x9C\x8F "  (* ✏ *)
          ++ span_ [attr "itemprop" "datePublished"]
               (raw (format_date article.art_created_at))
        )
      ++ raw "&nbsp;\n"
      ++ span_ [attr "title" "Last modified"]
           ( raw "\xE2\x9C\x82 "  (* ✂ *)
             ++ span_ [attr "itemprop" "dateModified"]
                  (raw (format_date article.art_modified_at))
           )
      ++ span_ [class_ "post-icons"]
           ( render_social_link article.art_hn
               "/images/y18.svg" "Discuss on Hacker News" "Hacker News" ""
             ++ render_social_link article.art_reddit
                  "/images/Reddit-Icon.svg" "Discuss on Reddit" "Reddit" ""
             ++ render_social_link article.art_lobsters
                  "/images/Lobsters-Icon.svg" "Discuss on Lobste.rs" "Lobsters" "lobsters-icon"
           )
    )

(* --- Table of contents rendering --- *)

let render_toc (sections : toc_section list) : Html.t =
  if sections = [] then empty
  else
    let render_toc_sub sub =
      li_ [class_ "toc toc-level-2"]
        (a_ [href_ ("#" ^ sub.toc_id)] (raw sub.toc_title))
    in
    let render_toc_section s =
      li_ [class_ "toc toc-level-1"]
        ( a_ [href_ ("#" ^ s.sec_entry.toc_id)] (raw s.sec_entry.toc_title)
          ++ (if s.sec_subsections = [] then empty
              else
                ul_ [class_ "toc toc-level-2"]
                  (concat (List.map render_toc_sub s.sec_subsections)))
        )
    in
    hr_ []
    ++ nl
    ++ ul_ [class_ "toc toc-level-1"]
         (concat (List.map render_toc_section sections))
    ++ hr_ []
    ++ nl

(* --- Similar and navigation --- *)

let render_similar : article list -> Html.t = function
  | [] -> empty
  | articles ->
    h2_ [] (raw "Similar articles")
    ++ ul_ [class_ "arrows"]
         (concat (List.map (fun a ->
            li_ [] (a_ [href_ a.art_url] (Render.render_inlines Render.empty_ctx a.art_title))
          ) articles))

let render_navigation (prev : article option) (next : article option) : Html.t =
  match prev, next with
  | None, None -> empty
  | _ ->
    let prev_html = match prev with
      | None -> empty
      | Some a ->
        div_ [id_ "newer"]
          (a_ [href_ a.art_url]
             (raw " \xE2\x86\x90"  (* ← *)
              ++ Render.render_inlines Render.empty_ctx a.art_title))
    in
    let next_html = match next with
      | None -> empty
      | Some a ->
        div_ [id_ "older"]
          (a_ [href_ a.art_url]
             (Render.render_inlines Render.empty_ctx a.art_title
              ++ raw "\xE2\x86\x92 "  (* → *)))
    in
    div_ [id_ "next-prev-nav"] (prev_html ++ next_html) ++ nl

(* --- Full post page --- *)

let render_post_page
    (root_url : string)
    (article : article)
    (toc : toc_section list)
    (similar : article list)
    (prev_post : article option)
    (next_post : article option)
    (body_html : string)
  : Html.t =
  doctype
  ++ nl
  ++ html_ [lang_ "en"]
       ( page_head root_url article
         ++ body_ []
              (article_ []
                 ( site_header
                   ++ h1_ [class_ "article-title"]
                        (a_ [href_ article.art_url]
                           (Render.render_inlines Render.empty_ctx article.art_title))
                   ++ render_post_attributes article
                   ++ nl
                   ++ render_toc toc
                   ++ nl
                   ++ raw body_html
                   ++ nl
                   ++ render_similar similar
                   ++ render_navigation prev_post next_post
                   ++ hr_ []
                   ++ nl
                   ++ site_footer
                 ))
       )
  ++ nl

(* --- Post list page --- *)

let render_post_entry (a : article) : Html.t =
  li_ [attr "itemscope" ""; attr "itemtype" "https://schema.org/CreativeWork"]
    ( leaf "meta" [attr "keywords" (String.concat "," a.art_keywords)]
      ++ h2_ [class_ "article-title"]
           (a_ [href_ a.art_url]
              (span_ [attr "itemprop" "headline"]
                 (Render.render_inlines Render.empty_ctx a.art_title)))
      ++ div_ [class_ "article-abstract"; attr "itemprop" "abstract"]
           (Render.render_inlines Render.empty_ctx a.art_subtitle)
      ++ render_post_attributes a
    )

let list_page_head (title_text : string) : Html.t =
  head_ []
    ( leaf "meta" [charset_ "UTF-8"]
      ++ leaf "meta" [content_ "width=device-width, initial-scale=1"; name_ "viewport"]
      ++ leaf "meta" [name_ "author"; content_ "Roman Kashitsyn"]
      ++ title_ [] (raw title_text)
      ++ link_ [rel_ "stylesheet"; href_ "/css/tufte.css"]
      ++ link_ [rel_ "icon"; href_ "/images/favicon.svg"]
      ++ link_ [rel_ "mask-icon"; href_ "/images/mask-icon.svg"; attr "color" "#000000"]
      ++ link_ [rel_ "alternate"; type_ "application/atom+xml"; href_ "/feed.xml"]
    )

(* Mirrors Go's page.tmpl — used only for standalone pages (about.html).
   Differs from [page_head] and [list_page_head]: includes the
   tdm-reservation meta and five font preloads, omits keywords/description/
   alternate feed/canonical. *)
let standalone_page_head (title_text : string) : Html.t =
  let preload path ty =
    link_
      [ rel_ "preload"
      ; href_ path
      ; attr "as" "font"
      ; type_ ty
      ; attr "crossorigin" ""
      ]
  in
  head_ []
    ( leaf "meta" [charset_ "UTF-8"]
      ++ leaf "meta" [content_ "width=device-width, initial-scale=1"; name_ "viewport"]
      ++ leaf "meta" [name_ "tdm-reservation"; content_ "0"]
      ++ leaf "meta" [name_ "author"; content_ "Roman Kashitsyn"]
      ++ title_ [] (raw title_text)
      ++ preload "/fonts/LibertinusSans-Regular.woff2"  "font/woff2"
      ++ preload "/fonts/LibertinusSans-Bold.woff2"     "font/woff2"
      ++ preload "/fonts/LibertinusSerif-Regular.woff2" "font/woff2"
      ++ preload "/fonts/LibertinusSerif-Bold.woff2"    "font/woff2"
      ++ preload "/fonts/YanoneKaffeesatz-Regular.otf"  "font/otf"
      ++ link_ [rel_ "stylesheet"; href_ "/css/tufte.css"]
      ++ link_ [rel_ "icon"; href_ "/images/favicon.svg"]
      ++ link_ [rel_ "mask-icon"; href_ "/images/mask-icon.svg"; attr "color" "#000000"]
    )

let render_post_list_page (title_text : string) (articles : article list) : Html.t =
  doctype
  ++ nl
  ++ html_ [lang_ "en"]
       ( list_page_head title_text
         ++ body_ []
              (article_ []
                 ( site_header
                   ++ hr_ []
                   ++ nl
                   ++ (if articles = [] then empty
                       else
                         ul_ [class_ "posts"]
                           (concat (List.map render_post_entry articles)))
                   ++ nl
                   ++ hr_ []
                   ++ nl
                   ++ site_footer
                 ))
       )
  ++ nl

let render_standalone_page (title_text : string) (url : string) (body_html : string) : Html.t =
  let link_href =
    if String.length url > 0 && url.[0] = '/'
    then String.sub url 1 (String.length url - 1)
    else url
  in
  doctype
  ++ nl
  ++ html_ [lang_ "en"]
       ( standalone_page_head title_text
         ++ body_ []
              (article_ []
                 ( site_header
                   ++ h1_ [class_ "article-title"]
                        (a_ [href_ link_href] (raw title_text))
                   ++ hr_ []
                   ++ raw body_html
                   ++ hr_ []
                   ++ nl
                   ++ site_footer
                 ))
       )
  ++ nl
