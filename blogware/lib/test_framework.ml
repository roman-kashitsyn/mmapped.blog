(* Tiny test framework.

   Reporting:
   - quiet on success: only a single summary line;
   - on failure: one line per failing test plus a summary;
   - no ANSI colors.

   The check type is [check = Pass | Fail of string] (not [result]) so it
   doesn't collide with [Stdlib.result] in callers. *)

type check = Pass | Fail of string

type t = { name : string; run : unit -> check }

let test (name : string) (action : unit -> check) : t =
  { name; run = action }

(* Prefix a list of tests with [group_name ^ "/"]. *)
let group (group_name : string) (tests : t list) : t list =
  List.map
    (fun tc -> { tc with name = group_name ^ "/" ^ tc.name })
    tests

(* --- Assertions --- *)

let assert_equal ~show expected actual : check =
  if expected = actual then Pass
  else
    Fail
      (Printf.sprintf "Expected:\n  %s\nGot:\n  %s"
         (show expected) (show actual))

let assert_equal_string (expected : string) (actual : string) : check =
  if expected = actual then Pass
  else
    Fail
      (Printf.sprintf "Expected:\n  %S\nGot:\n  %S" expected actual)

let assert_equal_int (expected : int) (actual : int) : check =
  if expected = actual then Pass
  else Fail (Printf.sprintf "Expected %d, got %d" expected actual)

let assert_bool (what : string) (b : bool) : check =
  if b then Pass else Fail ("assertion failed: " ^ what)

let assert_ok (r : ('a, 'e) Stdlib.result) (k : 'a -> check) : check =
  match r with
  | Ok x -> k x
  | Error _ -> Fail "expected Ok, got Error"

let assert_error (r : ('a, 'e) Stdlib.result) (k : 'e -> check) : check =
  match r with
  | Error e -> k e
  | Ok _ -> Fail "expected Error, got Ok"

(* --- Runner --- *)

(* Run a single test, optionally printing verbose output. Returns (result, elapsed_time). *)
let run_one ~verbose tc =
  let start = Unix.gettimeofday () in
  let r =
    try tc.run ()
    with e -> Fail (Printf.sprintf "exception: %s" (Printexc.to_string e))
  in
  let elapsed = Unix.gettimeofday () -. start in
  if verbose then begin
    match r with
    | Pass -> Printf.printf "PASS - %s (%.3fs)\n" tc.name elapsed
    | Fail _ -> Printf.printf "FAIL - %s (%.3fs)\n" tc.name elapsed
  end;
  (r, elapsed)

(* Run all tests, print a summary to stdout, return exit code (0 or 1). *)
let run_tests ?(verbose = false) (tests : t list) : int =
  let failures = ref [] in
  let passed = ref 0 in
  List.iter (fun tc ->
    let r, _elapsed = run_one ~verbose tc in
    match r with
    | Pass -> incr passed
    | Fail msg ->
      failures := (tc.name, msg) :: !failures
  ) tests;
  let failed = List.length !failures in
  let passed_n = !passed in
  if failed = 0 then begin
    Printf.printf "ok - %d tests passed\n" passed_n;
    0
  end else begin
    (* In non-verbose mode, show failing tests with details *)
    if not verbose then begin
      List.iter (fun (name, msg) ->
        Printf.printf "FAIL - %s\n" name;
        List.iter (fun line -> Printf.printf "    %s\n" line)
          (String.split_on_char '\n' msg)
      ) (List.rev !failures)
    end;
    Printf.printf "fail - %d tests failed, %d tests passed\n" failed passed_n;
    1
  end
