//! The document model: what an article is made of once the markup is gone.
//!
//! A document is a tree of [`Block`]s that hold [`Inline`]s. The model says
//! what things are (a section, a margin note, a citation), not how they look;
//! turning it into HTML is the renderer's job. Text is stored with typography
//! already applied.

pub use rftex_syntax::ast::{ColSpec, MathDisplay, MathNode};

use crate::date::Date;

/// The role of a piece of highlighted code.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum HighlightRole {
    Keyword,
    Defun,
    String,
    Comment,
    Variable,
    Typedef,
    Identifier,
}

/// A piece of running text.
#[derive(Clone, PartialEq, Debug)]
pub enum Inline {
    /// Plain text.
    Str(String),
    Strong(Vec<Inline>),
    Emph(Vec<Inline>),
    Italic(Vec<Inline>),
    Underline(Vec<Inline>),
    SmallCaps(Vec<Inline>),
    Strikethrough(Vec<Inline>),
    Code {
        classes: Vec<String>,
        body: Vec<Inline>,
    },
    Highlighted(HighlightRole, Vec<Inline>),
    Link {
        url: String,
        body: Vec<Inline>,
    },
    Math(MathDisplay, Vec<MathNode>),
    MarginNote {
        anchor: String,
        body: Vec<Inline>,
    },
    SideNote {
        anchor: String,
        body: Vec<Inline>,
    },
    Kbd(Vec<Inline>),
    Sub(Vec<Inline>),
    Sup(Vec<Inline>),
    /// Text in quotation marks.
    Quotation(Vec<Inline>),
    /// The title of a work.
    Cite(Vec<Inline>),
    /// A function name.
    Fun(Vec<Inline>),
    /// Text set in the math font, from `\math`.
    MathSpan(Vec<Inline>),
    /// Text that goes back to the normal style inside a styled span.
    Normal(Vec<Inline>),
    /// A place that links can point to, from `\label`.
    Anchor(String),
    HorizontalRule,
    /// A number in a circle.
    CircledRef(i64),
    LineBreak,
    /// A space as wide as a digit.
    NumericSpace,
    /// A link to a label that shows the title of its target.
    Nameref(String),
    /// A link to a label with its own text.
    Ref {
        label: String,
        body: Vec<Inline>,
    },
    /// A citation of a bibliography entry, with an optional postnote such as
    /// a page number.
    Bibref {
        key: String,
        postnote: Vec<Inline>,
    },
    /// An image inside running text or a table cell.
    Image {
        classes: Vec<String>,
        src: String,
    },
}

/// The text of inlines without their formatting. Math, images and other
/// inlines that are not made of text contribute nothing.
pub fn plain_text(inlines: &[Inline]) -> String {
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

/// The marker of a bulleted list.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ListStyle {
    Bullets,
    Checklist,
}

#[derive(Clone, PartialEq, Debug)]
pub struct TableCell {
    pub colspan: i64,
    pub align: ColSpec,
    pub content: Vec<Inline>,
}

#[derive(Clone, PartialEq, Debug)]
pub struct TableRow {
    pub border_top: bool,
    pub border_bottom: bool,
    pub cells: Vec<TableCell>,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Table {
    pub spec: Vec<ColSpec>,
    pub header: Option<TableRow>,
    pub rows: Vec<TableRow>,
    pub opts: Vec<String>,
}

/// The anchor and the title of a section.
#[derive(Clone, PartialEq, Debug)]
pub struct Heading {
    pub anchor: String,
    pub title: Vec<Inline>,
}

/// A piece of a document that stands on its own.
#[derive(Clone, PartialEq, Debug)]
pub enum Block {
    Para(Vec<Inline>),
    /// Inlines that are not wrapped into a paragraph.
    Plain(Vec<Inline>),
    /// A section. One without a heading holds the text that comes before the
    /// first heading, or follows `\section*`.
    Section {
        heading: Option<Heading>,
        body: Vec<Block>,
    },
    Subsection {
        heading: Heading,
        body: Vec<Block>,
    },
    /// A code listing.
    CodeBlock {
        classes: Vec<String>,
        body: Vec<Inline>,
    },
    /// Text reproduced exactly as written.
    VerbatimBlock {
        classes: Vec<String>,
        text: String,
    },
    BulletList(ListStyle, Vec<Vec<Block>>),
    OrderedList(Vec<Vec<Block>>),
    /// Terms with their descriptions.
    DescriptionList(Vec<(Vec<Inline>, Vec<Block>)>),
    Blockquote {
        body: Vec<Block>,
        attribution: Vec<Inline>,
    },
    Epigraph {
        body: Vec<Block>,
        attribution: Vec<Inline>,
    },
    Table(Table),
    Image {
        classes: Vec<String>,
        src: String,
    },
    Figure {
        classes: Vec<String>,
        body: Vec<Block>,
    },
    Abstract(Vec<Block>),
    Advice {
        anchor: String,
        body: Vec<Inline>,
    },
    /// A block that the reader can unfold.
    Details {
        summary: Vec<Inline>,
        body: Vec<Block>,
    },
    Center(Vec<Block>),
    Figcaption(Vec<Inline>),
    HRule,
}

/// A blog post.
#[derive(Clone, PartialEq, Debug)]
pub struct Article {
    /// The name of the source file without the extension.
    pub slug: String,
    pub title: Vec<Inline>,
    pub subtitle: Vec<Inline>,
    pub featured: bool,
    pub created_at: Date,
    pub modified_at: Date,
    pub word_count: usize,
    /// Sorted.
    pub keywords: Vec<String>,
    pub body: Vec<Block>,
    /// The path of the page on the site.
    pub url: String,
    pub reddit: Option<String>,
    pub hackernews: Option<String>,
    pub lobsters: Option<String>,
}

/// A page of the digital garden: lighter than an article.
#[derive(Clone, PartialEq, Debug)]
pub struct Note {
    /// The name of the source file without the extension.
    pub slug: String,
    pub title: Vec<Inline>,
    pub created_at: Date,
    pub modified_at: Date,
    pub body: Vec<Block>,
    /// The path of the page on the site.
    pub url: String,
}
