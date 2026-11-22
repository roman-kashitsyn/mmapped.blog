//! References between documents, and the check that they resolve.
//!
//! `\nameref` and `\ref` point to a label; `\bibref` points to an entry of
//! the bibliography. A label is either the slug of an article or a note, or
//! the anchor of a section or a subsection of the document that makes the
//! reference. Nothing else is a label: `\label`, `\advice` and the notes in
//! the margin place anchors that a URL can address, and no more than that.

use std::collections::HashSet;

use rftex_syntax::TextRange;

use crate::bib::Entry;
use crate::diagnostic::Diagnostic;
use crate::document::Block;

/// What a reference points to.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Target {
    /// A document, or a section of the same document.
    Label,
    /// An entry of the bibliography.
    Bib,
}

/// One use of `\nameref`, `\ref` or `\bibref`.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Reference {
    pub target: Target,
    /// The label or the key, as written.
    pub name: String,
    /// Where the name is written.
    pub range: TextRange,
}

/// The anchors of the sections and subsections of a document: the labels it
/// can refer to besides the slugs of the site.
pub fn section_anchors(body: &[Block]) -> Vec<&str> {
    let mut anchors = Vec::new();
    for block in body {
        let Block::Section {
            heading: Some(heading),
            body,
        } = block
        else {
            continue;
        };
        anchors.push(heading.anchor.as_str());
        for block in body {
            if let Block::Subsection { heading, .. } = block {
                anchors.push(heading.anchor.as_str());
            }
        }
    }
    anchors
}

/// The names that the documents of a site can refer to.
#[derive(Clone, Debug, Default)]
pub struct Index {
    slugs: HashSet<String>,
    /// `None` if the bibliography could not be read. Its errors are reported
    /// on their own; holding every citation against them would bury them.
    bib_keys: Option<HashSet<String>>,
}

impl Index {
    /// Builds the index from the slugs of all articles and notes and from the
    /// bibliography, if it is intact.
    pub fn new(slugs: impl IntoIterator<Item = String>, bib: Option<&[Entry]>) -> Index {
        Index {
            slugs: slugs.into_iter().collect(),
            bib_keys: bib.map(|entries| {
                entries
                    .iter()
                    .map(|entry| entry.key().to_string())
                    .collect()
            }),
        }
    }

    /// Reports the references that point nowhere. `anchors` are the labels
    /// of the referring document itself, see [`section_anchors`].
    pub fn check(&self, references: &[Reference], anchors: &[&str]) -> Vec<Diagnostic> {
        references
            .iter()
            .filter_map(|reference| match reference.target {
                Target::Label => {
                    let name = reference.name.as_str();
                    let known = self.slugs.contains(name) || anchors.contains(&name);
                    (!known).then(|| {
                        Diagnostic::new(reference.range, format!("unknown reference `{name}`"))
                            .with_label(
                                "no article, note or section of this document has this name",
                            )
                    })
                }
                Target::Bib => {
                    let keys = self.bib_keys.as_ref()?;
                    (!keys.contains(&reference.name)).then(|| {
                        Diagnostic::new(
                            reference.range,
                            format!("unknown bibliography entry `{}`", reference.name),
                        )
                        .with_label("no entry of the bibliography has this key")
                    })
                }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests;
