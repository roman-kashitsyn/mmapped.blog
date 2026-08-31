//! This crate provides rftex language support for the [tree-sitter] parsing library.
//!
//! rftex is the LaTeX flavor parsed by blogware, the static site generator behind
//! <https://mmapped.blog/>. The reference implementation is `blogware/lib/tex_parser.ml`
//! in that repository.
//!
//! ```
//! let code = r#"\section{intro}{Hello}"#;
//! let mut parser = tree_sitter::Parser::new();
//! parser
//!     .set_language(&tree_sitter_rftex::LANGUAGE.into())
//!     .expect("Error loading rftex parser");
//! let tree = parser.parse(code, None).unwrap();
//! assert!(!tree.root_node().has_error());
//! ```
//!
//! [tree-sitter]: https://tree-sitter.github.io/

use tree_sitter_language::LanguageFn;

extern "C" {
    fn tree_sitter_rftex() -> *const ();
}

/// The tree-sitter [`LanguageFn`] for this grammar.
pub const LANGUAGE: LanguageFn = unsafe { LanguageFn::from_raw(tree_sitter_rftex) };

/// The content of the [`node-types.json`] file for this grammar.
///
/// [`node-types.json`]: https://tree-sitter.github.io/tree-sitter/using-parsers/6-static-node-types
pub const NODE_TYPES: &str = include_str!("../../src/node-types.json");

/// The syntax highlighting query for this grammar.
pub const HIGHLIGHTS_QUERY: &str = include_str!("../../queries/highlights.scm");

/// The language injection query for this grammar.
pub const INJECTIONS_QUERY: &str = include_str!("../../queries/injections.scm");

/// The folding query for this grammar.
pub const FOLDS_QUERY: &str = include_str!("../../queries/folds.scm");
