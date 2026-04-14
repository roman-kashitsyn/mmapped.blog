(* Full-site loader and renderer. Mirror of Blogware.Site.

   This is the only module that touches the filesystem. It loads all
   posts/*.tex, runs them through parser → elaborate, then writes the
   rendered HTML/XML output. *)

open Document

type site_config = {
  site_input : string;
  site_output : string;
  site_root : string;
}

(* --- Small filesystem helpers (Unix + Sys stdlib only) --- *)

let ( // ) a b = Filename.concat a b

let is_directory path =
  try Sys.is_directory path with Sys_error _ -> false

let is_regular_file path =
  Sys.file_exists path && not (is_directory path)

let read_file_contents path : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () ->
       let len = in_channel_length ic in
       really_input_string ic len)

let write_file_contents path content : unit =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

let rec mkdir_p path =
  if is_directory path then ()
  else begin
    let parent = Filename.dirname path in
    if parent <> path && not (is_directory parent) then mkdir_p parent;
    try Unix.mkdir path 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let list_dir path =
  try Array.to_list (Sys.readdir path)
  with Sys_error _ -> []

let copy_file src dst =
  let content = read_file_contents src in
  write_file_contents dst content

let rec copy_directory_recursive src dst =
  mkdir_p dst;
  List.iter (fun entry ->
    let sp = src // entry in
    let dp = dst // entry in
    if is_directory sp then copy_directory_recursive sp dp
    else copy_file sp dp
  ) (list_dir src)

let take_base_name filename =
  Filename.remove_extension (Filename.basename filename)

(* --- Article loading --- *)

let load_article (dir : string) (file : string) : (article, string) result =
  let path = dir // file in
  let slug = take_base_name file in
  let content = read_file_contents path in
  match Parser.parse_document ~source_name:path content with
  | Error err -> Error (Error.format_parse_error content err)
  | Ok nodes ->
    match Elaborate.elaborate slug nodes with
    | Error err -> Error (Error.format_elab_error content err)
    | Ok article ->
      Ok { article with art_url = "/posts/" ^ take_base_name file ^ ".html" }

(* Load and sort all *.tex files under {input}/posts, newest-first. *)
let load_articles (input_dir : string) : (article list, string) result =
  let posts_dir = input_dir // "posts" in
  if not (is_directory posts_dir) then
    Error ("Posts directory not found: " ^ posts_dir)
  else begin
    let files = list_dir posts_dir in
    let tex_files =
      List.filter (fun f -> Filename.extension f = ".tex") files
    in
    (* Sort descending by filename to get newest-first (assuming the
       usual YYYY-MM-DD-slug.tex convention). *)
    let sorted = List.sort (fun a b -> compare b a) tex_files in
    let rec load_all acc = function
      | [] -> Ok (List.rev acc)
      | f :: rest ->
        (match load_article posts_dir f with
         | Error _ as e -> e
         | Ok art -> load_all (art :: acc) rest)
    in
    load_all [] sorted
  end

(* --- Site layout spec --- *)

(* Mirror of [SiteLayout] from ../mmapped.blog/blogware/layout.go. Each
   entry says what to produce at a given output path. The site renderer
   walks this list top-to-bottom; order decides which posts exist before
   the index page renders. *)

type asset_type =
  | Static_files
  | Index_page
  | TeX_articles
  | Standalone_page
  | Post_list
  | Atom_xml_feed

type layout_entry = { le_path : string; le_type : asset_type }

let site_layout : layout_entry list =
  [ { le_path = "/css/";       le_type = Static_files }
  ; { le_path = "/fonts/";     le_type = Static_files }
  ; { le_path = "/images/";    le_type = Static_files }
  ; { le_path = "/robots.txt"; le_type = Static_files }
  ; { le_path = "/posts/";     le_type = TeX_articles }
  ; { le_path = "/posts.html"; le_type = Post_list }
  ; { le_path = "/about.html"; le_type = Standalone_page }
  ; { le_path = "/feed.xml";   le_type = Atom_xml_feed }
  ; { le_path = "/index.html"; le_type = Index_page }
  ]

(* --- Site rendering --- *)

let eprintln s = prerr_endline s

(* Drop a leading '/' so paths can be joined against the output dir. *)
let strip_leading_slash s =
  if String.length s > 0 && s.[0] = '/'
  then String.sub s 1 (String.length s - 1)
  else s

(* Replace the ".html" suffix with ".tex". *)
let html_to_tex path =
  Filename.remove_extension path ^ ".tex"

(* Render one article as its own post page, with neighbour links. *)
let render_one_post ~root_url ~all_articles ~prev_post ~next_post article =
  let toc = Layout.extract_toc article.art_body in
  let similar =
    let rec index_of i = function
      | [] -> 0
      | a :: _ when a.art_slug = article.art_slug -> i
      | _ :: rest -> index_of (i + 1) rest
    in
    Layout.find_similar_articles all_articles (index_of 0 all_articles)
  in
  let ref_table = Layout.build_ref_table all_articles article in
  let ctx = { Render.ref_table = ref_table } in
  let body_html = Html.render (Render.render_blocks ctx article.art_body) in
  Html.render
    (Layout.render_post_page
       root_url article toc similar prev_post next_post body_html)

(* Render the standalone page at [page_path] (e.g. "/about.html"). The
   source file is the sibling [.tex] in [input_dir]. *)
let render_standalone_from ~input_dir page_path : (string, string) result =
  let tex_path = input_dir // strip_leading_slash (html_to_tex page_path) in
  let slug = take_base_name tex_path in
  let content = read_file_contents tex_path in
  match Parser.parse_document ~source_name:tex_path content with
  | Error err -> Error (Error.format_parse_error content err)
  | Ok nodes ->
    match Elaborate.elaborate slug nodes with
    | Error err -> Error (Error.format_elab_error content err)
    | Ok article ->
      let body_html = Html.render (Render.render_blocks Render.empty_ctx article.art_body) in
      let title_text = Html.render (Render.render_inlines Render.empty_ctx article.art_title) in
      Ok (Html.render
            (Layout.render_standalone_page title_text page_path body_html))

(* Copy [src] to [dst], handling both files and directories. *)
let copy_recursively src dst =
  if is_directory src then copy_directory_recursive src dst
  else if is_regular_file src then begin
    mkdir_p (Filename.dirname dst);
    copy_file src dst
  end

let generated_output_paths (input_dir : string) : (string list, string) result =
  match load_articles input_dir with
  | Error _ as e -> e
  | Ok articles ->
    let paths =
      List.concat
        (List.map (fun { le_path; le_type } ->
           match le_type with
           | Static_files -> []
           | TeX_articles ->
             List.map (fun article -> strip_leading_slash article.art_url) articles
           | Index_page
           | Standalone_page
           | Post_list
           | Atom_xml_feed ->
             [strip_leading_slash le_path]
         ) site_layout)
    in
    Ok paths

let rendered_outputs (config : site_config) : ((string * string) list, string) result =
  let input_dir = config.site_input in
  let root_url = config.site_root in
  match load_articles input_dir with
  | Error _ as e -> e
  | Ok articles ->
    let arr = Array.of_list articles in
    let n = Array.length arr in
    let outputs = ref [] in
    let emit path content =
      outputs := (strip_leading_slash path, content) :: !outputs
    in
    let rec collect = function
      | [] -> Ok (List.rev !outputs)
      | { le_path; le_type } :: rest ->
        (match le_type with
         | Static_files -> Ok ()
         | Index_page ->
           (match articles with
            | [] -> Ok ()
            | article :: rest_articles ->
              let next_post = match rest_articles with x :: _ -> Some x | [] -> None in
              let page_html =
                render_one_post ~root_url ~all_articles:articles
                  ~prev_post:None ~next_post article
              in
              emit le_path page_html;
              Ok ())
         | TeX_articles ->
           Array.iteri (fun i article ->
             let prev_post = if i > 0 then Some arr.(i - 1) else None in
             let next_post = if i < n - 1 then Some arr.(i + 1) else None in
             let page_html =
               render_one_post ~root_url ~all_articles:articles
                 ~prev_post ~next_post article
             in
             emit article.art_url page_html
           ) arr;
           Ok ()
         | Standalone_page ->
           (match render_standalone_from ~input_dir le_path with
            | Ok html ->
              emit le_path html;
              Ok ()
            | Error _ as e -> e)
         | Post_list ->
           let html =
             Html.render (Layout.render_post_list_page "All Posts" articles)
           in
           emit le_path html;
           Ok ()
         | Atom_xml_feed ->
           let feed_xml = Feed.render_atom_feed root_url articles in
           emit le_path feed_xml;
           Ok ())
        |> function
        | Error _ as e -> e
        | Ok () -> collect rest
    in
    collect site_layout

let render_site (config : site_config) : unit =
  let input_dir = config.site_input in
  let output_dir = config.site_output in

  mkdir_p output_dir;

  match rendered_outputs config with
  | Error err -> eprintln ("Error: " ^ err)
  | Ok outputs ->
    List.iter (fun { le_path; le_type } ->
      let src = input_dir // strip_leading_slash le_path in
      let dst = output_dir // strip_leading_slash le_path in
      (* Create the directory for trailing-slash entries up front, like
         RenderSite() does in the Go reference. *)
      let is_dir_entry =
        String.length le_path > 0
        && le_path.[String.length le_path - 1] = '/'
      in
      if is_dir_entry then begin
        eprintln ("Creating " ^ dst);
        mkdir_p dst
      end;
      match le_type with
      | Static_files ->
        if Sys.file_exists src then copy_recursively src dst
      | Index_page
      | TeX_articles
      | Standalone_page
      | Post_list
      | Atom_xml_feed -> ()
    ) site_layout;
    List.iter (fun (rel_path, content) ->
      eprintln ("Rendering /" ^ rel_path);
      let dst = output_dir // rel_path in
      mkdir_p (Filename.dirname dst);
      write_file_contents dst content
    ) outputs;

    eprintln "Done."
