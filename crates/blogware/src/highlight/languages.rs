//! The supported languages: their lexical rules, keywords and patterns.

use rftex_doc::document::HighlightRole as Role;

use super::lexer::{Kind, Language, Lexical, StringRule, Token};
use super::patterns::*;

fn c_like_ident_start(byte: u8) -> bool {
    byte.is_ascii_alphabetic() || byte == b'_' || byte >= 0x80
}

fn c_like_ident_part(byte: u8) -> bool {
    c_like_ident_start(byte) || byte.is_ascii_digit()
}

fn c_like_delim(byte: u8) -> bool {
    matches!(byte, b'(' | b')' | b'[' | b']' | b'{' | b'}' | b',' | b';')
}

fn c_like_operator(byte: u8) -> bool {
    matches!(
        byte,
        b'+' | b'-'
            | b'*'
            | b'/'
            | b'%'
            | b'&'
            | b'|'
            | b'^'
            | b'!'
            | b'~'
            | b'='
            | b'<'
            | b'>'
            | b':'
            | b'.'
            | b'?'
            | b'@'
            | b'#'
            | b'$'
    )
}

fn ocaml_ident_start(byte: u8) -> bool {
    byte.is_ascii_alphabetic() || byte == b'_' || byte >= 0x80
}

fn ocaml_ident_part(byte: u8) -> bool {
    ocaml_ident_start(byte) || byte.is_ascii_digit() || byte == b'\''
}

fn ocaml_operator(byte: u8) -> bool {
    matches!(
        byte,
        b'!' | b'$'
            | b'%'
            | b'&'
            | b'*'
            | b'+'
            | b'-'
            | b'.'
            | b'/'
            | b':'
            | b'<'
            | b'='
            | b'>'
            | b'?'
            | b'@'
            | b'^'
            | b'|'
            | b'~'
            | b'#'
            | b'\\'
    )
}

const DOUBLE_QUOTED: StringRule = StringRule {
    quote: b'"',
    allow_newline: false,
    raw: false,
};

const SINGLE_QUOTED: StringRule = StringRule {
    quote: b'\'',
    allow_newline: false,
    raw: false,
};

const C_COMMENTS: &[(&str, &str)] = &[("/*", "*/")];

const fn c_like(strings: &'static [StringRule]) -> Lexical {
    Lexical {
        line_comments: &["//"],
        block_comments: C_COMMENTS,
        strings,
        is_ident_start: c_like_ident_start,
        is_ident_part: c_like_ident_part,
        is_delim: c_like_delim,
        is_operator: c_like_operator,
    }
}

pub(super) static LANGUAGES: [Language; 4] = [
    Language {
        name: "go",
        keywords: &[
            "break",
            "default",
            "func",
            "interface",
            "select",
            "case",
            "defer",
            "go",
            "map",
            "struct",
            "chan",
            "else",
            "goto",
            "package",
            "switch",
            "const",
            "fallthrough",
            "if",
            "range",
            "type",
            "continue",
            "for",
            "import",
            "return",
            "var",
        ],
        lexical: c_like(&[
            StringRule {
                quote: b'`',
                allow_newline: true,
                raw: true,
            },
            DOUBLE_QUOTED,
            SINGLE_QUOTED,
        ]),
        classify: classify_go,
    },
    Language {
        name: "c",
        keywords: &[
            "_Alignas",
            "_Alignof",
            "_Atomic",
            "_Bool",
            "_Complex",
            "_Generic",
            "_Imaginary",
            "_Noreturn",
            "_Static_assert",
            "_Thread_local",
            "auto",
            "break",
            "case",
            "char",
            "const",
            "continue",
            "default",
            "do",
            "double",
            "else",
            "enum",
            "extern",
            "float",
            "for",
            "goto",
            "if",
            "inline",
            "int",
            "long",
            "register",
            "restrict",
            "return",
            "short",
            "signed",
            "sizeof",
            "static",
            "struct",
            "switch",
            "typedef",
            "union",
            "unsigned",
            "void",
            "volatile",
            "while",
        ],
        lexical: c_like(&[DOUBLE_QUOTED, SINGLE_QUOTED]),
        classify: classify_c,
    },
    Language {
        name: "rust",
        keywords: &[
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
            "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
            "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
            "trait", "true", "type", "unsafe", "use", "where", "while",
        ],
        lexical: c_like(&[DOUBLE_QUOTED]),
        classify: classify_rust,
    },
    Language {
        name: "ocaml",
        keywords: &[
            "and",
            "as",
            "assert",
            "begin",
            "class",
            "constraint",
            "do",
            "done",
            "downto",
            "else",
            "end",
            "exception",
            "external",
            "false",
            "for",
            "fun",
            "function",
            "functor",
            "if",
            "in",
            "include",
            "inherit",
            "initializer",
            "lazy",
            "let",
            "match",
            "method",
            "module",
            "mutable",
            "new",
            "nonrec",
            "object",
            "of",
            "open",
            "or",
            "private",
            "rec",
            "sig",
            "struct",
            "then",
            "to",
            "true",
            "try",
            "type",
            "val",
            "virtual",
            "when",
            "while",
            "with",
        ],
        lexical: Lexical {
            line_comments: &[],
            block_comments: &[("(*", "*)")],
            strings: &[DOUBLE_QUOTED],
            is_ident_start: ocaml_ident_start,
            is_ident_part: ocaml_ident_part,
            is_delim: c_like_delim,
            is_operator: ocaml_operator,
        },
        classify: classify_ocaml,
    },
];

fn classify_go(tokens: &mut [Token]) {
    let mark_params = |tokens: &mut [Token], (open, close, _): (usize, usize, usize)| {
        mark_go_field_vars(tokens, open, close, Role::Variable);
    };
    let mark_returns = |tokens: &mut [Token], after: usize| {
        if let Some(group) = balanced_from(tokens, after, "(", ")") {
            mark_params(tokens, group);
        }
    };
    for i in 0..tokens.len() {
        match (tokens[i].kind, tokens[i].text) {
            (Kind::Keyword, "func") => {
                let receiver = balanced_from(tokens, i + 1, "(", ")");
                let name_start = receiver.map_or(i + 1, |(_, _, next)| next);
                let name = next_sig_from(tokens, name_start).filter(|&n| is_ident(&tokens[n]));
                let params = name.and_then(|n| balanced_from(tokens, n + 1, "(", ")"));
                match (name, params) {
                    (Some(name), Some(params)) => {
                        if let Some(receiver) = receiver {
                            mark_params(tokens, receiver);
                        }
                        mark(&mut tokens[name], Role::Defun);
                        mark_params(tokens, params);
                        mark_returns(tokens, params.2);
                    }
                    // A function literal.
                    _ => {
                        if let Some(params) = balanced_from(tokens, i + 1, "(", ")") {
                            mark_params(tokens, params);
                            mark_returns(tokens, params.2);
                        }
                    }
                }
            }
            (Kind::Keyword, "type") => {
                apply_decl_choice(tokens, Style::FirstName, Role::Typedef, i + 1)
            }
            (Kind::Keyword, "var" | "const") => {
                apply_decl_choice(tokens, Style::NameList, Role::Variable, i + 1)
            }
            (Kind::Operator, ":=") => mark_short_decl_lhs(tokens, i, Role::Variable),
            _ => {}
        }
    }
}

fn classify_c(tokens: &mut [Token]) {
    for i in 0..tokens.len() {
        match (tokens[i].kind, tokens[i].text) {
            (Kind::Ident, _) => apply_c_function_definition(tokens, i),
            (Kind::Keyword, "typedef") => apply_c_typedef_declaration(tokens, i + 1),
            (Kind::Keyword, "struct" | "union" | "enum") => {
                mark_next_ident(tokens, Role::Typedef, i + 1);
            }
            _ => {}
        }
    }
}

fn classify_rust(tokens: &mut [Token]) {
    for i in 0..tokens.len() {
        match (tokens[i].kind, tokens[i].text) {
            (Kind::Keyword, "fn") => {
                let Some(name) = next_sig_from(tokens, i + 1) else {
                    continue;
                };
                if !is_ident(&tokens[name]) {
                    continue;
                }
                let params_start =
                    balanced_from(tokens, name + 1, "<", ">").map_or(name + 1, |(_, _, next)| next);
                if let Some((open, close, _)) = balanced_from(tokens, params_start, "(", ")") {
                    mark(&mut tokens[name], Role::Defun);
                    mark_rust_field_vars(tokens, open, close, Role::Variable);
                }
            }
            (Kind::Keyword, "let") => {
                let name_start = match next_sig_from(tokens, i + 1) {
                    Some(m) if tokens[m].kind == Kind::Keyword && tokens[m].text == "mut" => m + 1,
                    _ => i + 1,
                };
                mark_next_ident(tokens, Role::Variable, name_start);
            }
            (Kind::Keyword, "struct" | "enum" | "trait" | "type") => {
                mark_next_ident(tokens, Role::Typedef, i + 1);
            }
            _ => {}
        }
    }
}

fn classify_ocaml(tokens: &mut [Token]) {
    // `rec` and `nonrec` may stand between the keyword and the name.
    let skip_keyword =
        |tokens: &[Token], i: usize, keyword: &str| match next_sig_from(tokens, i + 1) {
            Some(k) if tokens[k].kind == Kind::Keyword && tokens[k].text == keyword => k + 1,
            _ => i + 1,
        };
    for i in 0..tokens.len() {
        match (tokens[i].kind, tokens[i].text) {
            (Kind::Keyword, "let") => {
                let start = skip_keyword(tokens, i, "rec");
                apply_ocaml_value_binding(tokens, start);
            }
            (Kind::Keyword, "and") => {
                apply_ocaml_value_binding(tokens, i + 1);
            }
            (Kind::Keyword, "type") => {
                let start = skip_keyword(tokens, i, "nonrec");
                mark_next_ident(tokens, Role::Typedef, start);
            }
            _ => {}
        }
    }
}
