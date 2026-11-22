//! Every post and note page must be byte-identical to its snapshot in
//! `tests/data/snapshots`, so that any change to the output is deliberate
//! and shows in review.
//!
//! The snapshots were first made by the OCaml engine this one replaced.
//! After a deliberate change, run with `UPDATE_SNAPSHOTS=1` (or
//! `make snapshots`) to rewrite them.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use blogware::pages::Options;
use blogware::{build, report, site};

/// The pages the snapshots leave out: they change with every post.
const EXCLUDED: [&str; 3] = ["feed.xml", "index.html", "posts.html"];

fn snapshot_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data/snapshots")
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
fn pages_match_the_snapshots() {
    let site = match site::load(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .as_path(),
    ) {
        Ok(site) => site,
        Err(failure) => panic!("{}", report::render(&failure, false)),
    };
    // The snapshots leave out the pages that change with every post; the
    // build makes them all the same.
    let rendered: Vec<(String, String)> = build::pages(&site, &Options::default())
        .into_iter()
        .map(|page| (page.path, page.content))
        .filter(|(path, _)| !EXCLUDED.contains(&path.as_str()))
        .collect();

    let root = snapshot_root();
    if std::env::var_os("UPDATE_SNAPSHOTS").is_some() {
        let _ = fs::remove_dir_all(&root);
        for (path, content) in &rendered {
            let path = root.join(path);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, content).unwrap();
        }
        return;
    }
    let mut expected_paths = BTreeSet::new();
    files(&root, &root, &mut expected_paths);
    let rendered_paths: BTreeSet<String> = rendered.iter().map(|(path, _)| path.clone()).collect();
    let snapshot_paths: BTreeSet<String> = expected_paths
        .into_iter()
        .filter(|path| !EXCLUDED.contains(&path.as_str()))
        .collect();
    assert_eq!(
        rendered_paths, snapshot_paths,
        "the set of pages differs (rerun with UPDATE_SNAPSHOTS=1 to accept)"
    );

    let mut failures = Vec::new();
    for (path, actual) in &rendered {
        let expected = fs::read_to_string(root.join(path)).unwrap();
        if &expected != actual {
            failures.push(format!("{path}: {}", first_difference(&expected, actual)));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} pages differ (rerun with UPDATE_SNAPSHOTS=1 to accept):\n{}",
        failures.len(),
        rendered.len(),
        failures.join("\n")
    );
}
