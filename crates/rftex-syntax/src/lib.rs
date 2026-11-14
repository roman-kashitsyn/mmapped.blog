//! Syntax of rftex, the LaTeX-flavored markup of mmapped.blog.
//!
//! The crate turns source text into two trees:
//!
//! - [`parse`] produces a lossless syntax [`Tree`] and a list of
//!   [`SyntaxError`]s. Parsing never fails: malformed input yields a tree
//!   with error nodes, so tools can keep working on a document while it is
//!   being edited.
//! - [`lower`] derives the [`ast`] that the rest of the blog engine consumes.
//!
//! The parser may panic if it stops making progress, which is a bug in the
//! grammar. A long-running caller such as a language server should wrap
//! [`parse`] in [`std::panic::catch_unwind`] and keep its previous tree.

pub mod ast;
pub mod dump;
mod error;
mod grammar;
mod kind;
pub mod lexer;
mod lower;
mod parser;
pub mod registry;
mod tree;

pub use error::{ErrorKind, SyntaxError};
pub use kind::SyntaxKind;
pub use lower::lower;
pub use tree::{Children, NodeId, TextRange, Tree};

/// The result of parsing: a tree that covers every byte of the source, and
/// the errors found on the way, ordered by position.
#[derive(Clone, Debug)]
pub struct Parse {
    pub tree: Tree,
    pub errors: Vec<SyntaxError>,
}

impl Parse {
    /// Renders the tree and the errors, for tests and debugging.
    pub fn dump(&self, src: &str) -> String {
        let mut out = self.tree.dump(src);
        if !self.errors.is_empty() {
            out.push_str("errors:\n");
            for error in &self.errors {
                out.push_str(&format!("  {error}\n"));
            }
        }
        out
    }
}

/// Parses a document.
///
/// # Panics
///
/// Panics if `src` is longer than 4 GiB, or on a bug in the grammar.
pub fn parse(src: &str) -> Parse {
    let mut parser = parser::Parser::new(src);
    grammar::document(&mut parser);
    let (tree, errors) = parser.finish();
    Parse { tree, errors }
}
