(* Full-site loader and renderer.
   It loads all posts/*.tex, parses, elaborates, and writes the rendered HTML/XML output. *)

open Document

type site_config = {
  site_input : string;
  site_output : string;
  site_root : string;
}

(* --- Small filesystem helpers (Unix + Sys stdlib only) --- *)

let ( // ) a b = Filename.concat a b
let is_directory path = try Sys.is_directory path with Sys_error _ -> false
let is_regular_file path = Sys.file_exists path && not (is_directory path)

let read_file_contents path : string =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
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
    try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let list_dir path =
  try Array.to_list (Sys.readdir path) with Sys_error _ -> []

let copy_file src dst =
  let content = read_file_contents src in
  write_file_contents dst content

let rec copy_directory_recursive src dst =
  mkdir_p dst;
  List.iter
    (fun entry ->
      let sp = src // entry in
      let dp = dst // entry in
      if is_directory sp then copy_directory_recursive sp dp
      else copy_file sp dp)
    (list_dir src)

let take_base_name filename =
  Filename.remove_extension (Filename.basename filename)

(* --- Article loading --- *)

let load_article (dir : string) (file : string) : (article, string) result =
  let path = dir // file in
  let slug = take_base_name file in
  let content = read_file_contents path in
  match Tex_parser.parse_document ~source_name:path content with
  | Error err -> Error (Error.format_parse_error content err)
  | Ok nodes -> (
      match Elaborate.elaborate slug nodes with
      | Error err ->
          Error (Error.format_elab_error ~source_name:path content err)
      | Ok article ->
          Ok
            {
              article with
              art_url =
                Text.of_string ("/posts/" ^ take_base_name file ^ ".html");
            })

(* --- Note loading --- *)

let load_note (dir : string) (file : string) : (note, string) result =
  let path = dir // file in
  let slug = take_base_name file in
  let content = read_file_contents path in
  match Tex_parser.parse_document ~source_name:path content with
  | Error err -> Error (Error.format_parse_error content err)
  | Ok nodes -> (
      match Elaborate.elaborate_note slug nodes with
      | Error err ->
          Error (Error.format_elab_error ~source_name:path content err)
      | Ok note -> Ok note)

let load_notes (input_dir : string) : (note list, string) result =
  let notes_dir = input_dir // "notes" in
  if not (is_directory notes_dir) then Ok []
  else begin
    let files = list_dir notes_dir in
    let tex_files =
      List.filter (fun f -> Filename.extension f = ".tex") files
    in
    let sorted = List.sort compare tex_files in
    let rec load_all acc = function
      | [] -> Ok (List.rev acc)
      | f :: rest -> (
          match load_note notes_dir f with
          | Error _ as e -> e
          | Ok n -> load_all (n :: acc) rest)
    in
    load_all [] sorted
  end

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
      | f :: rest -> (
          match load_article posts_dir f with
          | Error _ as e -> e
          | Ok art -> load_all (art :: acc) rest)
    in
    load_all [] sorted
  end

(* --- Site layout spec --- *)

(* Each entry says what to produce at a given output path.
   The site renderer walks this list top-to-bottom.
   Order decides which posts exist before the index page renders. *)

type asset_type =
  | Static_files
  | Index_page
  | TeX_articles
  | TeX_notes
  | Standalone_page
  | Post_list
  | Note_list
  | Atom_xml_feed

type layout_entry = { le_path : string; le_type : asset_type }

let site_layout : layout_entry list =
  [
    { le_path = "/css/"; le_type = Static_files };
    { le_path = "/fonts/"; le_type = Static_files };
    { le_path = "/images/"; le_type = Static_files };
    { le_path = "/robots.txt"; le_type = Static_files };
    { le_path = "/posts/"; le_type = TeX_articles };
    { le_path = "/notes/"; le_type = TeX_notes };
    { le_path = "/posts.html"; le_type = Post_list };
    { le_path = "/notes/index.html"; le_type = Note_list };
    { le_path = "/feed.xml"; le_type = Atom_xml_feed };
    { le_path = "/index.html"; le_type = Index_page };
  ]

(* --- Site rendering --- *)

let eprintln s = prerr_endline s

(* Drop a leading '/' so paths can be joined against the output dir. *)
let strip_leading_slash s =
  match Strings.strip_prefix ~prefix:"/" s with
  | Some stripped -> stripped
  | None -> s

(* Replace the ".html" suffix with ".tex". *)
let html_to_tex path = Filename.remove_extension path ^ ".tex"

let take n lst =
  let rec aux acc n = function
    | _ when n <= 0 -> List.rev acc
    | [] -> List.rev acc
    | x :: rest -> aux (x :: acc) (n - 1) rest
  in
  aux [] n lst

(* Build keyword → article list map from all articles, newest first. *)
let build_keyword_map (articles : article list) : article list Text.Map.t =
  let unsorted =
    List.fold_left
      (fun acc (a : article) ->
        List.fold_left
          (fun acc kw ->
            let prev = match Text.Map.find_opt kw acc with Some l -> l | None -> [] in
            Text.Map.add kw (a :: prev) acc)
          acc a.art_keywords)
      Text.Map.empty articles
  in
  Text.Map.map
    (List.sort (fun (a : article) (b : article) ->
       Date.compare b.art_created_at a.art_created_at))
    unsorted


(* Render one article as its own post page. *)
let render_one_post ~root_url ~all_articles ~all_notes ~idx article =
  let toc = Layout.extract_toc article.art_body in
  let similar = Layout.find_similar_articles all_articles idx in
  let ref_table = Layout.build_ref_table all_articles all_notes article in
  let ctx = { Render.ref_table } in
  let body = Render.render_blocks ctx article.art_body in
  Html.render (Layout.render_post_page root_url article toc similar body)

(* Render one note as its own page. *)
let render_one_note ~all_articles ~all_notes ~keyword_articles (note : note) =
  let ref_table = Layout.build_note_ref_table all_articles all_notes note in
  let ctx = { Render.ref_table } in
  let body = Render.render_blocks ctx note.note_body in
  let articles =
    match Text.Map.find_opt note.note_slug keyword_articles with
    | Some l -> l
    | None -> []
  in
  Html.render (Layout.render_note_page note body articles)

(* Render the standalone page at [page_path] (e.g. "/about.html"). The
   source file is the sibling [.tex] in [input_dir]. *)
let render_standalone_from ~input_dir ~all_articles ~all_notes page_path :
    (string, string) result =
  let tex_path = input_dir // strip_leading_slash (html_to_tex page_path) in
  let slug = take_base_name tex_path in
  let content = read_file_contents tex_path in
  match Tex_parser.parse_document ~source_name:tex_path content with
  | Error err -> Error (Error.format_parse_error content err)
  | Ok nodes -> (
      match Elaborate.elaborate slug nodes with
      | Error err ->
          Error (Error.format_elab_error ~source_name:tex_path content err)
      | Ok article ->
          let ref_table =
            Layout.build_global_ref_table all_articles all_notes
          in
          let ctx = { Render.ref_table } in
          let body = Render.render_blocks ctx article.art_body in
          let title = Render.render_inlines ctx article.art_title in
          Ok (Html.render (Layout.render_standalone_page title page_path body)))

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
  | Ok articles -> (
      match load_notes input_dir with
      | Error _ as e -> e
      | Ok notes ->
          let paths =
            List.concat
              (List.map
                 (fun { le_path; le_type } ->
                   match le_type with
                   | Static_files -> []
                   | TeX_articles ->
                       List.map
                         (fun article ->
                           strip_leading_slash (Text.to_string article.art_url))
                         articles
                   | TeX_notes ->
                       List.map
                         (fun (note : note) ->
                           strip_leading_slash (Text.to_string note.note_url))
                         notes
                   | Index_page | Standalone_page | Post_list | Note_list
                   | Atom_xml_feed ->
                       [ strip_leading_slash le_path ])
                 site_layout)
          in
          Ok paths)

let rendered_outputs (config : site_config) :
    ((string * string) list, string) result =
  let input_dir = config.site_input in
  let root_url = config.site_root in
  match load_articles input_dir with
  | Error _ as e -> e
  | Ok articles -> (
      match load_notes input_dir with
      | Error _ as e -> e
      | Ok notes ->
          let keyword_articles = build_keyword_map articles in
          let arr = Array.of_list articles in
          let outputs = ref [] in
          let emit path content =
            outputs := (strip_leading_slash path, content) :: !outputs
          in
          let rec collect = function
            | [] -> Ok (List.rev !outputs)
            | { le_path; le_type } :: rest -> (
                (match le_type with
                  | Static_files -> Ok ()
                  | Index_page -> (
                      let index_tex = input_dir // "index.tex" in
                      if not (is_regular_file index_tex) then
                        Error ("Index file not found: " ^ index_tex)
                      else
                        let content = read_file_contents index_tex in
                        match
                          Tex_parser.parse_document ~source_name:index_tex
                            content
                        with
                        | Error err ->
                            Error (Error.format_parse_error content err)
                        | Ok nodes -> (
                            match Elaborate.elaborate "index" nodes with
                            | Error err ->
                                Error
                                  (Error.format_elab_error
                                     ~source_name:index_tex content err)
                            | Ok index_article ->
                                let ref_table =
                                  Layout.build_global_ref_table articles notes
                                in
                                let ctx = { Render.ref_table } in
                                let body =
                                  Render.render_blocks ctx
                                    index_article.art_body
                                in
                                let featured =
                                  take 5
                                    (List.filter
                                       (fun a -> a.art_featured)
                                       articles)
                                in
                                let latest = take 5 articles in
                                let page_html =
                                  Html.render
                                    (Layout.render_index_page body featured
                                       latest)
                                in
                                emit le_path page_html;
                                Ok ()))
                  | TeX_articles ->
                      Array.iteri
                        (fun i article ->
                          let page_html =
                            render_one_post ~root_url ~all_articles:articles
                              ~all_notes:notes ~idx:i article
                          in
                          emit (Text.to_string article.art_url) page_html)
                        arr;
                      Ok ()
                  | TeX_notes ->
                      List.iter
                        (fun (note : note) ->
                          let page_html =
                            render_one_note ~all_articles:articles
                              ~all_notes:notes ~keyword_articles note
                          in
                          emit (Text.to_string note.note_url) page_html)
                        notes;
                      Ok ()
                  | Standalone_page -> (
                      match
                        render_standalone_from ~input_dir
                          ~all_articles:articles ~all_notes:notes le_path
                      with
                      | Ok html ->
                          emit le_path html;
                          Ok ()
                      | Error _ as e -> e)
                  | Post_list ->
                      let html =
                        Html.render
                          (Layout.render_post_list_page "All Posts" articles)
                      in
                      emit le_path html;
                      Ok ()
                  | Note_list ->
                      let sorted =
                        List.sort
                          (fun (a : note) (b : note) ->
                            Date.compare b.note_modified_at a.note_modified_at)
                          notes
                      in
                      let html =
                        Html.render (Layout.render_note_list_page sorted)
                      in
                      emit le_path html;
                      Ok ()
                  | Atom_xml_feed ->
                      let feed_xml = Feed.render_atom_feed root_url articles in
                      emit le_path feed_xml;
                      Ok ())
                |> function
                | Error _ as e -> e
                | Ok () -> collect rest)
          in
          collect site_layout)

let render_site (config : site_config) : unit =
  let input_dir = config.site_input in
  let output_dir = config.site_output in

  mkdir_p output_dir;

  match rendered_outputs config with
  | Error err -> eprintln ("Error: " ^ err)
  | Ok outputs ->
      List.iter
        (fun { le_path; le_type } ->
          let src = input_dir // strip_leading_slash le_path in
          let dst = output_dir // strip_leading_slash le_path in
          let is_dir_entry =
            String.length le_path > 0
            && le_path.[String.length le_path - 1] = '/'
          in
          if is_dir_entry then begin
            eprintln ("Creating " ^ dst);
            mkdir_p dst
          end;
          match le_type with
          | Static_files -> if Sys.file_exists src then copy_recursively src dst
          | Index_page | TeX_articles | TeX_notes | Standalone_page | Post_list
          | Note_list | Atom_xml_feed ->
              ())
        site_layout;
      List.iter
        (fun (rel_path, content) ->
          eprintln ("Rendering /" ^ rel_path);
          let dst = output_dir // rel_path in
          mkdir_p (Filename.dirname dst);
          write_file_contents dst content)
        outputs;

      eprintln "Done."
