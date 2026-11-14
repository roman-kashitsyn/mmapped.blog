use super::*;
use crate::{analyze_article, analyze_note, Analysis};

fn s(text: &str) -> Inline {
    Inline::Str(text.to_string())
}

fn para(text: &str) -> Block {
    Block::Para(vec![s(text)])
}

fn anonymous(body: Vec<Block>) -> Block {
    Block::Section {
        heading: None,
        body,
    }
}

fn section(anchor: &str, title: &str, body: Vec<Block>) -> Block {
    Block::Section {
        heading: Some(heading(anchor, title)),
        body,
    }
}

fn heading(anchor: &str, title: &str) -> Heading {
    Heading {
        anchor: anchor.to_string(),
        title: vec![s(title)],
    }
}

/// Elaborates an article that must have no errors.
fn article(src: &str) -> Article {
    let Analysis {
        doc, diagnostics, ..
    } = analyze_article("slug", src);
    assert_eq!(diagnostics, [], "{src}");
    doc.unwrap()
}

/// Elaborates the body of an article that must have no errors.
fn body(content: &str) -> Vec<Block> {
    article(&format!("\\begin{{document}}{content}\\end{{document}}")).body
}

/// The blocks of an article that is one section without a title.
fn blocks(content: &str) -> Vec<Block> {
    match body(content).as_slice() {
        [Block::Section {
            heading: None,
            body,
        }] => body.clone(),
        other => panic!("expected one anonymous section, got {other:?}"),
    }
}

/// The inlines of an article that is one paragraph.
fn inlines(content: &str) -> Vec<Inline> {
    match blocks(content).as_slice() {
        [Block::Para(inlines)] => inlines.clone(),
        other => panic!("expected one paragraph, got {other:?}"),
    }
}

/// The messages of the errors in an article, with the text they point at.
fn errors(src: &str) -> Vec<(String, String)> {
    analyze_article("slug", src)
        .diagnostics
        .into_iter()
        .map(|diagnostic| (diagnostic.message, diagnostic.range.slice(src).to_string()))
        .collect()
}

fn error(message: &str, text: &str) -> (String, String) {
    (message.to_string(), text.to_string())
}

// ------------------------------------------------------------- typography

#[test]
fn typography() {
    assert_eq!(apply_typography("foo"), "foo");
    assert_eq!(apply_typography("a---b"), "a\u{2014}b");
    assert_eq!(apply_typography("a--b"), "a\u{2013}b");
    assert_eq!(apply_typography("``hello''"), "\u{201C}hello\u{201D}");
    assert_eq!(apply_typography("it's"), "it\u{2019}s");
    // A single dash and a single backtick stay.
    assert_eq!(apply_typography("x-y"), "x-y");
    assert_eq!(apply_typography("a`b"), "a`b");
    assert_eq!(apply_typography("a----b"), "a\u{2014}-b");
    assert_eq!(apply_typography("'''"), "\u{201D}\u{2019}");
    assert_eq!(apply_typography("naïve---café"), "naïve\u{2014}café");
    assert_eq!(apply_typography(""), "");
}

// ------------------------------------------------- paragraphs and sections

#[test]
fn single_paragraph() {
    assert_eq!(body("hello"), [anonymous(vec![para("hello")])]);
}

#[test]
fn two_paragraphs() {
    assert_eq!(blocks("one\n\ntwo"), [para("one"), para("two")]);
}

#[test]
fn empty_paragraphs_are_skipped() {
    assert_eq!(blocks("\n\none\n\n\n\ntwo\n\n"), [para("one"), para("two")]);
    assert_eq!(body(""), []);
    assert_eq!(body(" \n\n "), []);
}

#[test]
fn inlines_between_blank_lines_join_one_paragraph() {
    assert_eq!(
        blocks("one \\b{two}\n\nthree"),
        [
            Block::Para(vec![s("one "), Inline::Strong(vec![s("two")])]),
            para("three"),
        ]
    );
}

#[test]
fn side_only_paragraph_is_plain() {
    assert_eq!(
        blocks("\\label{side-only}"),
        [Block::Plain(vec![Inline::Anchor("side-only".to_string())])]
    );
    assert_eq!(
        blocks("text\n\n\\label{a}\n\nmore"),
        [
            para("text"),
            Block::Plain(vec![Inline::Anchor("a".to_string())]),
            para("more"),
        ]
    );
}

#[test]
fn section_wrap() {
    assert_eq!(
        body("\\section{id}{Title}body"),
        [section("id", "Title", vec![para("body")])]
    );
}

#[test]
fn anonymous_preamble_before_section() {
    assert_eq!(
        body("pre\\section{id}{T}body"),
        [
            anonymous(vec![para("pre")]),
            section("id", "T", vec![para("body")]),
        ]
    );
}

#[test]
fn subsections_nest_in_their_section() {
    assert_eq!(
        body(
            "\\section{a}{A}intro\\subsection{a1}{A1}one\\subsection{a2}{A2}two\
             \\section* three\\section{b}{B}"
        ),
        [
            section(
                "a",
                "A",
                vec![
                    para("intro"),
                    Block::Subsection {
                        heading: heading("a1", "A1"),
                        body: vec![para("one")],
                    },
                    Block::Subsection {
                        heading: heading("a2", "A2"),
                        body: vec![para("two")],
                    },
                ]
            ),
            anonymous(vec![para("three")]),
            section("b", "B", vec![]),
        ]
    );
}

// ---------------------------------------------------------------- inlines

#[test]
fn strong_inline() {
    assert_eq!(inlines("\\b{bold}"), [Inline::Strong(vec![s("bold")])]);
}

#[test]
fn text_gets_typography_but_code_does_not() {
    assert_eq!(
        inlines("it's \\code{it's}"),
        [
            s("it\u{2019}s "),
            Inline::Code {
                classes: vec![],
                body: vec![s("it's")],
            },
        ]
    );
}

#[test]
fn symbols_and_dingbats() {
    assert_eq!(
        inlines("\\ldots\\qed\\dingbat{heavy-check}\\circled{3}"),
        [
            s("\u{2026}"),
            s("\u{220E}"),
            s("\u{2714}"),
            Inline::CircledRef(3),
        ]
    );
}

#[test]
fn group_stands_for_its_only_inline_or_its_text() {
    assert_eq!(inlines("{\\b{x}}"), [Inline::Strong(vec![s("x")])]);
    assert_eq!(inlines("{a\\b{b}c}"), [s("abc")]);
}

#[test]
fn bibref_optional_postnote() {
    assert_eq!(
        inlines("\\bibref[p. \\emph{6}]{rfc:2119_v2}"),
        [Inline::Bibref {
            key: "rfc:2119_v2".to_string(),
            postnote: vec![s("p. "), Inline::Emph(vec![s("6")])],
        }]
    );
    assert_eq!(
        inlines("\\bibref{key}"),
        [Inline::Bibref {
            key: "key".to_string(),
            postnote: vec![],
        }]
    );
}

#[test]
fn image_is_a_block_on_its_own_and_an_inline_in_text() {
    assert_eq!(
        blocks("\\includegraphics[wide]{/images/a.png}"),
        [Block::Image {
            classes: vec!["wide".to_string()],
            src: "/images/a.png".to_string(),
        }]
    );
    assert_eq!(
        inlines("\\b{\\includegraphics{/images/a.png}}"),
        [Inline::Strong(vec![Inline::Image {
            classes: vec![],
            src: "/images/a.png".to_string(),
        }])]
    );
}

// ----------------------------------------------------------------- blocks

#[test]
fn hrule_block() {
    assert_eq!(blocks("\\hrule"), [Block::HRule]);
}

#[test]
fn itemize_list() {
    assert_eq!(
        blocks("\\begin{itemize}\\item a\\item b\n\nc\\end{itemize}"),
        [Block::BulletList(
            ListStyle::Bullets,
            vec![
                vec![Block::Plain(vec![s("a")])],
                vec![Block::Plain(vec![s("b")]), para("c")],
            ]
        )]
    );
}

#[test]
fn description_list() {
    assert_eq!(
        blocks("\\begin{description}\\term{T}{one}ignored\\term{U}{a\n\nb}\\end{description}"),
        [Block::DescriptionList(vec![
            (vec![s("T")], vec![Block::Plain(vec![s("one")])]),
            (vec![s("U")], vec![para("a"), para("b")]),
        ])]
    );
}

#[test]
fn code_block_keeps_text_and_inline_commands() {
    assert_eq!(
        blocks("\\begin{code}[rust]\nlet x = \\b{1};\n\\end{code}"),
        [Block::CodeBlock {
            classes: vec!["rust".to_string()],
            body: vec![s("let x = "), Inline::Strong(vec![s("1")]), s(";\n")],
        }]
    );
}

#[test]
fn verbatim_block() {
    assert_eq!(
        blocks("\\begin{verbatim}\n\\b{raw} -- text\n\\end{verbatim}"),
        [Block::VerbatimBlock {
            classes: vec![],
            text: "\\b{raw} -- text\n".to_string(),
        }]
    );
}

#[test]
fn tabular_has_a_header_and_tabular_star_does_not() {
    let cell = |text: &str| TableCell {
        colspan: 1,
        align: ColSpec::Left,
        content: vec![s(text)],
    };
    let row = |text: &str, border_bottom: bool| TableRow {
        border_top: false,
        border_bottom,
        cells: vec![cell(text)],
    };
    assert_eq!(
        blocks("\\begin{tabular}{l}h\\\\b\\\\\\hrule\\end{tabular}"),
        [Block::Table(Table {
            spec: vec![ColSpec::Left],
            header: Some(row("h", false)),
            rows: vec![row("b", true)],
            opts: vec![],
        })]
    );
    assert_eq!(
        blocks("\\begin{tabular*}{l}h\\\\b\\\\\\end{tabular*}"),
        [Block::Table(Table {
            spec: vec![ColSpec::Left],
            header: None,
            rows: vec![row("h", false), row("b", false)],
            opts: vec![],
        })]
    );
}

// --------------------------------------------------------------- metadata

#[test]
fn metadata() {
    let article = article(
        "\\documentclass{article}\n\
         \\title{It's a title}\n\
         \\subtitle{Sub}\n\
         \\featured\n\
         \\date{2024-05-06}\n\
         \\modified{2024-07-08}\n\
         \\keyword{rust}\n\
         \\keyword{ocaml}\n\
         \\reddit{https://reddit.com/r/x}\n\
         \\hackernews{https://news.ycombinator.com/item?id=1}\n\
         \\lobsters{https://lobste.rs/s/x}\n\
         \\begin{document}One two.\\end{document}\n",
    );
    assert_eq!(article.slug, "slug");
    assert_eq!(article.url, "/posts/slug.html");
    assert_eq!(article.title, [s("It\u{2019}s a title")]);
    assert_eq!(article.subtitle, [s("Sub")]);
    assert!(article.featured);
    assert_eq!(article.created_at.to_string(), "2024-05-06");
    assert_eq!(article.modified_at.to_string(), "2024-07-08");
    assert_eq!(article.keywords, ["ocaml", "rust"]);
    assert_eq!(article.word_count, 2);
    assert_eq!(article.reddit.as_deref(), Some("https://reddit.com/r/x"));
    assert_eq!(
        article.hackernews.as_deref(),
        Some("https://news.ycombinator.com/item?id=1")
    );
    assert_eq!(article.lobsters.as_deref(), Some("https://lobste.rs/s/x"));
}

#[test]
fn metadata_defaults() {
    let article = article("\\date{2024-05-06}\\begin{document}hello\\end{document}");
    assert!(!article.featured);
    assert_eq!(article.title, [s("")]);
    assert_eq!(article.modified_at, article.created_at);
    assert_eq!(article.keywords, [] as [&str; 0]);
    assert_eq!(article.reddit, None);
}

#[test]
fn note_documentclass_accepted() {
    let analysis = analyze_note(
        "slug",
        "\\documentclass{note}\n\\begin{document}hello\\end{document}",
    );
    assert_eq!(analysis.diagnostics, []);
    let note = analysis.doc.unwrap();
    assert_eq!(note.body, [anonymous(vec![para("hello")])]);
    assert_eq!(note.url, "/notes/slug.html");
}

#[test]
fn article_rejects_note_documentclass() {
    assert_eq!(
        errors("\\documentclass{note}\n\\begin{document}hello\\end{document}"),
        [error(
            "expected \\documentclass{article} but found \\documentclass{note}",
            "note"
        )]
    );
}

#[test]
fn note_rejects_article_documentclass() {
    let messages = |src: &str| -> Vec<String> {
        analyze_note("slug", src)
            .diagnostics
            .into_iter()
            .map(|diagnostic| diagnostic.message)
            .collect()
    };
    assert_eq!(
        messages("\\documentclass{article}\n\\begin{document}hello\\end{document}"),
        ["expected \\documentclass{note} but found \\documentclass{article}"]
    );
    // An article may leave the class out; a note may not.
    assert_eq!(
        messages("\\begin{document}hello\\end{document}"),
        ["missing \\documentclass{note}"]
    );
}

// ----------------------------------------------------------------- errors

#[test]
fn unknown_command() {
    assert_eq!(
        errors("\\begin{document}\nHello \\foobar{x}\n\\end{document}\n"),
        [error("unknown command `\\foobar`", "\\foobar")]
    );
}

#[test]
fn unknown_environment() {
    assert_eq!(
        errors("\\begin{document}\n\\begin{fancybox}\ntext\n\\end{fancybox}\n\\end{document}\n"),
        [error("unknown environment `fancybox`", "\\begin{fancybox}")]
    );
}

#[test]
fn invalid_date() {
    assert_eq!(
        errors("\\date{not-a-date}\n\\begin{document}\nHello\n\\end{document}\n"),
        [error("invalid date `not-a-date`", "not-a-date")]
    );
}

#[test]
fn misplaced_commands() {
    assert_eq!(
        errors("\\begin{document}\\item x \\frac \\begin{document}\\end{document}\\end{document}"),
        [
            error("\\item outside of a list", "\\item"),
            error("`\\frac` is not allowed here", "\\frac"),
            error("`document` is not allowed here", "\\begin{document}"),
        ]
    );
}

#[test]
fn unknown_dingbat() {
    let src = "\\begin{document}\\dingbat{nope} \\code{\\dingbat{nah}}\\end{document}";
    assert_eq!(
        errors(src),
        [
            error("unknown dingbat `nope`", "nope"),
            error("unknown dingbat `nah`", "nah"),
        ]
    );
    let help = analyze_article("slug", src).diagnostics[0].help.clone();
    assert_eq!(
        help.as_deref(),
        Some("known dingbats: heavy-ballot-x, heavy-check, lower-right-pencil")
    );
}

#[test]
fn commands_that_code_cannot_hold() {
    assert_eq!(
        errors("\\begin{document}\\code{a \\foo b \\cite{c}}\\end{document}"),
        [
            error("unknown command `\\foo`", "\\foo"),
            error("`\\cite` is not allowed in code", "\\cite"),
        ]
    );
}

#[test]
fn subsection_needs_a_named_section() {
    let src = "\\begin{document}\\subsection{a}{A}x\\section* \\subsection{b}{B}y\\end{document}";
    let diagnostics = analyze_article("slug", src).diagnostics;
    let message = "\\subsection is not allowed in a section without a title";
    assert_eq!(
        diagnostics
            .iter()
            .map(|diagnostic| diagnostic.message.as_str())
            .collect::<Vec<_>>(),
        [message, message]
    );
    assert_eq!(diagnostics[0].related, []);
    assert!(diagnostics[0].help.is_some());
    let [related] = diagnostics[1].related.as_slice() else {
        panic!("{:?}", diagnostics[1].related);
    };
    assert_eq!(related.range.slice(src), "\\section*");
}

#[test]
fn all_errors_are_reported_in_source_order() {
    assert_eq!(
        errors(
            "\\date{soon}\n\
             \\begin{document}\n\
             \\foo \\begin{bar}\\baz\\end{bar}\n\
             \\dingbat{qux}\n\
             \\end{document}\n"
        ),
        [
            error("invalid date `soon`", "soon"),
            error("unknown command `\\foo`", "\\foo"),
            error("unknown environment `bar`", "\\begin{bar}"),
            error("unknown dingbat `qux`", "qux"),
        ]
    );
}

#[test]
fn syntax_errors_come_alone() {
    let src = "\\begin{document}\\foo \\b{x\\end{document}";
    let analysis = analyze_article("slug", src);
    assert!(analysis.doc.is_none());
    assert!(!analysis.diagnostics.is_empty());
    assert!(
        analysis
            .diagnostics
            .iter()
            .all(|diagnostic| !diagnostic.message.contains("foo")),
        "{:?}",
        analysis.diagnostics
    );
}

// ------------------------------------------------------------- references

#[test]
fn references_are_collected() {
    let src = "\\begin{document}\\nameref{a} \\ref{b}{text} \\bibref[p. 1]{c} \
               \\code{\\nameref{d}}\\end{document}";
    let analysis = analyze_article("slug", src);
    assert_eq!(analysis.diagnostics, []);
    let references: Vec<(Target, &str, &str)> = analysis
        .references
        .iter()
        .map(|reference| {
            (
                reference.target,
                reference.name.as_str(),
                reference.range.slice(src),
            )
        })
        .collect();
    assert_eq!(
        references,
        [
            (Target::Label, "a", "a"),
            (Target::Label, "b", "b"),
            (Target::Bib, "c", "c"),
            (Target::Label, "d", "d"),
        ]
    );
}
