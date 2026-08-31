//! The fidelity gate: every real `.rftex` file in the blog must parse with no ERROR
//! and no MISSING node, and every shipped query must compile against the grammar.

use std::path::{Path, PathBuf};

fn parser() -> tree_sitter::Parser {
    let mut parser = tree_sitter::Parser::new();
    parser
        .set_language(&tree_sitter_rftex::LANGUAGE.into())
        .expect("Error loading rftex parser");
    parser
}

/// Repository root, i.e. the parent of this crate's directory.
fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("crate directory has a parent")
        .to_path_buf()
}

fn rftex_files() -> Vec<PathBuf> {
    let root = repo_root();
    let mut files = Vec::new();
    for dir in ["posts", "notes"] {
        let Ok(entries) = std::fs::read_dir(root.join(dir)) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().is_some_and(|e| e == "rftex") {
                files.push(path);
            }
        }
    }
    let index = root.join("index.rftex");
    if index.exists() {
        files.push(index);
    }
    files.sort();
    files
}

/// Names the first offending node so a failure points at a line, not just a file.
fn first_problem(node: tree_sitter::Node) -> Option<(String, tree_sitter::Point)> {
    let mut cursor = node.walk();
    let mut stack = vec![node];
    while let Some(node) = stack.pop() {
        if node.is_error() || node.is_missing() {
            let kind = if node.is_missing() { "MISSING" } else { "ERROR" };
            return Some((format!("{kind} {}", node.kind()), node.start_position()));
        }
        stack.extend(node.children(&mut cursor));
    }
    None
}

#[test]
fn parses_the_whole_blog_without_errors() {
    let files = rftex_files();
    assert!(
        !files.is_empty(),
        "no .rftex files found under {}",
        repo_root().display()
    );

    let mut parser = parser();
    let mut failures = Vec::new();
    for path in &files {
        let source = std::fs::read_to_string(path).expect("readable source file");
        let tree = parser.parse(&source, None).expect("parser returns a tree");
        if let Some((kind, point)) = first_problem(tree.root_node()) {
            failures.push(format!(
                "{}:{}:{}: {kind}",
                path.display(),
                point.row + 1,
                point.column + 1
            ));
        }
    }

    assert!(
        failures.is_empty(),
        "{} of {} files failed to parse:\n{}",
        failures.len(),
        files.len(),
        failures.join("\n")
    );
}

#[test]
fn queries_compile() {
    let language: tree_sitter::Language = tree_sitter_rftex::LANGUAGE.into();
    for (name, source) in [
        ("highlights.scm", tree_sitter_rftex::HIGHLIGHTS_QUERY),
        ("injections.scm", tree_sitter_rftex::INJECTIONS_QUERY),
        ("folds.scm", tree_sitter_rftex::FOLDS_QUERY),
    ] {
        tree_sitter::Query::new(&language, source)
            .unwrap_or_else(|e| panic!("{name} failed to compile: {e}"));
    }
}

#[test]
fn url_arguments_keep_percent_and_ampersand() {
    // The one place a generic `{group}` would be wrong: `%` would start a comment.
    let source = r"\href{https://x.io/a?b=1&c=2%20d#f}{t}";
    let tree = parser().parse(source, None).unwrap();
    let root = tree.root_node();
    assert!(first_problem(root).is_none());

    let url_command = root.child(0).expect("a url_command");
    assert_eq!(url_command.kind(), "url_command");
    let url_group = url_command
        .child_by_field_name("url")
        .expect("a url field on the url_command");
    let url = url_group.named_child(0).expect("a url node");
    assert_eq!(
        &source[url.byte_range()],
        "https://x.io/a?b=1&c=2%20d#f"
    );
}
