//! Every article and note of the blog must parse cleanly.

mod support;

use rftex_syntax::{lower, parse, SyntaxKind};
use support::*;

#[test]
fn corpus_parses_without_errors() {
    let mut failures = Vec::new();
    for path in corpus() {
        let src = read(&path);
        let result = parse(&src);
        if let Err(message) = check_invariants(&src, &result) {
            failures.push(format!("{}: {message}", path.display()));
        }
        for error in &result.errors {
            failures.push(format!("{}: {error}", path.display()));
        }
        let tree = &result.tree;
        if tree.descendants(tree.root()).any(|id| {
            matches!(
                tree.kind(id),
                SyntaxKind::ErrorTree | SyntaxKind::ErrorToken
            )
        }) {
            failures.push(format!("{}: the tree has error elements", path.display()));
        }
        let _ = lower(tree, &src);
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
