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

let highlight lang inlines =
  Highlight.highlight ~classes:[ txt lang ] ~content:inlines

let dump_highlighted lang source = highlight lang [ s source ] |> dump_inlines

let h lang name source expected =
  test
    (lang ^ " " ^ name)
    (fun () -> assert_equal_string expected (dump_highlighted lang source))

let go_tests =
  group "syntax_highlight_go"
    [
      h "go" "keywords identifiers strings comments"
        "package main\n// hi\nvar msg = \"ok\"\n"
        "<kw:package> <id:main>\n\
         <comment:// hi>\n\
         <kw:var> <var:msg> = <str:\"ok\">\n";
      h "go" "malformed string and block comment recover"
        "\"unterminated\n/* block" "<str:\"unterminated>\n<comment:/* block>";
      h "go" "function definition parameters and body ids"
        "func add(x, y int) int { return x + y }"
        "<kw:func> <defun:add>(<var:x>, <var:y> <id:int>) <id:int> { \
         <kw:return> <id:x> + <id:y> }";
      h "go" "method receiver and named returns"
        "func (s *Server) Serve(ctx context.Context) (n int, err error) { \
         return }"
        "<kw:func> (<var:s> *<id:Server>) <defun:Serve>(<var:ctx> \
         <id:context>.<id:Context>) (<var:n> <id:int>, <var:err> <id:error>) { \
         <kw:return> }";
      h "go" "function literal parameters"
        "f := func(x int) error { return nil }"
        "<var:f> := <kw:func>(<var:x> <id:int>) <id:error> { <kw:return> \
         <id:nil> }";
      h "go" "var const blocks and short declarations"
        "const (\nPi = 3\nTau = 6\n)\nvar a, b int\nx, ok := m[k]\n"
        "<kw:const> (\n\
         <var:Pi> = 3\n\
         <var:Tau> = 6\n\
         )\n\
         <kw:var> <var:a>, <var:b> <id:int>\n\
         <var:x>, <var:ok> := <id:m>[<id:k>]\n";
      h "go" "declaration block boundaries ignore comparisons"
        "const (\nLess = a < b\nGreater = c > d\n)\n"
        "<kw:const> (\n\
         <var:Less> = <id:a> < <id:b>\n\
         <var:Greater> = <id:c> > <id:d>\n\
         )\n";
      h "go" "type definitions and aliases"
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
      test "go line comment spans tex commands" (fun () ->
          let input =
            [ s "// Hello "; Small_caps [ s "cruel" ]; s " world!\nvar x int" ]
          in
          assert_equal_string
            "<comment:// Hello {sc:cruel} world!>\n<kw:var> <var:x> <id:int>"
            (dump_inlines (highlight "go" input)));
      test "go non-string inlines are preserved" (fun () ->
          let input = [ s "func "; Anchor (txt "code-label"); s "main()" ] in
          match highlight "go" input with
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
      h "go" "method with receiver marks defun and params"
        "func (s *Server) Serve(ctx context.Context) error { return nil }"
        "<kw:func> (<var:s> *<id:Server>) <defun:Serve>(<var:ctx> \
         <id:context>.<id:Context>) <id:error> { <kw:return> <id:nil> }";
      test "go block comment spans inline boundary" (fun () ->
          let input =
            [
              s "/* Hello "; Small_caps [ s "cruel" ]; s " world! */\nvar x int";
            ]
          in
          assert_equal_string
            "<comment:/* Hello {sc:cruel} world! */>\n<kw:var> <var:x> <id:int>"
            (dump_inlines (highlight "go" input)));
      test "go unclosed block comment spans inline boundary" (fun () ->
          let input =
            [ s "/* Hello "; Small_caps [ s "cruel" ]; s " world!\nvar x int" ]
          in
          assert_equal_string
            "<comment:/* Hello {sc:cruel} world!>\n<comment:var x int>"
            (dump_inlines (highlight "go" input)));
    ]

let c_tests =
  group "syntax_highlight_c"
    [
      h "c" "typedefs function definitions parameters and keywords"
        "typedef struct Node Node;\n\
         static inline int add(const int x, int y) { return x + y; }"
        "<kw:typedef> <kw:struct> <typedef:Node> <typedef:Node>;\n\
         <kw:static> <kw:inline> <kw:int> <defun:add>(<kw:const> <kw:int> \
         <var:x>, <kw:int> <var:y>) { <kw:return> <id:x> + <id:y>; }";
      h "c" "function pointer typedef"
        "typedef int (*cmp_t)(const void *a, const void *b);"
        "<kw:typedef> <kw:int> (*<typedef:cmp_t>)(<kw:const> <kw:void> \
         *<id:a>, <kw:const> <kw:void> *<id:b>);";
      h "c" "comments strings and malformed recovery"
        "// hi\nchar c = 'x'; char *s = \"ok\";\n/* block"
        "<comment:// hi>\n\
         <kw:char> <id:c> = <str:'x'>; <kw:char> *<id:s> = <str:\"ok\">;\n\
         <comment:/* block>";
      test "c line comment spans tex commands" (fun () ->
          let input =
            [ s "// Hello "; Small_caps [ s "cruel" ]; s " world!\nint x = 1" ]
          in
          assert_equal_string
            "<comment:// Hello {sc:cruel} world!>\n<kw:int> <id:x> = 1"
            (dump_inlines (highlight "c" input)));
    ]

let rust_tests =
  group "syntax_highlight_rust"
    [
      h "rust" "function definitions parameters and keywords"
        "pub fn add(x: i32, mut y: i32) -> i32 { return x + y; }"
        "<kw:pub> <kw:fn> <defun:add>(<var:x>: <id:i32>, <kw:mut> <var:y>: \
         <id:i32>) -> <id:i32> { <kw:return> <id:x> + <id:y>; }";
      h "rust" "function generics"
        "fn first<T: Ord>(left: T, right: T) -> T { left }"
        "<kw:fn> <defun:first><<id:T>: <id:Ord>>(<var:left>: <id:T>, \
         <var:right>: <id:T>) -> <id:T> { <id:left> }";
      h "rust" "generic parameter types with commas"
        "fn sum(map: StableBTreeMap<(Principal, Subaccount), Tokens>, owner: \
         Principal) {}"
        "<kw:fn> <defun:sum>(<var:map>: <id:StableBTreeMap><(<id:Principal>, \
         <id:Subaccount>), <id:Tokens>>, <var:owner>: <id:Principal>) {}";
      h "rust" "type declarations and let bindings"
        "struct Server<T> { value: T }\n\
         enum State { Ready }\n\
         type Id = u64;\n\
         let mut id = 1;"
        "<kw:struct> <typedef:Server><<id:T>> { <id:value>: <id:T> }\n\
         <kw:enum> <typedef:State> { <id:Ready> }\n\
         <kw:type> <typedef:Id> = <id:u64>;\n\
         <kw:let> <kw:mut> <var:id> = 1;";
      h "rust" "comments strings and malformed recovery"
        "\"unterminated\n/* block" "<str:\"unterminated>\n<comment:/* block>";
      test "rust line comment spans tex commands" (fun () ->
          let input =
            [ s "// Hello "; Small_caps [ s "cruel" ]; s " world!\nlet x = 1" ]
          in
          assert_equal_string
            "<comment:// Hello {sc:cruel} world!>\n<kw:let> <var:x> = 1"
            (dump_inlines (highlight "rust" input)));
    ]

let ocaml_tests =
  group "syntax_highlight_ocaml"
    [
      h "ocaml" "let function definitions and value bindings"
        "let rec map f xs = match xs with [] -> []\nlet answer = 42"
        "<kw:let> <kw:rec> <defun:map> <id:f> <id:xs> = <kw:match> <id:xs> \
         <kw:with> [] -> []\n\
         <kw:let> <var:answer> = 42";
      h "ocaml" "tuple bindings and mutually recursive definitions"
        "let n, m = pair\nlet value : int = 1\nlet rec f x = x\nand g y = y"
        "<kw:let> <var:n>, <var:m> = <id:pair>\n\
         <kw:let> <var:value> : <id:int> = 1\n\
         <kw:let> <kw:rec> <defun:f> <id:x> = <id:x>\n\
         <kw:and> <defun:g> <id:y> = <id:y>";
      h "ocaml" "type declarations strings comments"
        "type server = { port : int }\nlet name = \"api\"\n(* hello *)"
        "<kw:type> <typedef:server> = { <id:port> : <id:int> }\n\
         <kw:let> <var:name> = <str:\"api\">\n\
         <comment:(* hello *)>";
      h "ocaml" "malformed string and block comment recover"
        "\"unterminated\n(* block" "<str:\"unterminated>\n<comment:(* block>";
      test "ocaml block comment spans tex commands" (fun () ->
          let input =
            [
              s "(* Hello "; Small_caps [ s "cruel" ]; s " world! *)\nlet x = 1";
            ]
          in
          assert_equal_string
            "<comment:(* Hello {sc:cruel} world! *)>\n<kw:let> <var:x> = 1"
            (dump_inlines (highlight "ocaml" input)));
      test "ocaml unclosed block comment spans inline boundary" (fun () ->
          let input =
            [ s "(* Hello "; Small_caps [ s "cruel" ]; s " world!\nlet x = 1" ]
          in
          assert_equal_string
            "<comment:(* Hello {sc:cruel} world!>\n<comment:let x = 1>"
            (dump_inlines (highlight "ocaml" input)));
    ]

let routing_tests =
  group "syntax_highlight_routing"
    [
      test "code content is dispatched by class" (fun () ->
          assert_equal_string "<kw:int> <defun:main>() {}"
            (dump_inlines
               (Highlight.highlight
                  ~classes:[ txt "c" ]
                  ~content:[ s "int main() {}" ])));
      test "unknown code class remains unchanged" (fun () ->
          assert_equal_string "int main() {}"
            (dump_inlines
               (Highlight.highlight
                  ~classes:[ txt "python" ]
                  ~content:[ s "int main() {}" ])));
    ]

let tests : Test_framework.t list =
  List.concat [ go_tests; c_tests; rust_tests; ocaml_tests; routing_tests ]
