//! The gate of the port: every post and note page must be byte-identical to
//! the snapshot the OCaml engine made of it.
//!
//! The snapshots live in `blogware/test/snapshots` and belong to the OCaml
//! engine until the cutover; this test only reads them.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use blogware::pages::{self, Options};
use blogware::{report, site};

/// The pages the snapshots leave out: they change with every post.
const EXCLUDED: [&str; 3] = ["feed.xml", "index.html", "posts.html"];

fn snapshot_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../blogware/test/snapshots")
}

fn files(root: &Path, dir: &Path, out: &mut BTreeSet<String>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            files(root, &path, out);
        } else {
            let relative = path.strip_prefix(root).unwrap();
            out.insert(relative.to_string_lossy().replace('\\', "/"));
        }
    }
}

/// Where the two texts first differ, with some context.
fn first_difference(expected: &str, actual: &str) -> String {
    let offset = expected
        .bytes()
        .zip(actual.bytes())
        .position(|(e, a)| e != a)
        .unwrap_or(expected.len().min(actual.len()));
    let window = |text: &str| {
        let mut start = offset.saturating_sub(120);
        while !text.is_char_boundary(start) {
            start -= 1;
        }
        let mut end = (offset + 120).min(text.len());
        while !text.is_char_boundary(end) {
            end += 1;
        }
        text[start..end].to_string()
    };
    format!(
        "at byte {offset}:\n  expected: {:?}\n  actual:   {:?}",
        window(expected),
        window(actual)
    )
}

#[test]
fn pages_match_the_ocaml_snapshots() {
    let site = match site::load(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .as_path(),
    ) {
        Ok(site) => site,
        Err(failure) => panic!("{}", report::render(&failure, false)),
    };
    let options = Options::default();
    let mut rendered = Vec::new();
    for (index, article) in site.articles.iter().enumerate() {
        rendered.push((
            format!("posts/{}.html", article.slug),
            pages::post_page(&site, index, &options),
        ));
    }
    for (index, note) in site.notes.iter().enumerate() {
        rendered.push((
            format!("notes/{}.html", note.slug),
            pages::note_page(&site, index, &options),
        ));
    }
    rendered.push((
        "notes/index.html".to_string(),
        pages::note_list_page(&site, &options),
    ));

    let root = snapshot_root();
    let mut expected_paths = BTreeSet::new();
    files(&root, &root, &mut expected_paths);
    let rendered_paths: BTreeSet<String> = rendered.iter().map(|(path, _)| path.clone()).collect();
    let snapshot_paths: BTreeSet<String> = expected_paths
        .into_iter()
        .filter(|path| !EXCLUDED.contains(&path.as_str()))
        .collect();
    assert_eq!(rendered_paths, snapshot_paths, "the set of pages differs");

    let mut failures = Vec::new();
    for (path, actual) in &rendered {
        let expected = fs::read_to_string(root.join(path)).unwrap();
        if &expected != actual {
            failures.push(format!("{path}: {}", first_difference(&expected, actual)));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} pages differ:\n{}",
        failures.len(),
        rendered.len(),
        failures.join("\n")
    );
}
