use super::*;

/// Lexes all of `src` in one mode and renders the tokens compactly.
fn lex(src: &str, mode: Mode) -> String {
    let mut pos = 0;
    let mut out = Vec::new();
    loop {
        let token = next_token(src, pos, mode);
        if token.kind == Eof {
            break;
        }
        let end = pos + token.len as usize;
        out.push(format!("{:?}({:?})", token.kind, &src[pos..end]));
        pos = end;
    }
    out.join(" ")
}

#[test]
fn text_mode() {
    assert_eq!(
        lex("a b\\emph {x}", Mode::Text),
        r#"Text("a b") ControlWord("\\emph ") LBrace("{") Text("x") RBrace("}")"#
    );
    assert_eq!(
        lex("it's ``so'' `x`", Mode::Text),
        r#"Text("it's ") OpenQuote("``") Text("so") CloseQuote("''") Text(" ") Backtick("`") Text("x") Backtick("`")"#
    );
    assert_eq!(
        lex("a\nb\n\n\nc", Mode::Text),
        r#"Text("a\nb") ParBreak("\n\n\n") Text("c")"#
    );
    assert_eq!(
        lex("50\\% % rest\nx", Mode::Text),
        r#"Text("50") Escape("\\%") Text(" ") Comment("% rest\n") Text("x")"#
    );
    assert_eq!(
        lex("\\\\ \\[ \\] & [ ] $", Mode::Text),
        r#"DoubleBackslash("\\\\") Text(" ") DisplayOpen("\\[") Text(" ") DisplayClose("\\]") Text(" ") Amp("&") Text(" ") LBracket("[") Text(" ") RBracket("]") Text(" ") Dollar("$")"#
    );
}

#[test]
fn control_words() {
    assert_eq!(
        lex("\\section*{a}", Mode::Text),
        r#"ControlWord("\\section*") LBrace("{") Text("a") RBrace("}")"#
    );
    // The name ends before punctuation, and only one space is swallowed.
    assert_eq!(
        lex("\\ldots. \\qed  x", Mode::Text),
        r#"ControlWord("\\ldots") Text(". ") ControlWord("\\qed ") Text(" x")"#
    );
    // Math keeps the space as a token of its own.
    assert_eq!(
        lex("\\pi -1", Mode::Math),
        r#"ControlWord("\\pi") Space(" ") Operator("-") Number("1")"#
    );
}

#[test]
fn bad_escapes() {
    assert_eq!(lex("\\", Mode::Text), r#"ErrorToken("\\")"#);
    assert_eq!(lex("\\é.", Mode::Text), r#"ErrorToken("\\é") Text(".")"#);
    assert_eq!(lex("\\&", Mode::Math), r#"ErrorToken("\\&")"#);
}

#[test]
fn code_mode() {
    assert_eq!(
        lex("f(x) { a[0] & b } % c\n\\b{x}$", Mode::Code),
        r#"Text("f(x) { a[0] & b } ") Comment("% c\n") ControlWord("\\b") Text("{x}") Dollar("$")"#
    );
    assert_eq!(
        lex("a\n\n\\\\n", Mode::Code),
        r#"Text("a\n\n") DoubleBackslash("\\\\") Text("n")"#
    );
}

#[test]
fn math_mode() {
    assert_eq!(
        lex("ab_1^{-2}", Mode::Math),
        r#"Letter("a") Letter("b") Underscore("_") Number("1") Caret("^") LBrace("{") Operator("-") Number("2") RBrace("}")"#
    );
    assert_eq!(
        lex("x  &= 12\n\n\\\\", Mode::Math),
        r#"Letter("x") Space("  ") Amp("&") Operator("=") Space(" ") Number("12") Newline("\n") Newline("\n") DoubleBackslash("\\\\")"#
    );
    assert_eq!(
        lex("a.b\\{ % c", Mode::Math),
        r#"Letter("a") ErrorToken(".") Letter("b") Escape("\\{") Space(" ") Comment("% c")"#
    );
}

#[test]
fn atom_mode() {
    assert_eq!(
        lex("{sec-1.a}", Mode::Atom(Charset::Symbol)),
        r#"LBrace("{") Atom("sec-1.a") RBrace("}")"#
    );
    assert_eq!(
        lex("{https://x.org/a%20b?q=[1]&r=$}", Mode::Atom(Charset::Url)),
        r#"LBrace("{") Atom("https://x.org/a%20b?q=[1]&r=$") RBrace("}")"#
    );
    assert_eq!(
        lex("{a b\\emph\n}", Mode::Atom(Charset::Symbol)),
        r#"LBrace("{") Atom("a") ErrorToken(" ") Atom("b") ControlWord("\\emph") Newline("\n") RBrace("}")"#
    );
    assert_eq!(
        lex("{-12}{l r|}", Mode::Atom(Charset::Number)),
        r#"LBrace("{") Atom("-12") RBrace("}") LBrace("{") ErrorToken("l r|") RBrace("}")"#
    );
}

#[test]
fn options_mode() {
    assert_eq!(
        lex("[good, bad\n ,x!]", Mode::Options),
        r#"LBracket("[") Atom("good") Comma(",") Whitespace(" ") Atom("bad") Whitespace("\n ") Comma(",") Atom("x") ErrorToken("!") RBracket("]")"#
    );
}

#[test]
fn raw() {
    let src = "a\\\\end{verbatim}";
    let (token, found) = raw_until(src, 0, "\\end{verbatim}");
    assert_eq!((token.len, found), (2, true));
    let (token, found) = raw_until("abc", 1, "\\end{verbatim}");
    assert_eq!((token.len, found), (2, false));
}

#[test]
fn tokens_end_on_char_boundaries() {
    let src = "é\\é$é^é$ {é} [é] %é\né";
    let charsets = [
        Charset::Symbol,
        Charset::BibKey,
        Charset::Number,
        Charset::Url,
        Charset::AlignSpec,
    ];
    let mut modes = vec![Mode::Text, Mode::Code, Mode::Math, Mode::Options];
    modes.extend(charsets.map(Mode::Atom));
    for mode in modes {
        for start in (0..src.len()).filter(|&i| src.is_char_boundary(i)) {
            let token = next_token(src, start, mode);
            assert!(
                src.is_char_boundary(start + token.len as usize),
                "{mode:?} at {start}"
            );
        }
    }
}
