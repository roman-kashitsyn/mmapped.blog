open Blogware
open Test_framework

let tests : Test_framework.t list =
  group "strings"
    [
      test "split_on supports long separators" (fun () ->
          assert_equal
            ~show:(fun xs -> "[" ^ String.concat "; " xs ^ "]")
            [ "a"; "b"; "c" ]
            (Strings.split_on "a<->b<->c" "<->"));
      test "split_on keeps unmatched tail" (fun () ->
          assert_equal
            ~show:(fun xs -> "[" ^ String.concat "; " xs ^ "]")
            [ "abc" ]
            (Strings.split_on "abc" "<->"));
      test "split_on empty separator is identity" (fun () ->
          assert_equal
            ~show:(fun xs -> "[" ^ String.concat "; " xs ^ "]")
            [ "abc" ]
            (Strings.split_on "abc" ""));
    ]
