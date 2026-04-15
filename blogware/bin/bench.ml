open Blogware

type sample = {
  parse_s : float;
  elab_s : float;
  render_s : float;
  total_s : float;
  words : float;
}

let usage () =
  prerr_endline "Usage: bench ITERATIONS FILE [FILE ...]";
  exit 1

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let now () = Unix.gettimeofday ()

let allocated_words () =
  let st = Gc.quick_stat () in
  st.minor_words +. st.major_words

let run_once path content =
  Gc.compact ();
  let words0 = allocated_words () in
  let t0 = now () in
  let nodes =
    match Parser.parse_document ~source_name:path content with
    | Ok nodes -> nodes
    | Error err ->
      failwith ("parse error: " ^ Error.format_parse_error content err)
  in
  let t1 = now () in
  let article =
    match Elaborate.elaborate "bench" nodes with
    | Ok article -> article
    | Error err ->
      failwith ("elab error: " ^ Error.format_elab_error content err)
  in
  let t2 = now () in
  let _html =
    Html.render (Render.render_blocks Render.empty_ctx article.Document.art_body)
  in
  let t3 = now () in
  let words1 = allocated_words () in
  { parse_s = t1 -. t0
  ; elab_s = t2 -. t1
  ; render_s = t3 -. t2
  ; total_s = t3 -. t0
  ; words = words1 -. words0
  }

let mean f xs =
  List.fold_left (fun acc x -> acc +. f x) 0.0 xs /. float_of_int (List.length xs)

let print_report path samples =
  let ms x = x *. 1000.0 in
  let parse_ms = mean (fun s -> s.parse_s) samples |> ms in
  let elab_ms = mean (fun s -> s.elab_s) samples |> ms in
  let render_ms = mean (fun s -> s.render_s) samples |> ms in
  let total_ms = mean (fun s -> s.total_s) samples |> ms in
  let words = mean (fun s -> s.words) samples in
  Printf.printf "%s\n" path;
  Printf.printf "  parse : %.3f ms\n" parse_ms;
  Printf.printf "  elab  : %.3f ms\n" elab_ms;
  Printf.printf "  render: %.3f ms\n" render_ms;
  Printf.printf "  total : %.3f ms\n" total_ms;
  Printf.printf "  alloc : %.0f words\n" words;
  print_endline ""

let benchmark_file iterations path =
  let content = read_file path in
  let rec loop acc n =
    if n = 0 then List.rev acc
    else loop (run_once path content :: acc) (n - 1)
  in
  print_report path (loop [] iterations)

let () =
  match Array.to_list Sys.argv with
  | _ :: iterations :: files ->
    (match int_of_string_opt iterations with
     | Some n when n > 0 ->
       List.iter (benchmark_file n) files
     | _ -> usage ())
  | _ -> usage ()
