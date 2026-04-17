(* Blogware OCaml port — test runner. Tests grow per translation phase.

   Usage: test_main [-verbose]
*)

open Blogware

let all_tests : Test_framework.t list =
  List.concat
    [
      Html_test.tests;
      Parser_test.tests;
      Math_test.tests;
      Render_test.tests;
      Render_mathml_test.tests;
      Elaborate_test.tests;
      Feed_test.tests;
      Layout_test.tests;
      Server_test.tests;
      Strings_test.tests;
      Pipeline_test.tests;
    ]

let () =
  let verbose = Array.to_list Sys.argv |> List.mem "-verbose" in
  exit (Test_framework.run_tests ~verbose all_tests)
