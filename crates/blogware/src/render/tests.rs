use rftex_doc::bib::{self, Entry};
use rftex_doc::document::{Heading, MathDisplay};

use super::*;

fn s(text: &str) -> Inline {
    Inline::Str(text.to_string())
}

fn block(block: &Block) -> String {
    let mut h = Html::new();
    render_block(&mut h, Ctx::EMPTY, block, true);
    h.finish()
}

fn inline(inline: &Inline) -> String {
    inlines_to_string(Ctx::EMPTY, std::slice::from_ref(inline))
}

fn code(classes: &[&str], body: Vec<Inline>) -> String {
    block(&Block::CodeBlock {
        classes: classes.iter().map(|class| class.to_string()).collect(),
        body,
    })
}

fn two_cell_table(opts: &[&str]) -> Block {
    let cell = |text: &str| TableCell {
        colspan: 1,
        align: ColSpec::Left,
        content: vec![s(text)],
    };
    Block::Table(Table {
        spec: vec![ColSpec::Left, ColSpec::Left],
        header: None,
        rows: vec![TableRow {
            border_top: false,
            border_bottom: false,
            cells: vec![cell("a"), cell("b")],
        }],
        opts: opts.iter().map(|opt| opt.to_string()).collect(),
    })
}

#[test]
fn paragraphs_and_plain_inlines() {
    assert_eq!(block(&Block::Para(vec![s("hi")])), "<p>hi</p>\n");
    assert_eq!(block(&Block::Plain(vec![s("hi")])), "hi");
    assert_eq!(
        block(&Block::Para(vec![Inline::Quotation(vec![s("q")])])),
        "<p class=\"hanging-quote\"><q>q</q></p>\n"
    );
}

#[test]
fn inlines() {
    assert_eq!(inline(&Inline::Strong(vec![s("bold")])), "<b>bold</b>");
    assert_eq!(inline(&s("a < b & \"c\"")), "a &lt; b &amp; &quot;c&quot;");
    assert_eq!(
        inline(&Inline::Link {
            url: "/x".to_string(),
            body: vec![s("x")]
        }),
        "<a href=\"/x\">x</a>"
    );
    assert_eq!(
        inline(&Inline::Anchor("foo".to_string())),
        "<span id=\"foo\"></span>"
    );
    assert_eq!(inline(&Inline::LineBreak), "<br>");
    assert_eq!(inline(&Inline::NumericSpace), "&numsp;");
    assert_eq!(
        inline(&Inline::CircledRef(1)),
        "<span class=\"circled-ref\" data-num-glyph=\"\u{2460}\" aria-label=\"step 1\" \
         role=\"img\"></span>"
    );
    assert_eq!(
        inline(&Inline::Highlighted(
            HighlightRole::Keyword,
            vec![s("func")]
        )),
        "<span class=\"hl-kw\">func</span>"
    );
    assert_eq!(
        inline(&Inline::Code {
            classes: vec![],
            body: vec![s("x")]
        }),
        "<code>x</code>"
    );
    assert_eq!(
        inline(&Inline::Math(MathDisplay::Inline, vec![])),
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" class=\"math\"></math>"
    );
    assert_eq!(
        inline(&Inline::MarginNote {
            anchor: "n".to_string(),
            body: vec![s("note")]
        }),
        "<label class=\"margin-toggle\" for=\"n\">\u{2295}</label><input type=\"checkbox\" \
         id=\"n\" class=\"margin-toggle\"><span class=\"marginnote\">note</span>"
    );
    assert_eq!(
        inline(&Inline::SideNote {
            anchor: "n".to_string(),
            body: vec![s("note")]
        }),
        "<label class=\"margin-toggle sidenote-number\" for=\"n\"></label><input \
         type=\"checkbox\" id=\"n\" class=\"margin-toggle\"><span class=\"sidenote\">note</span>"
    );
}

#[test]
fn references() {
    let mut refs = RefTable::new();
    refs.insert(
        "post".to_string(),
        RefTarget {
            title: "A &amp; B".to_string(),
            url: "/posts/post.html".to_string(),
        },
    );
    let ctx = Ctx {
        refs: &refs,
        bib: &[],
    };
    // The title is HTML and gets escaped once more.
    assert_eq!(
        inlines_to_string(ctx, &[Inline::Nameref("post".to_string())]),
        "<a href=\"/posts/post.html\">A &amp;amp; B</a>"
    );
    assert_eq!(
        inlines_to_string(
            ctx,
            &[Inline::Ref {
                label: "post".to_string(),
                body: vec![s("here")]
            }]
        ),
        "<a href=\"/posts/post.html\">here</a>"
    );
    assert_eq!(
        inline(&Inline::Nameref("post".to_string())),
        "[unresolved:post]"
    );
}

#[test]
fn bibref_renders_postnote_after_cite() {
    let entries: Vec<Entry> = bib::parse(
        "@book{knuth, author = {Donald Knuth}, title = {The Art of Computer Programming}, \
         url = {https://example.com/taocp}}\n@misc{anon, title = {Anonymous}}",
    )
    .entries;
    let ctx = Ctx {
        refs: &NO_REFS,
        bib: &entries,
    };
    let bibref = |key: &str, postnote: Vec<Inline>| {
        inlines_to_string(
            ctx,
            &[Inline::Bibref {
                key: key.to_string(),
                postnote,
            }],
        )
    };
    assert_eq!(
        bibref("knuth", vec![s("p. "), Inline::Emph(vec![s("6")])]),
        "<span class=\"bibref-author\">Donald Knuth</span>, <cite><a \
         href=\"https://example.com/taocp\">The Art of Computer Programming</a></cite>, <span \
         class=\"bibref-postnote\">p. <em>6</em></span>"
    );
    assert_eq!(bibref("anon", vec![]), "<cite>Anonymous</cite>");
}

#[test]
fn sections() {
    assert_eq!(
        block(&Block::Section {
            heading: None,
            body: vec![]
        }),
        "<section></section>\n"
    );
    assert_eq!(
        block(&Block::Section {
            heading: Some(Heading {
                anchor: "x".to_string(),
                title: vec![s("T")]
            }),
            body: vec![Block::Subsection {
                heading: Heading {
                    anchor: "y".to_string(),
                    title: vec![s("U")]
                },
                body: vec![Block::HRule],
            }],
        }),
        "<section><h2 id=\"x\"><a href=\"#x\">T</a></h2>\n<h3 id=\"y\"><a \
         href=\"#y\">U</a></h3>\n<hr>\n</section>\n"
    );
}

#[test]
fn lists() {
    assert_eq!(
        block(&Block::BulletList(
            ListStyle::Bullets,
            vec![vec![Block::Plain(vec![s("a")])]]
        )),
        "<ul class=\"bullets\"><li>a</li></ul>\n"
    );
    assert_eq!(
        block(&Block::OrderedList(vec![
            vec![Block::Plain(vec![s("a")])],
            vec![Block::Plain(vec![s("b")])]
        ])),
        "<ol class=\"circled\"><li data-num-glyph=\"\u{2460}\">a</li><li \
         data-num-glyph=\"\u{2461}\">b</li></ol>\n"
    );
}

#[test]
fn images() {
    let image = |classes: &[&str], src: &str| Block::Image {
        classes: classes.iter().map(|class| class.to_string()).collect(),
        src: src.to_string(),
    };
    assert_eq!(block(&image(&[], "p.png")), "<p><img src=\"p.png\"></p>\n");
    assert_eq!(
        block(&image(&["wide"], "p.png")),
        "<p><img class=\"wide\" src=\"p.png\"></p>\n"
    );
    assert_eq!(
        block(&image(&[], "diagram.svg")),
        "<p class=\"svg\"><img src=\"diagram.svg\"></p>\n"
    );
    assert_eq!(
        block(&Block::Figure {
            classes: vec![],
            body: vec![image(&[], "p.png")]
        }),
        "<figure><img src=\"p.png\">\n</figure>\n"
    );
}

#[test]
fn tables() {
    assert_eq!(
        block(&two_cell_table(&[])),
        "<table><tbody><tr><td colspan=\"1\" class=\"align-l\">a</td><td colspan=\"1\" \
         class=\"align-l\">b</td></tr></tbody></table>\n"
    );
    assert_eq!(
        block(&two_cell_table(&["uniform"])),
        "<table class=\"table-2 uniform\"><tbody><tr><td colspan=\"1\" class=\"align-l\">a</td>\
         <td colspan=\"1\" class=\"align-l\">b</td></tr></tbody></table>\n"
    );
    let Block::Table(mut with_header) = two_cell_table(&[]) else {
        unreachable!()
    };
    with_header.header = with_header.rows.pop();
    with_header.header.as_mut().unwrap().border_bottom = true;
    assert_eq!(
        block(&Block::Table(with_header)),
        "<table><thead><thead><tr class=\"border-bot\"><th colspan=\"1\" \
         class=\"align-l\">a</th><th colspan=\"1\" \
         class=\"align-l\">b</th></tr></thead><tbody></tbody></table>\n"
    );
}

#[test]
fn quotations() {
    assert_eq!(
        block(&Block::Blockquote {
            body: vec![Block::Para(vec![
                s("\n  hello "),
                Inline::Strong(vec![s("world")]),
                s("\n")
            ])],
            attribution: vec![s("by test")],
        }),
        "<figure class=\"bq left-gutter-anchor\"><blockquote><p>hello <b>world</b></p>\
         </blockquote><figcaption>by test</figcaption></figure>\n"
    );
    assert_eq!(
        block(&Block::Epigraph {
            body: vec![Block::Plain(vec![s("q")])],
            attribution: vec![],
        }),
        "<figure class=\"epigraph left-gutter-anchor\" role=\"doc-epigraph\"><blockquote>q\
         </blockquote><figcaption></figcaption></figure>\n"
    );
}

#[test]
fn advice_and_details() {
    assert_eq!(
        block(&Block::Advice {
            anchor: "hint".to_string(),
            body: vec![s("Use it.")]
        }),
        "<div class=\"advice\" id=\"hint\"><p><a class=\"anchor left-gutter-anchor \
         advice-anchor\" href=\"#hint\" aria-label=\"Link to this advice\"></a>Use \
         it.</p></div>\n"
    );
    assert_eq!(
        block(&Block::Details {
            summary: vec![s("More")],
            body: vec![Block::Para(vec![s("a")])]
        }),
        "<details><summary>More</summary>a</details>\n"
    );
}

#[test]
fn code_blocks() {
    assert_eq!(
        code(&["go"], vec![s("package main\nfunc main() {}")]),
        "<div class=\"source-container\"><pre class=\"source go\"><code><span \
         class=\"line\"><span class=\"hl-kw\">package</span> <span \
         class=\"hl-id\">main</span></span>\n<span class=\"line\"><span \
         class=\"hl-kw\">func</span> <span class=\"hl-defun\">main</span>() {}</span>\n\
         </code></pre></div>\n"
    );
    assert_eq!(
        code(&["python"], vec![s("fn main() {}\n")]),
        "<div class=\"source-container\"><pre class=\"source python\"><code><span \
         class=\"line\">fn main() {}</span>\n</code></pre></div>\n"
    );
    assert_eq!(
        code(&[], vec![]),
        "<div class=\"source-container\"><pre class=\"source\"><code></code></pre></div>\n"
    );
    assert_eq!(
        code(
            &["go"],
            vec![
                s("// Hello "),
                Inline::SmallCaps(vec![s("cruel")]),
                s(" world!")
            ]
        ),
        "<div class=\"source-container\"><pre class=\"source go\"><code><span \
         class=\"line\"><span class=\"hl-comment\">// Hello <span \
         class=\"smallcaps\">cruel</span> world!</span></span>\n</code></pre></div>\n"
    );
    // A span across a line break is cut at the break.
    assert_eq!(
        code(&[], vec![Inline::Strong(vec![s("a\nb")])]),
        "<div class=\"source-container\"><pre class=\"source\"><code><span \
         class=\"line\"><b>a</span>\n<span class=\"line\">b</b></span>\n</code></pre></div>\n"
    );
}

#[test]
fn verbatim_blocks_are_escaped() {
    assert_eq!(
        block(&Block::VerbatimBlock {
            classes: vec!["text".to_string()],
            text: "<b>\n".to_string()
        }),
        "<div class=\"source-container\"><pre class=\"source text\"><code>&lt;b&gt;\n\
         </code></pre></div>\n"
    );
}
