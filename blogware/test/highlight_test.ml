open Blogware
open Test_framework
open Document

let txt = Text.of_string
let s x = Str (txt x)

let tests : Test_framework.t list =
  group "highlight"
    [
      test "unknown language remains unchanged" (fun () ->
          match
            Highlight.highlight
              ~classes:[ txt "python" ]
              ~content:[ s "func main() {}" ]
          with
          | [ Str t ] -> assert_equal_string "func main() {}" (Text.to_string t)
          | _ -> Fail "expected unchanged string");
      test "language matching is exact" (fun () ->
          match
            Highlight.highlight
              ~classes:[ txt "golang" ]
              ~content:[ s "func main() {}" ]
          with
          | [ Str t ] -> assert_equal_string "func main() {}" (Text.to_string t)
          | _ -> Fail "expected unchanged string");
      test "language can appear among other code classes" (fun () ->
          match
            Highlight.highlight
              ~classes:[ txt "source"; txt "go" ]
              ~content:[ s "func main() {}" ]
          with
          | [
           Highlighted (Hl_keyword, [ Str func_ ]);
           Str space;
           Highlighted (Hl_defun, [ Str main ]);
           Str parens;
          ]
            when Text.equal_string func_ "func"
                 && Text.equal_string space " "
                 && Text.equal_string main "main"
                 && Text.equal_string parens "() {}" ->
              Pass
          | _ -> Fail "expected go highlighting");
      test "highlight spans do not cross newlines" (fun () ->
          match
            Highlight.highlight
              ~classes:[ txt "go" ]
              ~content:[ s "// a\n// b" ]
          with
          | [
           Highlighted (Hl_comment, [ Str a ]);
           Str nl;
           Highlighted (Hl_comment, [ Str b ]);
          ]
            when Text.equal_string a "// a" && Text.equal_string nl "\n"
                 && Text.equal_string b "// b" ->
              Pass
          | _ -> Fail "expected separate comment spans");
    ]
