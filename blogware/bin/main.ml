(* Blogware CLI. Mirror of Haskell Main.

   Supports two modes:
     -output DIR    static site generation
     -serve PORT    dev HTTP server
   plus shared options -input, -root. *)

open Blogware
open Site

let usage =
  "Usage: blogware [options]\n\n" ^ "Options:\n"
  ^ "  -input DIR     Input directory (default: .)\n"
  ^ "  -output DIR    Output directory for static generation\n"
  ^ "  -root URL      Root URL (default: https://mmapped.blog)\n"
  ^ "  -serve PORT    Start HTTP server on PORT\n"
  ^ "  -f FILE        Render a single file (not yet implemented)\n"

type parsed = {
  input : string option;
  output : string option;
  root : string;
  serve_port : int option;
}

let empty =
  {
    input = None;
    output = None;
    root = "https://mmapped.blog";
    serve_port = None;
  }

let rec parse_args acc = function
  | [] -> Ok acc
  | "-input" :: dir :: rest -> parse_args { acc with input = Some dir } rest
  | "-output" :: dir :: rest -> parse_args { acc with output = Some dir } rest
  | "-root" :: url :: rest -> parse_args { acc with root = url } rest
  | "-serve" :: port_str :: rest -> (
      match int_of_string_opt port_str with
      | Some p -> parse_args { acc with serve_port = Some p } rest
      | None -> Error ("Invalid port number: " ^ port_str))
  | "-f" :: _ :: _ -> Error "Single-file rendering not yet implemented"
  | unknown :: _ -> Error ("Unknown option: " ^ unknown)

let run (p : parsed) : unit =
  let input = match p.input with Some s -> s | None -> "." in
  match p.serve_port with
  | Some port ->
      let config =
        { site_input = input; site_output = ""; site_root = p.root }
      in
      Server.serve config port
  | None -> (
      match p.output with
      | None ->
          prerr_endline "Error: Either -output or -serve is required";
          prerr_endline usage;
          exit 1
      | Some out ->
          let config =
            { site_input = input; site_output = out; site_root = p.root }
          in
          Site.render_site config)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  match parse_args empty args with
  | Error err ->
      prerr_endline ("Error: " ^ err);
      prerr_endline usage;
      exit 1
  | Ok p -> run p
