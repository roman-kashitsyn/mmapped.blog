open Blogware

let ( // ) = Filename.concat

module StringSet = Set.Make(String)

let source_root () = Sys.getcwd ()

let snapshot_root () =
  source_root () // "blogware" // "test" // "snapshots"

let input_root () =
  source_root ()

let is_directory path =
  try Sys.is_directory path with Sys_error _ -> false

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () ->
       let len = in_channel_length ic in
       really_input_string ic len)

let write_file path content =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc)
    (fun () -> output_string oc content)

let rec mkdir_p path =
  if path = "" || path = "." || is_directory path then ()
  else begin
    let parent = Filename.dirname path in
    if parent <> path then mkdir_p parent;
    try Unix.mkdir path 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let list_dir path =
  try Array.to_list (Sys.readdir path) with Sys_error _ -> []

let rec remove_tree path =
  if is_directory path then begin
    List.iter (fun entry -> remove_tree (path // entry)) (list_dir path);
    Unix.rmdir path
  end else if Sys.file_exists path then
    Sys.remove path

let list_files_recursive root =
  if not (is_directory root) then []
  else
    let rec go dir =
      List.concat
        (List.map (fun entry ->
           let path = dir // entry in
           if is_directory path then go path else [path]
         ) (list_dir dir))
    in
    go root

let with_silenced_stderr f =
  flush stderr;
  let saved = Unix.dup Unix.stderr in
  let dev_null = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
  Fun.protect
    ~finally:(fun () ->
      flush stderr;
      Unix.dup2 saved Unix.stderr;
      Unix.close saved;
      Unix.close dev_null)
    (fun () ->
       Unix.dup2 dev_null Unix.stderr;
       f ())

let relative_to ~root path =
  let prefix = root ^ Filename.dir_sep in
  let lp = String.length prefix in
  if String.length path >= lp && String.sub path 0 lp = prefix
  then String.sub path lp (String.length path - lp)
  else path

let existing_snapshot_paths root =
  list_files_recursive root
  |> List.map (relative_to ~root)
  |> List.sort String.compare

let update_snapshots expected actual_map =
  let root = snapshot_root () in
  mkdir_p root;
  List.iter (fun rel ->
    match List.assoc_opt rel actual_map with
    | None -> ()
    | Some content ->
      let dst = root // rel in
      mkdir_p (Filename.dirname dst);
      write_file dst content
  ) expected;
  let expected_set =
    List.fold_left (fun acc rel -> StringSet.add rel acc) StringSet.empty expected
  in
  existing_snapshot_paths root
  |> List.iter (fun rel ->
       if not (StringSet.mem rel expected_set) then
         remove_tree (root // rel))

let rendered_outputs input_root =
  with_silenced_stderr (fun () ->
    Site.rendered_outputs
      { Site.site_input = input_root
      ; site_output = ""
      ; site_root = "https://mmapped.blog"
      })

let compare_snapshot actual_map rel =
  let snapshot_path = snapshot_root () // rel in
  match List.assoc_opt rel actual_map with
  | None -> Test_framework.Fail ("missing rendered output: " ^ rel)
  | Some actual ->
    if not (Sys.file_exists snapshot_path) then
      Test_framework.Fail ("missing snapshot: " ^ rel)
    else
      Test_framework.assert_equal_string (read_file snapshot_path) actual

let set_of_list xs =
  List.fold_left (fun acc x -> StringSet.add x acc) StringSet.empty xs

let no_extra_snapshots_test expected =
  Test_framework.test "snapshots/no extra files" (fun () ->
    let expected = set_of_list expected in
    let extra =
      existing_snapshot_paths (snapshot_root ())
      |> List.filter (fun rel -> not (StringSet.mem rel expected))
    in
    match extra with
    | [] -> Test_framework.Pass
    | xs ->
      Test_framework.Fail
        ("unexpected snapshot files:\n" ^ String.concat "\n" xs))

let snapshot_tests expected actual_map =
  let file_tests =
    List.map (fun rel ->
      Test_framework.test ("snapshots/" ^ rel) (fun () ->
        compare_snapshot actual_map rel)
    ) expected
  in
  no_extra_snapshots_test expected :: file_tests

let () =
  let input_root = input_root () in
  match Site.generated_output_paths input_root, rendered_outputs input_root with
  | Ok expected, Ok actual_map ->
    if Sys.getenv_opt "UPDATE_SNAPSHOTS" = Some "1" then
      update_snapshots expected actual_map;
    let exit_code =
      Test_framework.run_tests (snapshot_tests expected actual_map)
    in
    exit exit_code
  | Error err, _
  | _, Error err ->
    prerr_endline ("Error: " ^ err);
    exit 1
