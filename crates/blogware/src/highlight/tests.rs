use super::*;

fn s(text: &str) -> Inline {
    Inline::Str(text.to_string())
}

fn role_name(role: Role) -> &'static str {
    match role {
        Role::Keyword => "kw",
        Role::Defun => "defun",
        Role::String => "str",
        Role::Comment => "comment",
        Role::Variable => "var",
        Role::Typedef => "typedef",
        Role::Identifier => "id",
    }
}

/// A compact view of highlighted inlines: `<role:text>` for a span.
fn dump(inlines: &[Inline]) -> String {
    inlines
        .iter()
        .map(|inline| match inline {
            Inline::Str(text) => text.clone(),
            Inline::Highlighted(role, body) => format!("<{}:{}>", role_name(*role), dump(body)),
            Inline::SmallCaps(body) => format!("{{sc:{}}}", dump(body)),
            Inline::Anchor(id) => format!("{{anchor:{id}}}"),
            Inline::Link { url, body } => format!("{{link:{url}:{}}}", dump(body)),
            _ => "{inline}".to_string(),
        })
        .collect()
}

fn highlighted(language: &str, content: Vec<Inline>) -> String {
    dump(&highlight(&[language.to_string()], content))
}

#[track_caller]
fn check(language: &str, source: &str, expected: &str) {
    assert_eq!(highlighted(language, vec![s(source)]), expected, "{source}");
}

// ---------------------------------------------------------------- routing

#[test]
fn unknown_language_remains_unchanged() {
    let content = vec![s("func main() {}")];
    assert_eq!(highlight(&["python".to_string()], content.clone()), content);
    // Matching is exact.
    assert_eq!(highlight(&["golang".to_string()], content.clone()), content);
}

#[test]
fn language_can_appear_among_other_classes() {
    let classes = ["source".to_string(), "go".to_string()];
    assert_eq!(
        highlight(&classes, vec![s("func main() {}")]),
        [
            Inline::Highlighted(Role::Keyword, vec![s("func")]),
            s(" "),
            Inline::Highlighted(Role::Defun, vec![s("main")]),
            s("() {}"),
        ]
    );
}

#[test]
fn spans_do_not_cross_newlines() {
    assert_eq!(
        highlight(&["go".to_string()], vec![s("// a\n// b")]),
        [
            Inline::Highlighted(Role::Comment, vec![s("// a")]),
            s("\n"),
            Inline::Highlighted(Role::Comment, vec![s("// b")]),
        ]
    );
}

// --------------------------------------------------------------------- go

#[test]
fn go_keywords_identifiers_strings_comments() {
    check(
        "go",
        "package main\n// hi\nvar msg = \"ok\"\n",
        "<kw:package> <id:main>\n<comment:// hi>\n<kw:var> <var:msg> = <str:\"ok\">\n",
    );
}

#[test]
fn go_malformed_string_and_block_comment_recover() {
    check(
        "go",
        "\"unterminated\n/* block",
        "<str:\"unterminated>\n<comment:/* block>",
    );
}

#[test]
fn go_functions() {
    check(
        "go",
        "func add(x, y int) int { return x + y }",
        "<kw:func> <defun:add>(<var:x>, <var:y> <id:int>) <id:int> { <kw:return> <id:x> + <id:y> }",
    );
    check(
        "go",
        "func (s *Server) Serve(ctx context.Context) (n int, err error) { return }",
        "<kw:func> (<var:s> *<id:Server>) <defun:Serve>(<var:ctx> <id:context>.<id:Context>) \
         (<var:n> <id:int>, <var:err> <id:error>) { <kw:return> }",
    );
    check(
        "go",
        "f := func(x int) error { return nil }",
        "<var:f> := <kw:func>(<var:x> <id:int>) <id:error> { <kw:return> <id:nil> }",
    );
    check(
        "go",
        "func (s *Server) Serve(ctx context.Context) error { return nil }",
        "<kw:func> (<var:s> *<id:Server>) <defun:Serve>(<var:ctx> <id:context>.<id:Context>) \
         <id:error> { <kw:return> <id:nil> }",
    );
}

#[test]
fn go_declarations() {
    check(
        "go",
        "const (\nPi = 3\nTau = 6\n)\nvar a, b int\nx, ok := m[k]\n",
        "<kw:const> (\n<var:Pi> = 3\n<var:Tau> = 6\n)\n<kw:var> <var:a>, <var:b> <id:int>\n\
         <var:x>, <var:ok> := <id:m>[<id:k>]\n",
    );
    check(
        "go",
        "const (\nLess = a < b\nGreater = c > d\n)\n",
        "<kw:const> (\n<var:Less> = <id:a> < <id:b>\n<var:Greater> = <id:c> > <id:d>\n)\n",
    );
    check(
        "go",
        "type Server struct{}\ntype Alias = string\ntype (\nID int\nPair struct{}\n)\n",
        "<kw:type> <typedef:Server> <kw:struct>{}\n<kw:type> <typedef:Alias> = <id:string>\n\
         <kw:type> (\n<typedef:ID> <id:int>\n<typedef:Pair> <kw:struct>{}\n)\n",
    );
    // A short declaration at the very start of the listing.
    check("go", "x := 1", "<var:x> := 1");
    check("go", ":= 1", ":= 1");
}

#[test]
fn go_comments_span_inlines() {
    assert_eq!(
        highlighted(
            "go",
            vec![
                s("// Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world!\nvar x int")
            ]
        ),
        "<comment:// Hello {sc:cruel} world!>\n<kw:var> <var:x> <id:int>"
    );
    assert_eq!(
        highlighted(
            "go",
            vec![
                s("/* Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world! */\nvar x int")
            ]
        ),
        "<comment:/* Hello {sc:cruel} world! */>\n<kw:var> <var:x> <id:int>"
    );
    assert_eq!(
        highlighted(
            "go",
            vec![
                s("/* Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world!\nvar x int")
            ]
        ),
        "<comment:/* Hello {sc:cruel} world!>\n<comment:var x int>"
    );
}

#[test]
fn go_other_inlines_are_preserved() {
    assert_eq!(
        highlight(
            &["go".to_string()],
            vec![
                s("func "),
                Inline::Anchor("code-label".to_string()),
                s("main()")
            ]
        ),
        [
            Inline::Highlighted(Role::Keyword, vec![s("func")]),
            s(" "),
            Inline::Anchor("code-label".to_string()),
            Inline::Highlighted(Role::Identifier, vec![s("main")]),
            s("()"),
        ]
    );
}

// ---------------------------------------------------------------------- c

#[test]
fn c_definitions() {
    check(
        "c",
        "typedef struct Node Node;\nstatic inline int add(const int x, int y) { return x + y; }",
        "<kw:typedef> <kw:struct> <typedef:Node> <typedef:Node>;\n<kw:static> <kw:inline> \
         <kw:int> <defun:add>(<kw:const> <kw:int> <var:x>, <kw:int> <var:y>) { <kw:return> \
         <id:x> + <id:y>; }",
    );
    check(
        "c",
        "typedef int (*cmp_t)(const void *a, const void *b);",
        "<kw:typedef> <kw:int> (*<typedef:cmp_t>)(<kw:const> <kw:void> *<id:a>, <kw:const> \
         <kw:void> *<id:b>);",
    );
    check("c", "int main() {}", "<kw:int> <defun:main>() {}");
}

#[test]
fn c_comments_strings_and_recovery() {
    check(
        "c",
        "// hi\nchar c = 'x'; char *s = \"ok\";\n/* block",
        "<comment:// hi>\n<kw:char> <id:c> = <str:'x'>; <kw:char> *<id:s> = <str:\"ok\">;\n\
         <comment:/* block>",
    );
    assert_eq!(
        highlighted(
            "c",
            vec![
                s("// Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world!\nint x = 1")
            ]
        ),
        "<comment:// Hello {sc:cruel} world!>\n<kw:int> <id:x> = 1"
    );
}

// ------------------------------------------------------------------- rust

#[test]
fn rust_definitions() {
    check(
        "rust",
        "pub fn add(x: i32, mut y: i32) -> i32 { return x + y; }",
        "<kw:pub> <kw:fn> <defun:add>(<var:x>: <id:i32>, <kw:mut> <var:y>: <id:i32>) -> <id:i32> \
         { <kw:return> <id:x> + <id:y>; }",
    );
    check(
        "rust",
        "fn first<T: Ord>(left: T, right: T) -> T { left }",
        "<kw:fn> <defun:first><<id:T>: <id:Ord>>(<var:left>: <id:T>, <var:right>: <id:T>) -> \
         <id:T> { <id:left> }",
    );
    check(
        "rust",
        "fn sum(map: StableBTreeMap<(Principal, Subaccount), Tokens>, owner: Principal) {}",
        "<kw:fn> <defun:sum>(<var:map>: <id:StableBTreeMap><(<id:Principal>, <id:Subaccount>), \
         <id:Tokens>>, <var:owner>: <id:Principal>) {}",
    );
    check(
        "rust",
        "struct Server<T> { value: T }\nenum State { Ready }\ntype Id = u64;\nlet mut id = 1;",
        "<kw:struct> <typedef:Server><<id:T>> { <id:value>: <id:T> }\n<kw:enum> \
         <typedef:State> { <id:Ready> }\n<kw:type> <typedef:Id> = <id:u64>;\n<kw:let> \
         <kw:mut> <var:id> = 1;",
    );
}

#[test]
fn rust_comments_strings_and_recovery() {
    check(
        "rust",
        "\"unterminated\n/* block",
        "<str:\"unterminated>\n<comment:/* block>",
    );
    check("rust", "\"a\\\"b\" 'c'", "<str:\"a\\\"b\"> '<id:c>'");
    assert_eq!(
        highlighted(
            "rust",
            vec![
                s("// Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world!\nlet x = 1")
            ]
        ),
        "<comment:// Hello {sc:cruel} world!>\n<kw:let> <var:x> = 1"
    );
}

// ------------------------------------------------------------------ ocaml

#[test]
fn ocaml_bindings() {
    check(
        "ocaml",
        "let rec map f xs = match xs with [] -> []\nlet answer = 42",
        "<kw:let> <kw:rec> <defun:map> <id:f> <id:xs> = <kw:match> <id:xs> <kw:with> [] -> []\n\
         <kw:let> <var:answer> = 42",
    );
    check(
        "ocaml",
        "let n, m = pair\nlet value : int = 1\nlet rec f x = x\nand g y = y",
        "<kw:let> <var:n>, <var:m> = <id:pair>\n<kw:let> <var:value> : <id:int> = 1\n<kw:let> \
         <kw:rec> <defun:f> <id:x> = <id:x>\n<kw:and> <defun:g> <id:y> = <id:y>",
    );
    check(
        "ocaml",
        "let add x y = x + y",
        "<kw:let> <defun:add> <id:x> <id:y> = <id:x> + <id:y>",
    );
}

#[test]
fn ocaml_types_strings_comments() {
    check(
        "ocaml",
        "type server = { port : int }\nlet name = \"api\"\n(* hello *)",
        "<kw:type> <typedef:server> = { <id:port> : <id:int> }\n<kw:let> <var:name> = \
         <str:\"api\">\n<comment:(* hello *)>",
    );
    check(
        "ocaml",
        "\"unterminated\n(* block",
        "<str:\"unterminated>\n<comment:(* block>",
    );
    assert_eq!(
        highlighted(
            "ocaml",
            vec![
                s("(* Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world! *)\nlet x = 1")
            ]
        ),
        "<comment:(* Hello {sc:cruel} world! *)>\n<kw:let> <var:x> = 1"
    );
    assert_eq!(
        highlighted(
            "ocaml",
            vec![
                s("(* Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world!\nlet x = 1")
            ]
        ),
        "<comment:(* Hello {sc:cruel} world!>\n<comment:let x = 1>"
    );
}

#[test]
fn non_ascii_text_is_lexed_whole() {
    check(
        "go",
        "x := \"é\" // ü",
        "<var:x> := <str:\"é\"> <comment:// ü>",
    );
    check("rust", "let π = 3;", "<kw:let> <var:π> = 3;");
}
