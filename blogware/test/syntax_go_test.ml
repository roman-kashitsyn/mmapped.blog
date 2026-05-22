open Blogware
open Test_framework
open Document

let txt = Text.of_string
let s x = Str (txt x)

let role_name = function
  | Hl_keyword -> "kw"
  | Hl_defun -> "defun"
  | Hl_string -> "str"
  | Hl_comment -> "comment"
  | Hl_variable -> "var"
  | Hl_typedef -> "typedef"
  | Hl_identifier -> "id"

let rec dump_inline = function
  | Str t -> Text.to_string t
  | Highlighted (role, body) ->
      "<" ^ role_name role ^ ":" ^ dump_inlines body ^ ">"
  | Small_caps body -> "{sc:" ^ dump_inlines body ^ "}"
  | Anchor id -> "{anchor:" ^ Text.to_string id ^ "}"
  | Link (url, body) ->
      "{link:" ^ Text.to_string url ^ ":" ^ dump_inlines body ^ "}"
  | _ -> "{inline}"

and dump_inlines inlines = String.concat "" (List.map dump_inline inlines)

let dump_highlighted source = Syntax_go.highlight [ s source ] |> dump_inlines

let h name source expected =
  test name (fun () -> assert_equal_string expected (dump_highlighted source))

let tests : Test_framework.t list =
  group "syntax_go"
    [
      h "keywords identifiers strings comments"
        "package main\n// hi\nvar msg = \"ok\"\n"
        "<kw:package> <id:main>\n\
         <comment:// hi>\n\
         <kw:var> <var:msg> = <str:\"ok\">\n";
      h "malformed string and block comment recover" "\"unterminated\n/* block"
        "<str:\"unterminated>\n<comment:/* block>";
      h "function definition parameters and body ids"
        "func add(x, y int) int { return x + y }"
        "<kw:func> <defun:add>(<var:x>, <var:y> <id:int>) <id:int> { \
         <kw:return> <id:x> + <id:y> }";
      h "method receiver and named returns"
        "func (s *Server) Serve(ctx context.Context) (n int, err error) { \
         return }"
        "<kw:func> (<var:s> *<id:Server>) <defun:Serve>(<var:ctx> \
         <id:context>.<id:Context>) (<var:n> <id:int>, <var:err> <id:error>) { \
         <kw:return> }";
      h "var const blocks and short declarations"
        "const (\nPi = 3\nTau = 6\n)\nvar a, b int\nx, ok := m[k]\n"
        "<kw:const> (\n\
         <var:Pi> = 3\n\
         <var:Tau> = 6\n\
         )\n\
         <kw:var> <var:a>, <var:b> <id:int>\n\
         <var:x>, <var:ok> := <id:m>[<id:k>]\n";
      h "type definitions and aliases"
        "type Server struct{}\n\
         type Alias = string\n\
         type (\n\
         ID int\n\
         Pair struct{}\n\
         )\n"
        "<kw:type> <typedef:Server> <kw:struct>{}\n\
         <kw:type> <typedef:Alias> = <id:string>\n\
         <kw:type> (\n\
         <typedef:ID> <id:int>\n\
         <typedef:Pair> <kw:struct>{}\n\
         )\n";
      test "line comment spans tex commands" (fun () ->
          let input =
            [ s "// Hello "; Small_caps [ s "cruel" ]; s " world!\nvar x int" ]
          in
          assert_equal_string
            "<comment:// Hello {sc:cruel} world!>\n<kw:var> <var:x> <id:int>"
            (dump_inlines (Syntax_go.highlight input)));
      test "non-string inlines are preserved" (fun () ->
          let input = [ s "func "; Anchor (txt "code-label"); s "main()" ] in
          match Syntax_go.highlight input with
          | [
           Highlighted (Hl_keyword, [ Str func_ ]);
           Str space;
           Anchor id;
           Highlighted (Hl_identifier, [ Str main ]);
           Str parens;
          ]
            when Text.equal_string func_ "func"
                 && Text.equal_string space " "
                 && Text.equal_string id "code-label"
                 && Text.equal_string main "main"
                 && Text.equal_string parens "()" ->
              Pass
          | actual -> Fail ("unexpected inlines: " ^ dump_inlines actual));
    ]
