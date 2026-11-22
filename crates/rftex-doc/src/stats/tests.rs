use super::*;
use crate::document::{ColSpec, Heading, MathDisplay, TableCell};

fn s(text: &str) -> Inline {
    Inline::Str(text.to_string())
}

#[test]
fn counts_prose_without_tokenizing() {
    let blocks = [Block::Para(vec![
        s("Memory-mapped IO isn't slow."),
        Inline::NumericSpace,
        Inline::Strong(vec![s("It scales.")]),
        Inline::LineBreak,
        Inline::Link {
            url: "https://example.com".to_string(),
            body: vec![s("Read more")],
        },
    ])];
    assert_eq!(word_count(&blocks), 8);
}

#[test]
fn ignores_code_math_and_media() {
    let blocks = [
        Block::Para(vec![s("Count this short paragraph.")]),
        Block::CodeBlock {
            classes: vec![],
            body: vec![s("let x = 1")],
        },
        Block::VerbatimBlock {
            classes: vec![],
            text: "printfn \"hello\"".to_string(),
        },
        Block::Para(vec![Inline::Math(MathDisplay::Inline, vec![])]),
        Block::Image {
            classes: vec![],
            src: "/images/example.svg".to_string(),
        },
    ];
    assert_eq!(word_count(&blocks), 4);
}

#[test]
fn carries_state_across_inline_boundaries() {
    let blocks = [Block::Para(vec![Inline::SmallCaps(vec![s("llm")]), s("s")])];
    assert_eq!(word_count(&blocks), 1);
}

#[test]
fn treats_inline_separators_as_boundaries() {
    let blocks = [Block::Para(vec![
        s("one"),
        Inline::NumericSpace,
        s("two"),
        Inline::LineBreak,
        s("three"),
        Inline::Math(MathDisplay::Inline, vec![]),
        s("four"),
    ])];
    assert_eq!(word_count(&blocks), 4);
}

#[test]
fn includes_headings_notes_tables_and_quotes() {
    let row = |content: Vec<Inline>| TableRow {
        border_top: false,
        border_bottom: false,
        cells: vec![TableCell {
            colspan: 1,
            align: ColSpec::Left,
            content,
        }],
    };
    let blocks = [Block::Section {
        heading: Some(Heading {
            anchor: "intro".to_string(),
            title: vec![s("One heading")],
        }),
        body: vec![
            Block::Para(vec![s("Two body words.")]),
            Block::Blockquote {
                body: vec![Block::Para(vec![s("Three quoted words.")])],
                attribution: vec![],
            },
            Block::Table(Table {
                spec: vec![ColSpec::Left],
                header: Some(row(vec![s("Four header words here")])),
                rows: vec![row(vec![Inline::MarginNote {
                    anchor: "n1".to_string(),
                    body: vec![s("Two note")],
                }])],
                opts: vec![],
            }),
        ],
    }];
    assert_eq!(word_count(&blocks), 14);
}

#[test]
fn connectors_join_words_only_between_word_characters() {
    let count = |text: &str| word_count(&[Block::Para(vec![s(text)])]);
    assert_eq!(count("well-known"), 1);
    assert_eq!(count("rock 'n' roll"), 3);
    assert_eq!(count("a - b"), 2);
    assert_eq!(count("naïve café"), 2);
    assert_eq!(count("x--y"), 2);
    assert_eq!(count(""), 0);
}

#[test]
fn connectors_join_words_across_inline_boundaries() {
    let count = |inlines: Vec<Inline>| word_count(&[Block::Para(inlines)]);
    assert_eq!(count(vec![s("well-"), Inline::Strong(vec![s("known")])]), 1);
    assert_eq!(count(vec![s("isn'"), Inline::Emph(vec![s("t")])]), 1);
    assert_eq!(count(vec![Inline::Emph(vec![s("rock-")]), s("solid")]), 1);
    assert_eq!(count(vec![s("well-"), Inline::LineBreak, s("known")]), 2);
    assert_eq!(
        count(vec![s("well -"), Inline::Strong(vec![s("known")])]),
        2
    );
}
