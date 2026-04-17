(* Dev HTTP server. Mirror of Blogware.Server.

   On every request, re-parses posts from disk and re-renders the
   requested page. This is deliberate: the intent is a low-friction
   preview during authoring, where stale output is more painful than a
   few milliseconds of CPU. *)

open Site
open Document

(* --- Small string helpers --- *)

let split_first_line s =
  match String.index_opt s '\n' with Some i -> String.sub s 0 i | None -> s

let split_ws s = String.split_on_char ' ' s |> List.filter (fun x -> x <> "")

(* --- Request parsing --- *)

let parse_request_line (req : string) : string * string =
  let first = split_first_line req in
  (* Strip trailing \r if present. *)
  let first =
    if String.length first > 0 && first.[String.length first - 1] = '\r' then
      String.sub first 0 (String.length first - 1)
    else first
  in
  match split_ws first with
  | method_ :: path :: _ -> (method_, path)
  | _ -> ("", "/")

(* --- Response building --- *)

let status_text = function
  | 200 -> "OK"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 500 -> "Internal Server Error"
  | _ -> "Unknown"

let build_response_head (status : int) (content_type : string)
    (content_length : int) : string =
  Printf.sprintf
    "HTTP/1.1 %d %s\r\n\
     Content-Type: %s\r\n\
     Content-Length: %d\r\n\
     Connection: close\r\n\
     \r\n"
    status (status_text status) content_type content_length

let build_response (status : int) (content_type : string) (body : string) :
    string =
  build_response_head status content_type (String.length body) ^ body

let send_response fd status content_type body =
  let head = build_response_head status content_type (String.length body) in
  Socket_ffi.send_all fd head;
  Socket_ffi.send_all fd body

(* --- Content-type sniffing --- *)

let suffix_to_mime =
  [|
    (".css", "text/css; charset=utf-8");
    (".woff2", "font/woff2");
    (".woff", "font/woff");
    (".ttf", "font/ttf");
    (".png", "image/png");
    (".jpg", "image/jpeg");
    (".jpeg", "image/jpeg");
    (".gif", "image/gif");
    (".svg", "image/svg+xml");
    (".ico", "image/x-icon");
    (".txt", "text/plain; charset=utf-8");
    (".xml", "application/xml; charset=utf-8");
    ("", "application/octet-stream");
  |]

let content_type_for (path : string) : string =
  match
    Array.find_index
      (fun (suffix, _) -> String.ends_with ~suffix path)
      suffix_to_mime
  with
  | Some i -> snd suffix_to_mime.(i)
  | None -> "application/octet-stream"

(* --- Handlers --- *)

let find_article (articles : article list) (path : string) :
    (int * article) option =
  let rec go i = function
    | [] -> None
    | a :: _ when a.art_url = path -> Some (i, a)
    | _ :: rest -> go (i + 1) rest
  in
  go 0 articles

let serve_index fd (config : site_config) : unit =
  match Site.load_articles config.site_input with
  | Error err -> send_response fd 500 "text/plain" err
  | Ok [] -> send_response fd 404 "text/plain" "No posts yet"
  | Ok (article :: rest as all_articles) ->
      let toc = Layout.extract_toc article.art_body in
      let similar = Layout.find_similar_articles all_articles 0 in
      let next_post = match rest with x :: _ -> Some x | [] -> None in
      let ref_table = Layout.build_ref_table all_articles article in
      let ctx = { Render.ref_table } in
      let body_html = Html.render (Render.render_blocks ctx article.art_body) in
      let page_html =
        Html.render
          (Layout.render_post_page config.site_root article toc similar None
             next_post body_html)
      in
      send_response fd 200 "text/html; charset=utf-8" page_html

let serve_post fd (config : site_config) (path : string) : unit =
  match Site.load_articles config.site_input with
  | Error err -> send_response fd 500 "text/plain" err
  | Ok articles -> (
      match find_article articles path with
      | None -> send_response fd 404 "text/plain" ("No post at path " ^ path)
      | Some (i, article) ->
          let arr = Array.of_list articles in
          let n = Array.length arr in
          let toc = Layout.extract_toc article.art_body in
          let similar = Layout.find_similar_articles articles i in
          let prev_post = if i > 0 then Some arr.(i - 1) else None in
          let next_post = if i < n - 1 then Some arr.(i + 1) else None in
          let ref_table = Layout.build_ref_table articles article in
          let ctx = { Render.ref_table } in
          let body_html =
            Html.render (Render.render_blocks ctx article.art_body)
          in
          let page_html =
            Html.render
              (Layout.render_post_page config.site_root article toc similar
                 prev_post next_post body_html)
          in
          send_response fd 200 "text/html; charset=utf-8" page_html)

let serve_post_list fd (config : site_config) : unit =
  match Site.load_articles config.site_input with
  | Error err -> send_response fd 500 "text/plain" err
  | Ok articles ->
      let page_html =
        Html.render (Layout.render_post_list_page "All Posts" articles)
      in
      send_response fd 200 "text/html; charset=utf-8" page_html

let serve_feed fd (config : site_config) : unit =
  match Site.load_articles config.site_input with
  | Error err -> send_response fd 500 "text/plain" err
  | Ok articles ->
      let feed_xml = Feed.render_atom_feed config.site_root articles in
      send_response fd 200 "application/atom+xml; charset=utf-8" feed_xml

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let n = in_channel_length ic in
      really_input_string ic n)

let serve_page fd (config : site_config) (name : string) : unit =
  let path = Filename.concat config.site_input (name ^ ".tex") in
  if not (Sys.file_exists path) then
    send_response fd 404 "text/plain" "Not Found"
  else
    let content = read_file path in
    match Tex_parser.parse_document ~source_name:path content with
    | Error err ->
        send_response fd 500 "text/plain" (Error.format_parse_error content err)
    | Ok nodes -> (
        match Elaborate.elaborate name nodes with
        | Error err ->
            send_response fd 500 "text/plain"
              (Error.format_elab_error ~source_name:path content err)
        | Ok article ->
            let body_html =
              Html.render
                (Render.render_blocks Render.empty_ctx article.art_body)
            in
            let title_text =
              Html.render
                (Render.render_inlines Render.empty_ctx article.art_title)
            in
            let page_html =
              Html.render
                (Layout.render_standalone_page title_text
                   ("/" ^ name ^ ".html")
                   body_html)
            in
            send_response fd 200 "text/html; charset=utf-8" page_html)

let serve_static fd (config : site_config) (path : string) : unit =
  (* Drop leading '/' *)
  let rel =
    if String.length path > 0 && path.[0] = '/' then
      String.sub path 1 (String.length path - 1)
    else path
  in
  let file_path = Filename.concat config.site_input rel in
  if not (Sys.file_exists file_path) then
    send_response fd 404 "text/plain" "Not Found"
  else
    let content = read_file file_path in
    let ct = content_type_for path in
    send_response fd 200 ct content

(* --- Dispatch --- *)

let handle_get fd (config : site_config) (path : string) : unit =
  if path = "/" || path = "/index.html" then serve_index fd config
  else if path = "/posts.html" then serve_post_list fd config
  else if path = "/about.html" then serve_page fd config "about"
  else if path = "/feed.xml" then serve_feed fd config
  else if String.starts_with ~prefix:"/posts/" path then
    serve_post fd config path
  else if
    String.starts_with ~prefix:"/css/" path
    || String.starts_with ~prefix:"/fonts/" path
    || String.starts_with ~prefix:"/images/" path
    || path = "/robots.txt"
  then serve_static fd config path
  else send_response fd 404 "text/plain" "Not Found"

(* --- Client handling --- *)

let handle_client fd (config : site_config) : unit =
  let req = Socket_ffi.recv_all fd 65536 in
  let method_, path = parse_request_line req in
  let start = Unix.gettimeofday () in
  (if method_ <> "GET" then
     send_response fd 405 "text/plain" "Method Not Allowed"
   else
     try handle_get fd config path
     with e ->
       prerr_endline ("Error: " ^ Printexc.to_string e);
       send_response fd 500 "text/plain" "Internal Server Error");
  let elapsed = Unix.gettimeofday () -. start in
  Printf.eprintf "%s %s (%.3fs)\n%!" method_ path elapsed;
  Socket_ffi.close_socket fd

let rec accept_loop (server_fd : Socket_ffi.fd) (config : site_config) : unit =
  let client_fd =
    try Socket_ffi.accept_conn server_fd
    with Unix.Unix_error (Unix.EINTR, _, _) ->
      prerr_endline "\nShutting down.";
      exit 0
  in
  handle_client client_fd config;
  accept_loop server_fd config

let serve (config : site_config) (port : int) : unit =
  Printf.eprintf "Listening on http://localhost:%d\n%!" port;
  let fd = Socket_ffi.listen_on port in
  accept_loop fd config
