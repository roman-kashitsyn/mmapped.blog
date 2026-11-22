//! End-to-end tests of `blogware build`.
//!
//! Byte-for-byte parity with the OCaml engine is checked by `make diff-site`,
//! which needs both engines; these tests need only this one.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use blogware::build::{self, Summary, STATIC};
use blogware::pages::Options;
use blogware::site;

const BROKEN: &str = "tests/data/broken";

/// A fresh directory for the test called `name`.
fn scratch(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(name);
    let _ = fs::remove_dir_all(&dir);
    dir
}

fn count_files(path: &Path) -> usize {
    if !path.is_dir() {
        return usize::from(path.exists());
    }
    fs::read_dir(path)
        .unwrap()
        .map(|entry| count_files(&entry.unwrap().path()))
        .sum()
}

#[test]
fn the_blog_builds() {
    let output = scratch("the_blog_builds");
    let options = Options::default();
    let summary = build::build(Path::new("../.."), &output, &options).unwrap();

    let site = site::load(Path::new("../..")).unwrap();
    let static_files = STATIC
        .iter()
        .map(|name| count_files(&Path::new("../..").join(name)))
        .sum();
    assert_eq!(
        summary,
        Summary {
            // Every article and note, the two lists, the feed and the front page.
            pages: site.articles.len() + site.notes.len() + 4,
            static_files,
        }
    );
    assert_eq!(count_files(&output), summary.pages + summary.static_files);

    for page in build::pages(&site, &options) {
        let written = fs::read_to_string(output.join(&page.path)).unwrap();
        assert!(written == page.content, "{}", page.path);
    }
    assert_eq!(
        fs::read(output.join("css/mmapped.css")).unwrap(),
        fs::read("../../css/mmapped.css").unwrap()
    );

    let index = fs::read_to_string(output.join("index.html")).unwrap();
    assert!(index.contains("<h2>Featured</h2>"), "{index}");
    assert!(index.contains("<h2>Latest</h2>"), "{index}");
    let newest = &site.articles[0];
    let posts = fs::read_to_string(output.join("posts.html")).unwrap();
    assert!(posts.contains(&format!("<a href=\"{}\">", newest.url)));
    let feed = fs::read_to_string(output.join("feed.xml")).unwrap();
    assert!(feed.contains(&format!("<id>https://mmapped.blog{}</id>", newest.url)));
}

#[test]
fn a_broken_site_writes_nothing() {
    let output = scratch("a_broken_site_writes_nothing");
    let failure = build::build(Path::new(BROKEN), &output, &Options::default()).unwrap_err();
    assert_eq!(failure.files.len(), 7);
    assert!(!output.exists());
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

#[test]
fn command_line() {
    let output = scratch("command_line");
    let out = output.to_str().unwrap();

    let (code, stdout, stderr) = blogware(&[
        "build",
        "--input",
        "../..",
        "--output",
        out,
        "--root",
        "https://preview.example/",
    ]);
    assert_eq!((code, stderr.as_str()), (Some(0), ""));
    assert!(stdout.starts_with("ok: "), "{stdout}");
    // The trailing slash of the root does not double the slashes of links.
    let feed = fs::read_to_string(output.join("feed.xml")).unwrap();
    assert!(feed.contains("<id>https://preview.example/</id>"), "{feed}");
    assert!(feed.contains("https://preview.example/posts/"), "{feed}");

    // A broken site reports what `check` reports.
    let broken = scratch("command_line_broken");
    let (code, stdout, stderr) = blogware(&[
        "build",
        "--input",
        BROKEN,
        "--output",
        broken.to_str().unwrap(),
    ]);
    assert_eq!((code, stdout.as_str()), (Some(1), ""));
    assert_eq!(
        stderr,
        fs::read_to_string("tests/data/broken.stderr").unwrap()
    );
    assert!(!broken.exists());

    for args in [
        &["build"][..],
        &["build", "--input", "../.."],
        &["build", "--output"],
        &["build", "--output", out, "--root"],
    ] {
        let (code, _, stderr) = blogware(args);
        assert_eq!(code, Some(2), "{args:?}");
        assert!(stderr.starts_with("error: "), "{stderr}");
        assert!(stderr.contains("Usage: blogware"), "{stderr}");
    }
}
