open Blogware

let ( // ) = Filename.concat

module StringSet = Set.Make (String)

let rec find_source_root dir =
  if Sys.file_exists (dir // "dune-project") then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else find_source_root parent

let source_root () =
  match find_source_root (Sys.getcwd ()) with
  | Some root -> root
  | None -> Sys.getcwd ()

let excluded_snapshots =
  StringSet.of_list [ "feed.xml"; "index.html"; "posts.html" ]

let snapshot_root () = source_root () // "blogware" // "test" // "snapshots"
let input_root () = source_root ()
let is_directory path = try Sys.is_directory path with Sys_error _ -> false

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let len = in_channel_length ic in
      really_input_string ic len)

let write_file path content =
  let oc = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out oc)
    (fun () -> output_string oc content)

let rec mkdir_p path =
  if path = "" || path = "." || is_directory path then ()
  else begin
    let parent = Filename.dirname path in
    if parent <> path then mkdir_p parent;
    try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let list_dir path =
  try Array.to_list (Sys.readdir path) with Sys_error _ -> []

let rec remove_tree path =
  if is_directory path then begin
    List.iter (fun entry -> remove_tree (path // entry)) (list_dir path);
    Unix.rmdir path
  end
  else if Sys.file_exists path then Sys.remove path

let list_files_recursive root =
  if not (is_directory root) then []
  else
    let rec go dir =
      List.concat
        (List.map
           (fun entry ->
             let path = dir // entry in
             if is_directory path then go path else [ path ])
           (list_dir dir))
    in
    go root

let with_silenced_stderr f =
  flush stderr;
  let saved = Unix.dup Unix.stderr in
  let dev_null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
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
  match Strings.strip_prefix ~prefix path with
  | Some rest -> rest
  | None -> path

let existing_snapshot_paths root =
  list_files_recursive root
  |> List.map (relative_to ~root)
  |> List.sort String.compare

let included_snapshot_path rel = not (StringSet.mem rel excluded_snapshots)

let update_snapshots expected actual_map =
  let root = snapshot_root () in
  mkdir_p root;
  List.iter
    (fun rel ->
      match List.assoc_opt rel actual_map with
      | None -> ()
      | Some content ->
          let dst = root // rel in
          mkdir_p (Filename.dirname dst);
          write_file dst content)
    expected;
  let expected_set =
    List.fold_left
      (fun acc rel -> StringSet.add rel acc)
      StringSet.empty expected
  in
  existing_snapshot_paths root
  |> List.iter (fun rel ->
      if not (StringSet.mem rel expected_set) then remove_tree (root // rel))

let rendered_outputs input_root =
  with_silenced_stderr (fun () ->
      Site.rendered_outputs
        {
          Site.site_input = input_root;
          site_output = "";
          site_root = "https://mmapped.blog";
        })

type diff_op = Same of string | Remove of string | Add of string

let line_diff expected actual =
  let a = Array.of_list (String.split_on_char '\n' expected) in
  let b = Array.of_list (String.split_on_char '\n' actual) in
  let m = Array.length a in
  let n = Array.length b in
  let dp = Array.make_matrix (m + 1) (n + 1) 0 in
  for i = m - 1 downto 0 do
    for j = n - 1 downto 0 do
      dp.(i).(j) <-
        (if String.equal a.(i) b.(j) then 1 + dp.(i + 1).(j + 1)
         else max dp.(i + 1).(j) dp.(i).(j + 1))
    done
  done;
  let rec build acc i j =
    if i < m && j < n && String.equal a.(i) b.(j) then
      build (Same a.(i) :: acc) (i + 1) (j + 1)
    else if i < m && (j = n || dp.(i + 1).(j) >= dp.(i).(j + 1)) then
      build (Remove a.(i) :: acc) (i + 1) j
    else if j < n then build (Add b.(j) :: acc) i (j + 1)
    else List.rev acc
  in
  build [] 0 0

let unified_diff expected actual =
  let context = 3 in
  let ops = Array.of_list (line_diff expected actual) in
  let len = Array.length ops in
  let change_indices =
    let rec go acc i =
      if i = len then List.rev acc
      else
        match ops.(i) with
        | Same _ -> go acc (i + 1)
        | Remove _ | Add _ -> go (i :: acc) (i + 1)
    in
    go [] 0
  in
  let old_before = Array.make len 0 in
  let new_before = Array.make len 0 in
  let old_line = ref 0 in
  let new_line = ref 0 in
  Array.iteri
    (fun i op ->
      old_before.(i) <- !old_line;
      new_before.(i) <- !new_line;
      match op with
      | Same _ ->
          incr old_line;
          incr new_line
      | Remove _ -> incr old_line
      | Add _ -> incr new_line)
    ops;
  let hunks =
    let rec go acc current = function
      | [] -> (
          match current with
          | None -> List.rev acc
          | Some h -> List.rev (h :: acc))
      | i :: rest ->
          let hunk_start = max 0 (i - context) in
          let hunk_end = min (len - 1) (i + context) in
          begin match current with
          | None -> go acc (Some (hunk_start, hunk_end)) rest
          | Some (start, stop) ->
              if hunk_start <= stop + 1 then
                go acc (Some (start, max stop hunk_end)) rest
              else go ((start, stop) :: acc) (Some (hunk_start, hunk_end)) rest
          end
    in
    go [] None change_indices
  in
  let old_count start stop =
    let n = ref 0 in
    for i = start to stop do
      match ops.(i) with Same _ | Remove _ -> incr n | Add _ -> ()
    done;
    !n
  in
  let new_count start stop =
    let n = ref 0 in
    for i = start to stop do
      match ops.(i) with Same _ | Add _ -> incr n | Remove _ -> ()
    done;
    !n
  in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf "Diff (-expected +actual):\n";
  Buffer.add_string buf "--- expected\n";
  Buffer.add_string buf "+++ actual\n";
  List.iter
    (fun (start, stop) ->
      let old_count = old_count start stop in
      let new_count = new_count start stop in
      let old_start =
        if old_count = 0 then old_before.(start) else old_before.(start) + 1
      in
      let new_start =
        if new_count = 0 then new_before.(start) else new_before.(start) + 1
      in
      Buffer.add_string buf
        (Printf.sprintf "@@ -%d,%d +%d,%d @@\n" old_start old_count new_start
           new_count);
      for i = start to stop do
        match ops.(i) with
        | Same line ->
            Buffer.add_char buf ' ';
            Buffer.add_string buf line;
            Buffer.add_char buf '\n'
        | Remove line ->
            Buffer.add_char buf '-';
            Buffer.add_string buf line;
            Buffer.add_char buf '\n'
        | Add line ->
            Buffer.add_char buf '+';
            Buffer.add_string buf line;
            Buffer.add_char buf '\n'
      done)
    hunks;
  Buffer.contents buf

let compare_snapshot actual_map rel =
  let snapshot_path = snapshot_root () // rel in
  match List.assoc_opt rel actual_map with
  | None -> Test_framework.Fail ("missing rendered output: " ^ rel)
  | Some actual ->
      if not (Sys.file_exists snapshot_path) then
        Test_framework.Fail ("missing snapshot: " ^ rel)
      else
        let expected = read_file snapshot_path in
        if String.equal expected actual then Test_framework.Pass
        else Test_framework.Fail (unified_diff expected actual)

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
    List.map
      (fun rel ->
        Test_framework.test ("snapshots/" ^ rel) (fun () ->
            compare_snapshot actual_map rel))
      expected
  in
  no_extra_snapshots_test expected :: file_tests

let () =
  let input_root = input_root () in
  match
    (Site.generated_output_paths input_root, rendered_outputs input_root)
  with
  | Ok expected, Ok actual_map ->
      let expected = List.filter included_snapshot_path expected in
      let actual_map =
        List.filter (fun (rel, _) -> included_snapshot_path rel) actual_map
      in
      if Sys.getenv_opt "UPDATE_SNAPSHOTS" = Some "1" then
        update_snapshots expected actual_map;
      let exit_code =
        Test_framework.run_tests (snapshot_tests expected actual_map)
      in
      exit exit_code
  | Error err, _ | _, Error err ->
      prerr_endline ("Error: " ^ err);
      exit 1
