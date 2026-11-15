//! The document model as HTML: blocks and inlines.
//!
//! The output must stay byte-identical to the OCaml renderer's until the
//! cutover, quirks included; they are marked where they occur.

use std::collections::BTreeMap;
use std::path::Path;

use rftex_doc::bib::Entry;
use rftex_doc::document::{
    Block, ColSpec, HighlightRole, Inline, ListStyle, Table, TableCell, TableRow,
};

use crate::highlight;
use crate::html::{class_if_any, Html};
use crate::mathml;

/// Where a label points: the rendered title of its target and its URL.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct RefTarget {
    /// HTML. It is escaped once more where it is shown, as the OCaml engine
    /// does.
    pub title: String,
    pub url: String,
}

pub type RefTable = BTreeMap<String, RefTarget>;

static NO_REFS: RefTable = BTreeMap::new();

/// What rendering a document needs besides the document.
#[derive(Clone, Copy)]
pub struct Ctx<'a> {
    pub refs: &'a RefTable,
    pub bib: &'a [Entry],
}

impl Ctx<'static> {
    /// No labels and no bibliography: for titles and other text outside the
    /// body of a document.
    pub const EMPTY: Ctx<'static> = Ctx {
        refs: &NO_REFS,
        bib: &[],
    };
}

/// The glyph of a number in a circle: ① for 1.
pub fn circled_glyph(n: i64) -> String {
    u32::try_from(n)
        .ok()
        .and_then(|n| n.checked_add(0x245F))
        .and_then(char::from_u32)
        .map(String::from)
        .unwrap_or_default()
}

fn is_svg(path: &str) -> bool {
    Path::new(path).extension().is_some_and(|ext| ext == "svg")
}

fn role_class(role: HighlightRole) -> &'static str {
    match role {
        HighlightRole::Keyword => "hl-kw",
        HighlightRole::Defun => "hl-defun",
        HighlightRole::String => "hl-str",
        HighlightRole::Comment => "hl-comment",
        HighlightRole::Variable => "hl-var",
        HighlightRole::Typedef => "hl-typedef",
        HighlightRole::Identifier => "hl-id",
    }
}

fn align_class(align: ColSpec) -> &'static str {
    match align {
        ColSpec::Left => "align-l",
        ColSpec::Right => "align-r",
        ColSpec::Center => "align-c",
    }
}

// ---------------------------------------------------------------- inlines

/// Renders inlines to a string.
pub fn inlines_to_string(ctx: Ctx, inlines: &[Inline]) -> String {
    let mut h = Html::new();
    render_inlines(&mut h, ctx, inlines);
    h.finish()
}

pub fn render_inlines(h: &mut Html, ctx: Ctx, inlines: &[Inline]) {
    for inline in inlines {
        render_inline(h, ctx, inline);
    }
}

fn wrap(h: &mut Html, ctx: Ctx, tag: &str, class: Option<&str>, body: &[Inline]) {
    let attrs = class.map(|class| ("class", class));
    h.elem_opt(tag, &[attrs], |h| render_inlines(h, ctx, body));
}

fn image(h: &mut Html, classes: &[String], src: &str) {
    let classes = classes.join(" ");
    h.open_opt("img", &[class_if_any(&classes), Some(("src", src))]);
}

pub fn render_inline(h: &mut Html, ctx: Ctx, inline: &Inline) {
    match inline {
        Inline::Str(text) => {
            h.text(text);
        }
        Inline::Strong(body) => wrap(h, ctx, "b", None, body),
        Inline::Emph(body) => wrap(h, ctx, "em", None, body),
        Inline::Italic(body) => wrap(h, ctx, "i", None, body),
        Inline::Underline(body) => wrap(h, ctx, "u", None, body),
        Inline::SmallCaps(body) => wrap(h, ctx, "span", Some("smallcaps"), body),
        Inline::Strikethrough(body) => wrap(h, ctx, "span", Some("strikethrough"), body),
        Inline::Code { classes, body } => {
            let classes = classes.join(" ");
            h.elem_opt("code", &[class_if_any(&classes)], |h| {
                render_inlines(h, ctx, body)
            });
        }
        Inline::Highlighted(role, body) => wrap(h, ctx, "span", Some(role_class(*role)), body),
        Inline::Link { url, body } => {
            h.elem("a", &[("href", url)], |h| render_inlines(h, ctx, body));
        }
        Inline::Math(display, nodes) => mathml::math(h, *display, nodes),
        Inline::MarginNote { anchor, body } => {
            h.elem(
                "label",
                &[("class", "margin-toggle"), ("for", anchor)],
                |h| {
                    h.raw("\u{2295}");
                },
            );
            h.open(
                "input",
                &[
                    ("type", "checkbox"),
                    ("id", anchor),
                    ("class", "margin-toggle"),
                ],
            );
            wrap(h, ctx, "span", Some("marginnote"), body);
        }
        Inline::SideNote { anchor, body } => {
            h.elem(
                "label",
                &[("class", "margin-toggle sidenote-number"), ("for", anchor)],
                |_| {},
            );
            h.open(
                "input",
                &[
                    ("type", "checkbox"),
                    ("id", anchor),
                    ("class", "margin-toggle"),
                ],
            );
            wrap(h, ctx, "span", Some("sidenote"), body);
        }
        Inline::Kbd(body) => wrap(h, ctx, "kbd", None, body),
        Inline::Sub(body) => wrap(h, ctx, "sub", None, body),
        Inline::Sup(body) => wrap(h, ctx, "sup", None, body),
        Inline::Cite(body) => wrap(h, ctx, "cite", None, body),
        Inline::Quotation(body) => wrap(h, ctx, "q", None, body),
        Inline::Fun(body) => wrap(h, ctx, "span", Some("fun"), body),
        Inline::MathSpan(body) => wrap(h, ctx, "span", Some("math"), body),
        Inline::Normal(body) => wrap(h, ctx, "span", Some("normal"), body),
        Inline::Anchor(id) => {
            h.elem("span", &[("id", id)], |_| {});
        }
        Inline::HorizontalRule => {
            h.open("hr", &[]);
        }
        Inline::CircledRef(n) => {
            let glyph = circled_glyph(*n);
            let label = format!("step {n}");
            h.elem(
                "span",
                &[
                    ("class", "circled-ref"),
                    ("data-num-glyph", &glyph),
                    ("aria-label", &label),
                    ("role", "img"),
                ],
                |_| {},
            );
        }
        Inline::LineBreak => {
            h.open("br", &[]);
        }
        Inline::NumericSpace => {
            h.raw("&numsp;");
        }
        Inline::Image { classes, src } => {
            if is_svg(src) {
                h.elem("p", &[("class", "svg")], |h| image(h, classes, src));
            } else {
                image(h, classes, src);
            }
        }
        // `blogware check` rejects unresolved references in the body. Titles
        // are rendered without labels, so a reference in a title shows as a
        // placeholder, as it does in the OCaml engine.
        Inline::Nameref(label) => match ctx.refs.get(label) {
            Some(target) => {
                h.text_elem("a", &[("href", &target.url)], &target.title);
            }
            None => {
                h.text(&format!("[unresolved:{label}]"));
            }
        },
        Inline::Ref { label, body } => match ctx.refs.get(label) {
            Some(target) => {
                h.elem("a", &[("href", &target.url)], |h| {
                    render_inlines(h, ctx, body)
                });
            }
            None => {
                h.text(&format!("[unresolved:{label}]"));
            }
        },
        Inline::Bibref { key, postnote } => {
            let Some(entry) = ctx.bib.iter().find(|entry| entry.key() == key) else {
                h.text(&format!("[unresolved bib:{key}]"));
                return;
            };
            if let Some(author) = entry.author() {
                h.text_elem("span", &[("class", "bibref-author")], author);
                h.text(", ");
            }
            h.elem("cite", &[], |h| match entry.url() {
                Some(url) => {
                    h.text_elem("a", &[("href", url)], entry.title());
                }
                None => {
                    h.text(entry.title());
                }
            });
            if !postnote.is_empty() {
                h.text(", ");
                wrap(h, ctx, "span", Some("bibref-postnote"), postnote);
            }
        }
    }
}

// ----------------------------------------------------------------- blocks

/// The lines of a code listing, each in a span. The content is rendered
/// first and split after, so a span that crosses a line break is cut in two
/// with unbalanced tags; browsers repair them.
fn code_lines(h: &mut Html, ctx: Ctx, content: &[Inline]) {
    let rendered = inlines_to_string(ctx, content);
    let mut lines: Vec<&str> = rendered.split('\n').collect();
    // A final line break does not start another line.
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for line in lines {
        h.elem("span", &[("class", "line")], |h| {
            h.raw(line);
        });
        h.nl();
    }
}

fn source_block(h: &mut Html, classes: &[String], body: impl FnOnce(&mut Html)) {
    let classes = classes.join(" ");
    let pre_class = if classes.is_empty() {
        "source".to_string()
    } else {
        format!("source {classes}")
    };
    h.elem("div", &[("class", "source-container")], |h| {
        h.elem("pre", &[("class", &pre_class)], |h| {
            h.elem("code", &[], body);
        });
    });
    h.nl();
}

fn table_cell(h: &mut Html, ctx: Ctx, tag: &str, cell: &TableCell) {
    let colspan = cell.colspan.to_string();
    h.elem(
        tag,
        &[("colspan", &colspan), ("class", align_class(cell.align))],
        |h| render_inlines(h, ctx, &cell.content),
    );
}

fn table_row(h: &mut Html, ctx: Ctx, tag: &str, row: &TableRow) {
    let class = match (row.border_top, row.border_bottom) {
        (true, true) => "border-top border-bot",
        (true, false) => "border-top",
        (false, true) => "border-bot",
        (false, false) => "",
    };
    h.elem_opt("tr", &[class_if_any(class)], |h| {
        for cell in &row.cells {
            table_cell(h, ctx, tag, cell);
        }
    });
}

fn table(h: &mut Html, ctx: Ctx, table: &Table) {
    let mut classes = Vec::new();
    if table.opts.iter().any(|opt| opt == "uniform") {
        classes.push(format!("table-{}", table.spec.len()));
    }
    classes.extend(table.opts.iter().cloned());
    let classes = classes.join(" ");
    h.elem_opt("table", &[class_if_any(&classes)], |h| {
        if let Some(header) = &table.header {
            // Quirk: the header opens `thead` twice and closes it once.
            h.raw("<thead>");
            h.elem("thead", &[], |h| table_row(h, ctx, "th", header));
        }
        h.elem("tbody", &[], |h| {
            for row in &table.rows {
                table_row(h, ctx, "td", row);
            }
        });
    });
    h.nl();
}

fn hanging_quote(inlines: &[Inline]) -> Option<(&'static str, &'static str)> {
    matches!(inlines.first(), Some(Inline::Quotation(_))).then_some(("class", "hanging-quote"))
}

/// A block inside a quotation. Paragraphs lose the whitespace at their ends
/// and the newline after them.
fn quote_block(h: &mut Html, ctx: Ctx, block: &Block) {
    match block {
        Block::Para(inlines) => {
            let rendered = inlines_to_string(ctx, inlines);
            let trimmed = rendered.trim_matches([' ', '\t', '\x0C', '\n', '\r']);
            h.elem_opt("p", &[hanging_quote(inlines)], |h| {
                h.raw(trimmed);
            });
        }
        Block::Plain(inlines) => render_inlines(h, ctx, inlines),
        block => render_block(h, ctx, block, true),
    }
}

fn quotation(
    h: &mut Html,
    ctx: Ctx,
    attrs: &[(&str, &str)],
    body: &[Block],
    attribution: &[Inline],
) {
    h.elem("figure", attrs, |h| {
        h.elem("blockquote", &[], |h| {
            for block in body {
                quote_block(h, ctx, block);
            }
        });
        wrap(h, ctx, "figcaption", None, attribution);
    });
    h.nl();
}

fn heading(h: &mut Html, ctx: Ctx, tag: &str, anchor: &str, title: &[Inline]) {
    if anchor.is_empty() {
        wrap(h, ctx, tag, None, title);
    } else {
        let href = format!("#{anchor}");
        h.elem(tag, &[("id", anchor)], |h| {
            h.elem("a", &[("href", &href)], |h| render_inlines(h, ctx, title));
        });
    }
    h.nl();
}

pub fn render_blocks(h: &mut Html, ctx: Ctx, blocks: &[Block]) {
    render_blocks_with(h, ctx, blocks, true);
}

/// Renders blocks. Without `wrap_images`, images that are blocks of their own
/// are not wrapped in paragraphs.
fn render_blocks_with(h: &mut Html, ctx: Ctx, blocks: &[Block], wrap_images: bool) {
    for block in blocks {
        render_block(h, ctx, block, wrap_images);
    }
}

pub fn render_block(h: &mut Html, ctx: Ctx, block: &Block, wrap_images: bool) {
    match block {
        Block::Para(inlines) => {
            h.elem_opt("p", &[hanging_quote(inlines)], |h| {
                render_inlines(h, ctx, inlines)
            });
            h.nl();
        }
        Block::Plain(inlines) => render_inlines(h, ctx, inlines),
        Block::Section {
            heading: title,
            body,
        } => {
            h.elem("section", &[], |h| {
                if let Some(title) = title {
                    heading(h, ctx, "h2", &title.anchor, &title.title);
                }
                render_blocks(h, ctx, body);
            });
            h.nl();
        }
        Block::Subsection {
            heading: title,
            body,
        } => {
            heading(h, ctx, "h3", &title.anchor, &title.title);
            render_blocks(h, ctx, body);
        }
        Block::CodeBlock { classes, body } => {
            let content = highlight::highlight(classes, body.clone());
            source_block(h, classes, |h| code_lines(h, ctx, &content));
        }
        Block::VerbatimBlock { classes, text } => {
            source_block(h, classes, |h| {
                h.text(text);
            });
        }
        Block::BulletList(style, items) => {
            let class = match style {
                ListStyle::Bullets => "bullets",
                ListStyle::Checklist => "checklist",
            };
            h.elem("ul", &[("class", class)], |h| {
                for item in items {
                    h.elem("li", &[], |h| render_blocks(h, ctx, item));
                }
            });
            h.nl();
        }
        Block::OrderedList(items) => {
            h.elem("ol", &[("class", "circled")], |h| {
                for (index, item) in items.iter().enumerate() {
                    let glyph = circled_glyph(index as i64 + 1);
                    h.elem("li", &[("data-num-glyph", &glyph)], |h| {
                        render_blocks(h, ctx, item)
                    });
                }
            });
            h.nl();
        }
        Block::DescriptionList(items) => {
            h.elem("dl", &[], |h| {
                for (term, description) in items {
                    wrap(h, ctx, "dt", None, term);
                    h.elem("dd", &[], |h| render_blocks(h, ctx, description));
                }
            });
            h.nl();
        }
        Block::Blockquote { body, attribution } => quotation(
            h,
            ctx,
            &[("class", "bq left-gutter-anchor")],
            body,
            attribution,
        ),
        Block::Epigraph { body, attribution } => quotation(
            h,
            ctx,
            &[
                ("class", "epigraph left-gutter-anchor"),
                ("role", "doc-epigraph"),
            ],
            body,
            attribution,
        ),
        Block::Table(t) => table(h, ctx, t),
        Block::Image { classes, src } => {
            if is_svg(src) {
                h.elem("p", &[("class", "svg")], |h| image(h, classes, src));
            } else if wrap_images {
                h.elem("p", &[], |h| image(h, classes, src));
            } else {
                image(h, classes, src);
            }
            h.nl();
        }
        Block::Figure { classes, body } => {
            let classes = classes.join(" ");
            h.elem_opt("figure", &[class_if_any(&classes)], |h| {
                render_blocks_with(h, ctx, body, false)
            });
            h.nl();
        }
        Block::Abstract(body) => {
            h.elem(
                "section",
                &[("class", "abstract"), ("role", "doc-abstract")],
                |h| render_blocks(h, ctx, body),
            );
            h.nl();
        }
        Block::Advice { anchor, body } => {
            let href = format!("#{anchor}");
            h.elem("div", &[("class", "advice"), ("id", anchor)], |h| {
                h.elem("p", &[], |h| {
                    h.elem(
                        "a",
                        &[
                            ("class", "anchor left-gutter-anchor advice-anchor"),
                            ("href", &href),
                            ("aria-label", "Link to this advice"),
                        ],
                        |_| {},
                    );
                    render_inlines(h, ctx, body);
                });
            });
            h.nl();
        }
        Block::Details { summary, body } => {
            // Paragraphs in the body are not wrapped.
            let body: Vec<Block> = body
                .iter()
                .map(|block| match block {
                    Block::Para(inlines) => Block::Plain(inlines.clone()),
                    block => block.clone(),
                })
                .collect();
            h.elem("details", &[], |h| {
                wrap(h, ctx, "summary", None, summary);
                render_blocks(h, ctx, &body);
            });
            h.nl();
        }
        Block::Center(body) => {
            h.elem("center", &[], |h| render_blocks_with(h, ctx, body, false));
            h.nl();
        }
        Block::Figcaption(inlines) => {
            wrap(h, ctx, "figcaption", None, inlines);
            h.nl();
        }
        Block::HRule => {
            h.open("hr", &[]);
            h.nl();
        }
    }
}

/// Renders blocks to a string.
pub fn blocks_to_string(ctx: Ctx, blocks: &[Block]) -> String {
    let mut h = Html::new();
    render_blocks(&mut h, ctx, blocks);
    h.finish()
}

#[cfg(test)]
mod tests;
