//! Helpers shared by the integration tests.
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};

use rftex_syntax::{Parse, SyntaxKind, TextRange};

/// The repository root: two levels above this crate.
pub fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap()
}

pub fn data_dir(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/data")
        .join(name)
}

/// The `.rftex` files directly inside `dir`, sorted.
pub fn rftex_files(dir: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = fs::read_dir(dir)
        .unwrap_or_else(|err| panic!("{}: {err}", dir.display()))
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "rftex"))
        .collect();
    files.sort();
    files
}

/// Every article and note of the blog.
pub fn corpus() -> Vec<PathBuf> {
    let root = repo_root();
    let mut files = vec![root.join("index.rftex")];
    files.extend(rftex_files(&root.join("posts")));
    files.extend(rftex_files(&root.join("notes")));
    assert!(
        files.len() > 50,
        "the corpus looks incomplete: {} files",
        files.len()
    );
    files
}

pub fn read(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_else(|err| panic!("{}: {err}", path.display()))
}

/// Compares `actual` with the snapshot at `path`. With `UPDATE_SNAPSHOTS=1`
/// in the environment the snapshot is rewritten instead.
pub fn check_snapshot(path: &Path, actual: &str) -> Result<(), String> {
    if std::env::var_os("UPDATE_SNAPSHOTS").is_some() {
        fs::write(path, actual).unwrap();
        return Ok(());
    }
    match fs::read_to_string(path) {
        Ok(expected) if expected == actual => Ok(()),
        Ok(expected) => Err(format!(
            "{} is out of date (rerun with UPDATE_SNAPSHOTS=1 to accept):\n{}",
            path.display(),
            first_difference(&expected, actual)
        )),
        Err(_) => Err(format!(
            "{} is missing (rerun with UPDATE_SNAPSHOTS=1 to create it)",
            path.display()
        )),
    }
}

pub fn first_difference(expected: &str, actual: &str) -> String {
    let mut expected_lines = expected.lines();
    let mut actual_lines = actual.lines();
    for number in 1.. {
        match (expected_lines.next(), actual_lines.next()) {
            (None, None) => break,
            (e, a) if e != a => {
                return format!(
                    "line {number}:\n  expected: {}\n  actual:   {}",
                    e.unwrap_or("<end>"),
                    a.unwrap_or("<end>")
                );
            }
            _ => {}
        }
    }
    "the texts differ only in their line endings".to_string()
}

/// Checks what must hold for the result of parsing any input: tokens are
/// non-empty and tile the source without gaps, nodes span exactly their
/// children, and errors point inside the source.
pub fn check_invariants(src: &str, parse: &Parse) -> Result<(), String> {
    let tree = &parse.tree;
    let len = src.len() as u32;
    let root = tree.root();
    if tree.kind(root) != SyntaxKind::Document || tree.range(root) != TextRange::new(0, len) {
        return Err(format!(
            "bad root: {:?}@{}",
            tree.kind(root),
            tree.range(root)
        ));
    }

    let mut offset = 0;
    for id in tree.descendants(root) {
        let range = tree.range(id);
        if tree.is_token(id) {
            if range.is_empty() || range.start != offset {
                return Err(format!(
                    "token {:?}@{range} does not follow offset {offset}",
                    tree.kind(id)
                ));
            }
            if !src.is_char_boundary(range.end as usize) {
                return Err(format!(
                    "token {:?}@{range} splits a character",
                    tree.kind(id)
                ));
            }
            offset = range.end;
        } else {
            let mut children = tree.children(id).peekable();
            let start = children
                .peek()
                .map_or(range.start, |&first| tree.range(first).start);
            let end = children
                .last()
                .map_or(range.end, |last| tree.range(last).end);
            if (start, end) != (range.start, range.end) {
                return Err(format!(
                    "node {:?}@{range} does not span its children",
                    tree.kind(id)
                ));
            }
        }
        if id != root && tree.parent(id).is_none() {
            return Err(format!("{:?}@{range} has no parent", tree.kind(id)));
        }
    }
    if offset != len {
        return Err(format!("tokens cover {offset} of {len} bytes"));
    }
    for error in &parse.errors {
        if error.range.end > len || error.range.start > error.range.end {
            return Err(format!("error out of bounds: {error}"));
        }
    }
    Ok(())
}
