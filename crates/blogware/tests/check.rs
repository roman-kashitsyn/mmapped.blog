//! End-to-end tests of `blogware check`.
//!
//! Cargo runs integration tests from the directory of the package, so the
//! paths below, and the paths in the expected output, are relative to it.

use std::fs;
use std::path::Path;
use std::process::Command;

use blogware::{report, site};

/// A site in which every kind of mistake occurs.
const BROKEN: &str = "tests/data/broken";

/// Compares `actual` with the snapshot at `path`. With `UPDATE_SNAPSHOTS=1`
/// in the environment the snapshot is rewritten instead.
fn check_snapshot(path: &str, actual: &str) {
    if std::env::var_os("UPDATE_SNAPSHOTS").is_some() {
        fs::write(path, actual).unwrap();
        return;
    }
    let expected = fs::read_to_string(path)
        .unwrap_or_else(|_| panic!("{path} is missing (rerun with UPDATE_SNAPSHOTS=1)"));
    assert!(
        expected == actual,
        "{path} is out of date (rerun with UPDATE_SNAPSHOTS=1 to accept):\n{actual}"
    );
}

fn blogware(args: &[&str]) -> (Option<i32>, String, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_blogware"))
        .args(args)
        .output()
        .unwrap();
    (
        output.status.code(),
        String::from_utf8(output.stdout).unwrap(),
        String::from_utf8(output.stderr).unwrap(),
    )
}

/// The gate of the migration: the blog itself has no errors.
#[test]
fn the_blog_checks_clean() {
    let site = match site::load(Path::new("../..")) {
        Ok(site) => site,
        Err(failure) => panic!("{}", report::render(&failure, false)),
    };
    assert!(site.articles.len() > 50, "{} articles", site.articles.len());
    assert!(site.notes.len() > 10, "{} notes", site.notes.len());
    assert!(site.bib.len() > 10, "{} entries", site.bib.len());

    // Newest first.
    let slugs: Vec<&str> = site
        .articles
        .iter()
        .map(|article| article.slug.as_str())
        .collect();
    let mut sorted = slugs.clone();
    sorted.sort();
    sorted.reverse();
    assert_eq!(slugs, sorted);
    assert_eq!(site.index.slug, "index");
}

#[test]
fn every_error_of_a_broken_site_is_reported() {
    let failure = site::load(Path::new(BROKEN)).unwrap_err();
    check_snapshot("tests/data/broken.stderr", &report::render(&failure, false));
}

#[test]
fn a_broken_document_is_still_a_reference_target() {
    let failure = site::load(Path::new(BROKEN)).unwrap_err();
    let files: Vec<&str> = failure
        .files
        .iter()
        .map(|file| file.path.as_str())
        .collect();
    // `01-good` refers to both broken posts and to the broken note, and is
    // not among the files with errors.
    assert_eq!(
        files,
        [
            "tests/data/broken/index.rftex",
            "tests/data/broken/library.bib",
            "tests/data/broken/notes/garden.rftex",
            "tests/data/broken/posts/02-errors.rftex",
            "tests/data/broken/posts/03-syntax.rftex",
        ]
    );
}

#[test]
fn a_file_with_syntax_errors_reports_only_those() {
    let failure = site::load(Path::new(BROKEN)).unwrap_err();
    let file = failure
        .files
        .iter()
        .find(|file| file.path.ends_with("03-syntax.rftex"))
        .unwrap();
    let messages: Vec<&str> = file
        .diagnostics
        .iter()
        .map(|diagnostic| diagnostic.message.as_str())
        .collect();
    assert_eq!(
        messages,
        [
            "missing \\end for this environment",
            "\\end without a matching \\begin",
            "missing closing }",
        ]
    );
}

#[test]
fn a_directory_that_is_not_a_site() {
    let failure = site::load(Path::new("tests/data/no-such-site")).unwrap_err();
    assert_eq!(
        failure.errors,
        [
            "posts directory not found: tests/data/no-such-site/posts",
            "index file not found: tests/data/no-such-site/index.rftex",
        ]
    );
    assert_eq!(
        report::render(&failure, false),
        "error: posts directory not found: tests/data/no-such-site/posts\n\n\
         error: index file not found: tests/data/no-such-site/index.rftex\n\n\
         2 errors\n"
    );
}

#[test]
fn command_line() {
    let (code, stdout, stderr) = blogware(&["check", "--input", "../.."]);
    assert_eq!((code, stderr.as_str()), (Some(0), ""));
    assert!(stdout.starts_with("ok: "), "{stdout}");

    // Errors go to stderr, without colors when it is not a terminal, and
    // fail the command.
    let (code, stdout, stderr) = blogware(&["check", "--input", BROKEN]);
    assert_eq!((code, stdout.as_str()), (Some(1), ""));
    check_snapshot("tests/data/broken.stderr", &stderr);

    for args in [
        &[][..],
        &["frobnicate"],
        &["check", "--input"],
        &["check", "--output", "x"],
        &["check", "extra"],
    ] {
        let (code, _, stderr) = blogware(args);
        assert_eq!(code, Some(2), "{args:?}");
        assert!(stderr.starts_with("error: "), "{stderr}");
        assert!(stderr.contains("Usage: blogware"), "{stderr}");
    }

    let (code, stdout, _) = blogware(&["--help"]);
    assert_eq!(code, Some(0));
    assert!(stdout.starts_with("Usage: blogware"), "{stdout}");
}
