//! The meaning of rftex documents.
//!
//! [`rftex_syntax`] turns source text into a tree. This crate turns the tree
//! into a [`document`]: an article or a note made of blocks and inlines, ready
//! to be rendered. It also holds everything else that is needed to say
//! whether a set of documents is correct: the bibliography ([`bib`]) and the
//! check that every reference points somewhere ([`refs`]).
//!
//! Nothing here stops at the first mistake. Each pass returns what it could
//! build together with a list of [`Diagnostic`]s, so that a build reports all
//! the errors of a site at once and an editor can underline all of them.
//!
//! The crate knows nothing about HTML or the file system. The usual entry
//! points are [`analyze_article`] and [`analyze_note`].

pub mod bib;
mod date;
mod diagnostic;
pub mod document;
pub mod elaborate;
mod line_index;
pub mod refs;
pub mod stats;

pub use date::Date;
pub use diagnostic::{Diagnostic, Related};
pub use line_index::{LineCol, LineIndex};

use document::{Article, Note};
use elaborate::Elaborated;
use refs::Reference;

/// What is known about one source file.
#[derive(Clone, Debug)]
pub struct Analysis<T> {
    /// The document, or `None` if the source has syntax errors. A document
    /// that comes with diagnostics is incomplete and must not be published.
    pub doc: Option<T>,
    /// The references the document makes, to be checked against the rest of
    /// the site with [`refs::Index::check`].
    pub references: Vec<Reference>,
    /// The mistakes found, ordered by position.
    pub diagnostics: Vec<Diagnostic>,
}

/// Parses and elaborates an article.
pub fn analyze_article(slug: &str, src: &str) -> Analysis<Article> {
    analyze(src, |nodes| elaborate::article(slug, nodes))
}

/// Parses and elaborates a note.
pub fn analyze_note(slug: &str, src: &str) -> Analysis<Note> {
    analyze(src, |nodes| elaborate::note(slug, nodes))
}

fn analyze<T>(
    src: &str,
    elaborate: impl FnOnce(&[rftex_syntax::ast::Node]) -> Elaborated<T>,
) -> Analysis<T> {
    let parse = rftex_syntax::parse(src);
    // The tree of a source with syntax errors has holes that later passes
    // would report a second time, in more obscure terms.
    if !parse.errors.is_empty() {
        return Analysis {
            doc: None,
            references: Vec::new(),
            diagnostics: parse.errors.iter().map(Diagnostic::from).collect(),
        };
    }
    let nodes = rftex_syntax::lower(&parse.tree, src);
    let Elaborated {
        doc,
        references,
        mut diagnostics,
    } = elaborate(&nodes);
    diagnostics.sort_by_key(|diagnostic| (diagnostic.range.start, diagnostic.range.end));
    Analysis {
        doc: Some(doc),
        references,
        diagnostics,
    }
}
