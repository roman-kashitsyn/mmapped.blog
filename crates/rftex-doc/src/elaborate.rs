//! Elaboration: from the syntax of a document to its meaning.
//!
//! The elaborator reads the metadata commands that precede the `document`
//! environment, turns the body into blocks and inlines, splits the text into
//! paragraphs and nests it into sections.
//!
//! A mistake does not stop it. The offending piece is reported and left out,
//! and the rest of the document is elaborated as usual, so one run finds
//! every mistake. The input must come from a source without syntax errors:
//! on a broken tree the elaborator would complain about the holes.

use rftex_syntax::ast::{Arg, ArgValue, Name, Node, NodeKind, Row, RowBorder};
use rftex_syntax::registry::Sym;
use rftex_syntax::TextRange;

use crate::date::Date;
use crate::diagnostic::Diagnostic;
use crate::document::{
    Article, Block, ColSpec, Heading, Inline, ListStyle, Note, Table, TableCell, TableRow,
};
use crate::refs::{Reference, Target};
use crate::stats;

/// The outcome of elaboration.
#[derive(Clone, Debug)]
pub struct Elaborated<T> {
    /// The document. If there are diagnostics, it lacks the pieces they
    /// point at.
    pub doc: T,
    /// Every `\nameref`, `\ref` and `\bibref` of the document.
    pub references: Vec<Reference>,
    pub diagnostics: Vec<Diagnostic>,
}

/// Elaborates an article. `slug` is the name of its source file without the
/// extension.
pub fn article(slug: &str, nodes: &[Node]) -> Elaborated<Article> {
    let mut elaborator = Elaborator::default();
    let (meta, body) = elaborator.document(DocClass::Article, nodes);
    let mut keywords = meta.keywords;
    keywords.sort();
    let doc = Article {
        slug: slug.to_string(),
        title: vec![Inline::Str(apply_typography(&meta.title))],
        subtitle: vec![Inline::Str(apply_typography(&meta.subtitle))],
        featured: meta.featured,
        created_at: meta.created_at,
        modified_at: meta.modified_at,
        word_count: stats::word_count(&body),
        keywords,
        body,
        url: format!("/posts/{slug}.html"),
        reddit: meta.reddit,
        hackernews: meta.hackernews,
        lobsters: meta.lobsters,
    };
    elaborator.finish(doc)
}

/// Elaborates a note. `slug` is the name of its source file without the
/// extension.
pub fn note(slug: &str, nodes: &[Node]) -> Elaborated<Note> {
    let mut elaborator = Elaborator::default();
    let (meta, body) = elaborator.document(DocClass::Note, nodes);
    let doc = Note {
        slug: slug.to_string(),
        title: vec![Inline::Str(apply_typography(&meta.title))],
        created_at: meta.created_at,
        modified_at: meta.modified_at,
        body,
        url: format!("/notes/{slug}.html"),
    };
    elaborator.finish(doc)
}

// ------------------------------------------------------------- typography

/// Replaces ASCII punctuation with its typographic form: `---` and `--`
/// become dashes, ` `` ` and `''` become double quotes, `'` becomes an
/// apostrophe.
pub fn apply_typography(input: &str) -> String {
    // Longer patterns first: `---` must not be read as `--` and `-`.
    const REPLACEMENTS: [(&str, &str); 5] = [
        ("---", "\u{2014}"),
        ("--", "\u{2013}"),
        ("``", "\u{201C}"),
        ("''", "\u{201D}"),
        ("'", "\u{2019}"),
    ];
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while let Some(index) = rest.find(['-', '`', '\'']) {
        out.push_str(&rest[..index]);
        rest = &rest[index..];
        let replaced = REPLACEMENTS
            .iter()
            .find(|(pattern, _)| rest.starts_with(pattern));
        let used = match replaced {
            Some((pattern, replacement)) => {
                out.push_str(replacement);
                pattern.len()
            }
            None => {
                out.push_str(&rest[..1]);
                1
            }
        };
        rest = &rest[used..];
    }
    out.push_str(rest);
    out
}

const DINGBATS: [(&str, &str); 3] = [
    ("heavy-ballot-x", "\u{2717}"),
    ("heavy-check", "\u{2714}"),
    ("lower-right-pencil", "\u{270E}"),
];

/// The mark that ends a proof.
const QED: &str = "\u{220E}";

// --------------------------------------------------------------- metadata

#[derive(Clone, Copy, PartialEq, Eq)]
enum DocClass {
    Article,
    Note,
}

impl DocClass {
    fn name(self) -> &'static str {
        match self {
            DocClass::Article => "article",
            DocClass::Note => "note",
        }
    }
}

struct Meta {
    title: String,
    subtitle: String,
    featured: bool,
    created_at: Date,
    modified_at: Date,
    keywords: Vec<String>,
    reddit: Option<String>,
    hackernews: Option<String>,
    lobsters: Option<String>,
}

/// Commands that describe the document. They are read before the body and
/// mean nothing inside it.
fn is_metadata(sym: Sym) -> bool {
    matches!(
        sym,
        Sym::Documentclass
            | Sym::Title
            | Sym::Subtitle
            | Sym::Featured
            | Sym::Date
            | Sym::Modified
            | Sym::Keyword
            | Sym::Reddit
            | Sym::Hackernews
            | Sym::Lobsters
    )
}

/// Turns nodes back into source-like text, for arguments that hold plain
/// text: titles and image paths.
fn node_text(nodes: &[Node]) -> String {
    let mut out = String::new();
    for node in nodes {
        match &node.kind {
            NodeKind::Text(text) => out.push_str(text),
            NodeKind::Cmd { name, args, .. } => {
                out.push('\\');
                out.push_str(&name.text);
                for arg in args {
                    if let ArgValue::Nodes(nodes) = &arg.value {
                        out.push('{');
                        out.push_str(&node_text(nodes));
                        out.push('}');
                    }
                }
            }
            _ => {}
        }
    }
    out
}

// ----------------------------------------------------------- text helpers

fn is_whitespace(text: &str) -> bool {
    text.bytes()
        .all(|byte| matches!(byte, b' ' | b'\x0C' | b'\t' | b'\n' | b'\r'))
}

/// The text of inlines without their formatting.
fn inlines_to_text(inlines: &[Inline]) -> String {
    fn collect(inlines: &[Inline], out: &mut String) {
        for inline in inlines {
            match inline {
                Inline::Str(text) => out.push_str(text),
                Inline::Strong(body)
                | Inline::Emph(body)
                | Inline::Italic(body)
                | Inline::Underline(body)
                | Inline::SmallCaps(body)
                | Inline::Strikethrough(body)
                | Inline::Kbd(body)
                | Inline::Sub(body)
                | Inline::Sup(body)
                | Inline::Quotation(body)
                | Inline::Cite(body)
                | Inline::Fun(body)
                | Inline::MathSpan(body)
                | Inline::Normal(body)
                | Inline::Code { body, .. }
                | Inline::Highlighted(_, body)
                | Inline::Link { body, .. }
                | Inline::MarginNote { body, .. }
                | Inline::SideNote { body, .. }
                | Inline::Ref { body, .. } => collect(body, out),
                Inline::Math(..)
                | Inline::Anchor(_)
                | Inline::HorizontalRule
                | Inline::CircledRef(_)
                | Inline::LineBreak
                | Inline::NumericSpace
                | Inline::Nameref(_)
                | Inline::Bibref { .. }
                | Inline::Image { .. } => {}
            }
        }
    }
    let mut out = String::new();
    collect(inlines, &mut out);
    out
}

/// What a braced group stands for: its only inline, or else its text.
fn group_inline(mut inlines: Vec<Inline>) -> Inline {
    if inlines.len() == 1 {
        inlines.remove(0)
    } else {
        Inline::Str(inlines_to_text(&inlines))
    }
}

// ------------------------------------------------------------- paragraphs

/// Drops the whitespace-only text at both ends.
fn trim(inlines: &[Inline]) -> &[Inline] {
    let blank = |inline: &Inline| matches!(inline, Inline::Str(text) if is_whitespace(text));
    let start = inlines
        .iter()
        .position(|inline| !blank(inline))
        .unwrap_or(inlines.len());
    let end = inlines
        .iter()
        .rposition(|inline| !blank(inline))
        .map_or(start, |last| last + 1);
    &inlines[start..end]
}

/// Content that lives in the margin or is invisible.
fn is_side_content(inline: &Inline) -> bool {
    matches!(
        inline,
        Inline::MarginNote { .. } | Inline::SideNote { .. } | Inline::Anchor(_)
    )
}

/// Ends the paragraph collected in `inlines`, if it has any content.
fn flush_paragraph(inlines: &mut Vec<Inline>, blocks: &mut Vec<Block>) {
    let trimmed = trim(inlines);
    if !trimmed.is_empty() {
        // A paragraph element around nothing but side content would add an
        // empty line to the page.
        blocks.push(if trimmed.iter().all(is_side_content) {
            Block::Plain(trimmed.to_vec())
        } else {
            Block::Para(trimmed.to_vec())
        });
    }
    inlines.clear();
}

/// Splits inlines into paragraphs at the blank lines in their text.
fn split_paragraphs(inlines: Vec<Inline>) -> Vec<Block> {
    let mut blocks = Vec::new();
    let mut current = Vec::new();
    for inline in inlines {
        match inline {
            Inline::Str(text) if text.contains("\n\n") => {
                // Each blank line ends a paragraph; the text after the last
                // one starts the next.
                for (index, piece) in text.split("\n\n").enumerate() {
                    if index > 0 {
                        flush_paragraph(&mut current, &mut blocks);
                    }
                    current.push(Inline::Str(piece.to_string()));
                }
            }
            inline => current.push(inline),
        }
    }
    flush_paragraph(&mut current, &mut blocks);
    blocks
}

/// Whether the text before the first line break has a blank line.
fn has_blank_line_before_first_line_break(inlines: &[Inline]) -> bool {
    inlines
        .iter()
        .take_while(|inline| !matches!(inline, Inline::LineBreak))
        .any(|inline| matches!(inline, Inline::Str(text) if text.contains("\n\n")))
}

/// Whether the inlines are side content and line breaks only, separated by
/// nothing but whitespace.
fn is_side_content_only(inlines: &[Inline]) -> bool {
    !inlines.is_empty()
        && inlines.iter().all(|inline| match inline {
            Inline::LineBreak => true,
            Inline::Str(text) => is_whitespace(text),
            inline => is_side_content(inline),
        })
}

/// Turns the inlines collected between two blocks into paragraphs.
fn flush_inlines(pending: &mut Vec<Inline>, out: &mut Vec<Flat>) {
    let inlines = std::mem::take(pending);
    if inlines.is_empty() {
        return;
    }
    let trimmed = trim(&inlines);
    if !has_blank_line_before_first_line_break(&inlines) && is_side_content_only(trimmed) {
        out.push(Flat::Block(Block::Plain(trimmed.to_vec())));
    } else {
        out.extend(split_paragraphs(inlines).into_iter().map(Flat::Block));
    }
}

// --------------------------------------------------------- classification

/// An item of the body before sections are formed.
enum Flat {
    Block(Block),
    Section(Heading),
    /// `\section*`, with the range of its name.
    AnonymousSection(TextRange),
    /// `\subsection`, with the range of its name.
    Subsection(TextRange, Heading),
}

/// What a node contributes to the document.
enum Classified {
    Block(Block),
    Mark(Flat),
    Inline(Inline),
    Nothing,
}

/// How the content of an argument is read.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Prose,
    /// Inside `\code` and the `code` environment: text is taken literally
    /// and only inline commands are allowed.
    Code,
}

macro_rules! symbol {
    ($value:pat) => {
        Arg {
            value: ArgValue::Symbol($value),
            ..
        }
    };
}

macro_rules! nodes {
    ($value:pat) => {
        Arg {
            value: ArgValue::Nodes($value),
            ..
        }
    };
}

macro_rules! url {
    ($value:pat) => {
        Arg {
            value: ArgValue::Url($value),
            ..
        }
    };
}

macro_rules! number {
    ($value:pat) => {
        Arg {
            value: ArgValue::Number($value),
            ..
        }
    };
}

/// The inline that a command wraps its only argument into, for commands that
/// do nothing else.
fn span(sym: Sym) -> Option<fn(Vec<Inline>) -> Inline> {
    let wrap: fn(Vec<Inline>) -> Inline = match sym {
        Sym::B => Inline::Strong,
        Sym::Emph => Inline::Emph,
        Sym::Textit => Inline::Italic,
        Sym::U => Inline::Underline,
        Sym::Textsc => Inline::SmallCaps,
        Sym::Strikethrough => Inline::Strikethrough,
        Sym::Kbd => Inline::Kbd,
        Sym::Sub => Inline::Sub,
        Sym::Sup => Inline::Sup,
        Sym::Fun => Inline::Fun,
        Sym::Math => Inline::MathSpan,
        Sym::Normal => Inline::Normal,
        _ => return None,
    };
    Some(wrap)
}

#[derive(Default)]
struct Elaborator {
    diagnostics: Vec<Diagnostic>,
    references: Vec<Reference>,
}

impl Elaborator {
    fn finish<T>(self, doc: T) -> Elaborated<T> {
        Elaborated {
            doc,
            references: self.references,
            diagnostics: self.diagnostics,
        }
    }

    fn error(&mut self, diagnostic: Diagnostic) {
        self.diagnostics.push(diagnostic);
    }

    fn reference(&mut self, target: Target, name: &str, range: TextRange) {
        self.references.push(Reference {
            target,
            name: name.to_string(),
            range,
        });
    }

    // ----------------------------------------------------------- document

    fn document(&mut self, class: DocClass, nodes: &[Node]) -> (Meta, Vec<Block>) {
        let meta = self.metadata(class, nodes);
        let body = nodes.iter().find_map(|node| match &node.kind {
            NodeKind::Env { name, body, .. } if name.sym == Sym::Document => Some(body.as_slice()),
            _ => None,
        });
        let flat = self.flat_blocks(body.unwrap_or_default());
        (meta, self.sections(flat))
    }

    fn metadata(&mut self, class: DocClass, nodes: &[Node]) -> Meta {
        let mut meta = Meta {
            title: String::new(),
            subtitle: String::new(),
            featured: false,
            created_at: Date::EPOCH,
            modified_at: Date::EPOCH,
            keywords: Vec::new(),
            reddit: None,
            hackernews: None,
            lobsters: None,
        };
        let mut class_declared = false;
        for node in nodes {
            let NodeKind::Cmd { name, args, .. } = &node.kind else {
                continue;
            };
            match (name.sym, args.as_slice()) {
                (Sym::Documentclass, [arg @ symbol!(found), ..]) => {
                    class_declared = true;
                    if found != class.name() {
                        self.error(Diagnostic::new(
                            arg.range,
                            format!(
                                "expected \\documentclass{{{}}} but found \\documentclass{{{found}}}",
                                class.name()
                            ),
                        ));
                    }
                }
                (Sym::Title, [nodes!(title), ..]) => meta.title = node_text(title),
                (Sym::Subtitle, [nodes!(subtitle), ..]) => meta.subtitle = node_text(subtitle),
                (Sym::Featured, _) => meta.featured = true,
                (Sym::Date, [arg @ symbol!(_), ..]) => {
                    if let Some(date) = self.date(arg) {
                        meta.created_at = date;
                        meta.modified_at = date;
                    }
                }
                (Sym::Modified, [arg @ symbol!(_), ..]) => {
                    if let Some(date) = self.date(arg) {
                        meta.modified_at = date;
                    }
                }
                (Sym::Keyword, [symbol!(keyword), ..]) => meta.keywords.push(keyword.clone()),
                (Sym::Reddit, [url!(url), ..]) => meta.reddit = Some(url.clone()),
                (Sym::Hackernews, [url!(url), ..]) => meta.hackernews = Some(url.clone()),
                (Sym::Lobsters, [url!(url), ..]) => meta.lobsters = Some(url.clone()),
                _ => {}
            }
        }
        // A document that does not name its class is an article.
        if !class_declared && class != DocClass::Article {
            self.error(
                Diagnostic::new(
                    TextRange::empty(0),
                    format!("missing \\documentclass{{{}}}", class.name()),
                )
                .with_help("a document without \\documentclass is an article"),
            );
        }
        meta
    }

    fn date(&mut self, arg: &Arg) -> Option<Date> {
        let ArgValue::Symbol(text) = &arg.value else {
            return None;
        };
        let date = Date::parse(text);
        if date.is_none() {
            self.error(
                Diagnostic::new(arg.range, format!("invalid date `{text}`"))
                    .with_label("expected YYYY-MM-DD"),
            );
        }
        date
    }

    // ------------------------------------------------------------- blocks

    /// Elaborates block content, keeping the section marks.
    fn flat_blocks(&mut self, nodes: &[Node]) -> Vec<Flat> {
        let mut out = Vec::new();
        let mut pending = Vec::new();
        for node in nodes {
            match self.classify(node) {
                Classified::Block(block) => {
                    flush_inlines(&mut pending, &mut out);
                    out.push(Flat::Block(block));
                }
                Classified::Mark(mark) => {
                    flush_inlines(&mut pending, &mut out);
                    out.push(mark);
                }
                Classified::Inline(inline) => pending.push(inline),
                Classified::Nothing => {}
            }
        }
        flush_inlines(&mut pending, &mut out);
        out
    }

    /// Elaborates block content that cannot hold sections. Section marks in
    /// it are ignored.
    fn blocks(&mut self, nodes: &[Node]) -> Vec<Block> {
        self.flat_blocks(nodes)
            .into_iter()
            .filter_map(|flat| match flat {
                Flat::Block(block) => Some(block),
                _ => None,
            })
            .collect()
    }

    /// Nests flat content into sections and subsections. Content before the
    /// first heading forms a section without a title.
    fn sections(&mut self, flat: Vec<Flat>) -> Vec<Block> {
        enum Open {
            Preamble,
            Anonymous(TextRange),
            Named(Heading),
        }

        fn close(
            open: Open,
            mut body: Vec<Block>,
            subsection: Option<(Heading, Vec<Block>)>,
            out: &mut Vec<Block>,
        ) {
            if let Some((heading, blocks)) = subsection {
                body.push(Block::Subsection {
                    heading,
                    body: blocks,
                });
            }
            let heading = match open {
                Open::Preamble if body.is_empty() => return,
                Open::Preamble | Open::Anonymous(_) => None,
                Open::Named(heading) => Some(heading),
            };
            out.push(Block::Section { heading, body });
        }

        let mut out = Vec::new();
        let mut open = Open::Preamble;
        let mut body = Vec::new();
        let mut subsection: Option<(Heading, Vec<Block>)> = None;
        for item in flat {
            let next = match item {
                Flat::Block(block) => {
                    match &mut subsection {
                        Some((_, blocks)) => blocks.push(block),
                        None => body.push(block),
                    }
                    continue;
                }
                Flat::Subsection(range, heading) => {
                    let message = "\\subsection is not allowed in a section without a title";
                    match &open {
                        Open::Named(_) => {
                            if let Some((heading, blocks)) = subsection.take() {
                                body.push(Block::Subsection {
                                    heading,
                                    body: blocks,
                                });
                            }
                            subsection = Some((heading, Vec::new()));
                        }
                        Open::Anonymous(section) => self.error(
                            Diagnostic::new(range, message)
                                .with_related(*section, "the section starts here"),
                        ),
                        Open::Preamble => self.error(
                            Diagnostic::new(range, message)
                                .with_help("start a section with \\section{anchor}{title} first"),
                        ),
                    }
                    continue;
                }
                Flat::Section(heading) => Open::Named(heading),
                Flat::AnonymousSection(range) => Open::Anonymous(range),
            };
            let previous = std::mem::replace(&mut open, next);
            close(
                previous,
                std::mem::take(&mut body),
                subsection.take(),
                &mut out,
            );
        }
        close(open, body, subsection, &mut out);
        out
    }

    fn classify(&mut self, node: &Node) -> Classified {
        match &node.kind {
            NodeKind::Text(text) => Classified::Inline(Inline::Str(apply_typography(text))),
            NodeKind::Group(body) => Classified::Inline(group_inline(self.inlines(body))),
            NodeKind::Quotation(body) => Classified::Inline(Inline::Quotation(self.inlines(body))),
            NodeKind::Math { display, body } => {
                Classified::Inline(Inline::Math(*display, body.clone()))
            }
            NodeKind::Cmd { name, opts, args } => self.command(name, opts, args),
            NodeKind::Env { name, opts, body } => self.environment(name, opts, body),
            NodeKind::Table {
                name,
                opts,
                spec,
                rows,
            } => {
                // Only `tabular` has a header; `tabular*` is all body.
                let has_header = name.sym == Sym::Tabular;
                Classified::Block(Block::Table(self.table(has_header, opts, spec, rows)))
            }
        }
    }

    fn command(&mut self, name: &Name, opts: &[String], args: &[Arg]) -> Classified {
        if let Some(inline) = self.inline_command(Mode::Prose, name, opts, args) {
            return Classified::Inline(inline);
        }
        let block = match (name.sym, args) {
            (Sym::Section, [symbol!(anchor), nodes!(title), ..]) => {
                return Classified::Mark(Flat::Section(Heading {
                    anchor: anchor.clone(),
                    title: self.inlines(title),
                }));
            }
            (Sym::SectionStar, _) => {
                return Classified::Mark(Flat::AnonymousSection(name.range));
            }
            (Sym::Subsection, [symbol!(anchor), nodes!(title), ..]) => {
                let heading = Heading {
                    anchor: anchor.clone(),
                    title: self.inlines(title),
                };
                return Classified::Mark(Flat::Subsection(name.range, heading));
            }
            (Sym::Cite, [nodes!(body), ..]) => {
                return Classified::Inline(Inline::Cite(self.inlines(body)));
            }
            (Sym::Bibref, [key_arg @ symbol!(key), rest @ ..]) => {
                self.reference(Target::Bib, key, key_arg.range);
                let postnote = match rest {
                    [nodes!(postnote), ..] => self.inlines(postnote),
                    _ => Vec::new(),
                };
                return Classified::Inline(Inline::Bibref {
                    key: key.clone(),
                    postnote,
                });
            }
            (Sym::Center, [nodes!(body), ..]) => Block::Center(self.blocks(body)),
            (Sym::Hrule, _) => Block::HRule,
            (Sym::Advice, [symbol!(anchor), nodes!(body), ..]) => Block::Advice {
                anchor: anchor.clone(),
                body: self.inlines(body),
            },
            (Sym::Epigraph, [nodes!(body), nodes!(attribution), ..]) => Block::Epigraph {
                body: self.blocks(body),
                attribution: self.inlines(attribution),
            },
            (Sym::Blockquote, [nodes!(body), nodes!(attribution), ..]) => Block::Blockquote {
                body: self.blocks(body),
                attribution: self.inlines(attribution),
            },
            (Sym::Figcaption, [nodes!(body), ..]) => Block::Figcaption(self.inlines(body)),
            (Sym::Details, [nodes!(summary), nodes!(body), ..]) => Block::Details {
                summary: self.inlines(summary),
                body: self.blocks(body),
            },
            // A term outside of a description list forms a list of its own.
            (Sym::Term, [nodes!(term), nodes!(description), ..]) => {
                let term = self.inlines(term);
                let description = vec![Block::Plain(self.inlines(description))];
                Block::DescriptionList(vec![(term, description)])
            }
            (Sym::Includegraphics, [nodes!(path), ..]) => Block::Image {
                classes: opts.to_vec(),
                src: node_text(path),
            },
            (Sym::Item, _) => {
                self.error(
                    Diagnostic::new(name.range, "\\item outside of a list")
                        .with_label("expected inside itemize, enumerate or checklist"),
                );
                return Classified::Nothing;
            }
            (sym, _) if is_metadata(sym) => return Classified::Nothing,
            (Sym::Other, _) => {
                self.error(Diagnostic::new(
                    name.range,
                    format!("unknown command `\\{}`", name.text),
                ));
                return Classified::Nothing;
            }
            _ => {
                self.error(Diagnostic::new(
                    name.range,
                    format!("`\\{}` is not allowed here", name.text),
                ));
                return Classified::Nothing;
            }
        };
        Classified::Block(block)
    }

    fn environment(&mut self, name: &Name, opts: &[String], body: &[Node]) -> Classified {
        let block = match name.sym {
            Sym::Abstract => Block::Abstract(self.blocks(body)),
            Sym::Enumerate => Block::OrderedList(self.list_items(body)),
            Sym::Itemize => Block::BulletList(ListStyle::Bullets, self.list_items(body)),
            Sym::Checklist => Block::BulletList(ListStyle::Checklist, self.list_items(body)),
            Sym::Figure => Block::Figure {
                classes: opts.to_vec(),
                body: self.blocks(body),
            },
            Sym::Description => Block::DescriptionList(self.description_items(body)),
            Sym::Verbatim => Block::VerbatimBlock {
                classes: opts.to_vec(),
                text: body
                    .iter()
                    .filter_map(|node| match &node.kind {
                        NodeKind::Text(text) => Some(text.as_str()),
                        _ => None,
                    })
                    .collect(),
            },
            Sym::Code => Block::CodeBlock {
                classes: opts.to_vec(),
                body: self.code_inlines(body),
            },
            Sym::Other => {
                self.error(Diagnostic::new(
                    name.range,
                    format!("unknown environment `{}`", name.text),
                ));
                return Classified::Nothing;
            }
            _ => {
                self.error(Diagnostic::new(
                    name.range,
                    format!("`{}` is not allowed here", name.text),
                ));
                return Classified::Nothing;
            }
        };
        Classified::Block(block)
    }

    /// Splits the body of a list at `\item`. The first paragraph of an item
    /// is not wrapped, so that a one-line item stays compact.
    fn list_items(&mut self, nodes: &[Node]) -> Vec<Vec<Block>> {
        let is_item =
            |node: &Node| matches!(&node.kind, NodeKind::Cmd { name, .. } if name.sym == Sym::Item);
        let mut items = Vec::new();
        for group in nodes.split(is_item) {
            let mut blocks = self.blocks(group);
            if let Some(first) = blocks.first_mut() {
                if let Block::Para(inlines) = first {
                    let inlines = std::mem::take(inlines);
                    *first = Block::Plain(inlines);
                }
            }
            if !blocks.is_empty() {
                items.push(blocks);
            }
        }
        items
    }

    /// Collects the `\term` entries of a description list. Anything between
    /// them is ignored.
    fn description_items(&mut self, nodes: &[Node]) -> Vec<(Vec<Inline>, Vec<Block>)> {
        let mut items = Vec::new();
        for node in nodes {
            let NodeKind::Cmd { name, args, .. } = &node.kind else {
                continue;
            };
            let (Sym::Term, [nodes!(term), nodes!(description), ..]) = (name.sym, args.as_slice())
            else {
                continue;
            };
            let term = self.inlines(term);
            let mut description = self.blocks(description);
            if let [Block::Para(inlines)] = description.as_mut_slice() {
                let inlines = std::mem::take(inlines);
                description = vec![Block::Plain(inlines)];
            }
            items.push((term, description));
        }
        items
    }

    fn table(
        &mut self,
        has_header: bool,
        opts: &[String],
        spec: &[ColSpec],
        rows: &[Row],
    ) -> Table {
        let mut rows: Vec<TableRow> = rows
            .iter()
            .map(|row| TableRow {
                border_top: matches!(row.border, RowBorder::Top | RowBorder::Both),
                border_bottom: matches!(row.border, RowBorder::Bottom | RowBorder::Both),
                cells: row
                    .cells
                    .iter()
                    .map(|cell| TableCell {
                        colspan: cell.colspan,
                        align: cell.align,
                        content: self.inlines(&cell.body),
                    })
                    .collect(),
            })
            .collect();
        let header = (has_header && !rows.is_empty()).then(|| rows.remove(0));
        Table {
            spec: spec.to_vec(),
            header,
            rows,
            opts: opts.to_vec(),
        }
    }

    // ------------------------------------------------------------ inlines

    /// Elaborates inline content. Blocks have no place in it and are left
    /// out, except for images, which can stand in a line.
    fn inlines(&mut self, nodes: &[Node]) -> Vec<Inline> {
        let mut out = Vec::new();
        for node in nodes {
            match self.classify(node) {
                Classified::Inline(inline) => out.push(inline),
                Classified::Block(Block::Image { classes, src }) => {
                    out.push(Inline::Image { classes, src })
                }
                Classified::Block(_) | Classified::Mark(_) | Classified::Nothing => {}
            }
        }
        out
    }

    /// Elaborates the content of `\code` and of the `code` environment.
    fn code_inlines(&mut self, nodes: &[Node]) -> Vec<Inline> {
        let mut out = Vec::new();
        for node in nodes {
            match &node.kind {
                NodeKind::Text(text) => out.push(Inline::Str(text.clone())),
                NodeKind::Group(body) => out.push(group_inline(self.code_inlines(body))),
                NodeKind::Quotation(body) => out.push(Inline::Quotation(self.code_inlines(body))),
                NodeKind::Math { display, body } => out.push(Inline::Math(*display, body.clone())),
                NodeKind::Cmd { name, opts, args } => {
                    out.extend(self.code_command(name, opts, args))
                }
                NodeKind::Env { name, .. } | NodeKind::Table { name, .. } => {
                    self.error(Diagnostic::new(
                        name.range,
                        format!("environment `{}` is not allowed in code", name.text),
                    ));
                }
            }
        }
        out
    }

    fn code_command(&mut self, name: &Name, opts: &[String], args: &[Arg]) -> Option<Inline> {
        if let Some(inline) = self.inline_command(Mode::Code, name, opts, args) {
            return Some(inline);
        }
        match (name.sym, args) {
            (Sym::Hrule, _) => Some(Inline::HorizontalRule),
            (Sym::Includegraphics, [nodes!(path), ..]) => Some(Inline::Image {
                classes: opts.to_vec(),
                src: node_text(path),
            }),
            (Sym::Other, _) => {
                self.error(Diagnostic::new(
                    name.range,
                    format!("unknown command `\\{}`", name.text),
                ));
                None
            }
            _ => {
                self.error(Diagnostic::new(
                    name.range,
                    format!("`\\{}` is not allowed in code", name.text),
                ));
                None
            }
        }
    }

    fn inlines_in(&mut self, mode: Mode, nodes: &[Node]) -> Vec<Inline> {
        match mode {
            Mode::Prose => self.inlines(nodes),
            Mode::Code => self.code_inlines(nodes),
        }
    }

    /// Elaborates a command that means the same in prose and in code.
    /// Returns `None` for any other command.
    fn inline_command(
        &mut self,
        mode: Mode,
        name: &Name,
        opts: &[String],
        args: &[Arg],
    ) -> Option<Inline> {
        if let (Some(wrap), [nodes!(body), ..]) = (span(name.sym), args) {
            return Some(wrap(self.inlines_in(mode, body)));
        }
        Some(match (name.sym, args) {
            (Sym::Code, [nodes!(body), ..]) => Inline::Code {
                classes: opts.to_vec(),
                body: self.code_inlines(body),
            },
            (Sym::Href, [url!(url), nodes!(body), ..]) => Inline::Link {
                url: url.clone(),
                body: self.inlines_in(mode, body),
            },
            (Sym::Nameref, [arg @ symbol!(label), ..]) => {
                self.reference(Target::Label, label, arg.range);
                Inline::Nameref(label.clone())
            }
            (Sym::Ref, [arg @ symbol!(label), nodes!(body), ..]) => {
                self.reference(Target::Label, label, arg.range);
                Inline::Ref {
                    label: label.clone(),
                    body: self.inlines_in(mode, body),
                }
            }
            (Sym::Label, [symbol!(anchor), ..]) => Inline::Anchor(anchor.clone()),
            (Sym::Newline, _) => Inline::LineBreak,
            (Sym::Numspace, _) => Inline::NumericSpace,
            (Sym::Qed, _) => Inline::Str(QED.to_string()),
            (Sym::Marginnote, [symbol!(anchor), nodes!(body), ..]) => Inline::MarginNote {
                anchor: anchor.clone(),
                body: self.inlines_in(mode, body),
            },
            (Sym::Sidenote, [symbol!(anchor), nodes!(body), ..]) => Inline::SideNote {
                anchor: anchor.clone(),
                body: self.inlines_in(mode, body),
            },
            (Sym::Dingbat, [arg @ symbol!(dingbat), ..]) => {
                let glyph = DINGBATS.iter().find(|(known, _)| known == dingbat);
                if glyph.is_none() {
                    let known: Vec<&str> = DINGBATS.iter().map(|(known, _)| *known).collect();
                    self.error(
                        Diagnostic::new(arg.range, format!("unknown dingbat `{dingbat}`"))
                            .with_help(format!("known dingbats: {}", known.join(", "))),
                    );
                }
                Inline::Str(glyph.map_or(String::new(), |(_, glyph)| glyph.to_string()))
            }
            (Sym::Circled, [number!(number), ..]) => Inline::CircledRef(*number),
            (sym, _) => Inline::Str(sym.spec().replacement?.to_string()),
        })
    }
}

#[cfg(test)]
mod tests;
