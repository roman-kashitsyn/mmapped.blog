(* Server tests. Focused on the pure request/response helpers; the
   accept loop is covered indirectly by the pipeline tests. *)

open Blogware
open Test_framework

let tests : Test_framework.t list =
  group "server"
    [
      test "parse_request_line GET /" (fun () ->
          let m, p =
            Server.parse_request_line "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
          in
          if m = "GET" && p = "/" then Pass
          else Fail (Printf.sprintf "got (%s, %s)" m p));
      test "parse_request_line strips \\r" (fun () ->
          let m, p = Server.parse_request_line "GET /posts.html HTTP/1.1\r\n" in
          if m = "GET" && p = "/posts.html" then Pass
          else Fail (Printf.sprintf "got (%s, %s)" m p));
      test "parse_request_line POST" (fun () ->
          let m, _ = Server.parse_request_line "POST /x HTTP/1.1\r\n" in
          if m = "POST" then Pass else Fail m);
      test "content_type_for css" (fun () ->
          assert_equal_string "text/css; charset=utf-8"
            (Server.content_type_for "/css/main.css"));
      test "content_type_for png" (fun () ->
          assert_equal_string "image/png"
            (Server.content_type_for "/images/x.png"));
      test "content_type_for unknown" (fun () ->
          assert_equal_string "application/octet-stream"
            (Server.content_type_for "/x.bin"));
      test "status_text known" (fun () ->
          assert_equal_string "Not Found" (Server.status_text 404));
      test "build_response has status line" (fun () ->
          let r = Server.build_response 200 "text/plain" "hi" in
          if String.starts_with ~prefix:"HTTP/1.1 200 OK" r then Pass
          else Fail r);
      test "build_response has content-length" (fun () ->
          let r = Server.build_response 200 "text/plain" "hello" in
          assert_bool "content-length: 5"
            (Strings.is_infix_of "Content-Length: 5" r));
    ]
