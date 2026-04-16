(* Profiling harness: parse, elaborate, and render a single .tex file.
   Mirror of Profile.hs. *)

open Blogware

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let () =
  match Array.to_list Sys.argv |> List.tl with
  | [ path ] -> (
      let content = read_file path in
      match Tex_parser.parse_document ~source_name:path content with
      | Error err ->
          prerr_endline ("Parse error: " ^ Error.format_parse_error content err)
      | Ok nodes -> (
          match Elaborate.elaborate "profile" nodes with
          | Error err ->
              prerr_endline
                ("Elab error: "
                ^ Error.format_elab_error ~source_name:path content err)
          | Ok article ->
              let html =
                Html.render
                  (Render.render_blocks Render.empty_ctx
                     article.Document.art_body)
              in
              print_string html))
  | _ -> prerr_endline "Usage: profile <file.tex>"
