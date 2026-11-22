//! End-to-end tests of `blogware build`.
//!
//! The content of the pages is compared with their snapshots in
//! `tests/snapshots.rs`; these tests check what the build writes, and where.

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
    assert_eq!(failure.files.len(), 8);
    assert!(!output.exists());
}

/// A correct site with one post and two static files, in a fresh directory.
fn tiny_site(name: &str) -> PathBuf {
    let site = scratch(name);
    let files = [
        (
            "index.rftex",
            "\\documentclass{article}\n\\title{Home}\n\\begin{document}\nHello.\n\\end{document}\n",
        ),
        (
            "posts/01-hello.rftex",
            "\\documentclass{article}\n\\title{Hello}\n\\date{2024-01-01}\n\
             \\begin{document}\nHello.\n\\end{document}\n",
        ),
        ("robots.txt", "User-agent: *\n"),
        ("images/logo.svg", "<svg/>\n"),
    ];
    for (path, content) in files {
        let path = site.join(path);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }
    site
}

#[test]
fn the_output_cannot_overlap_the_static_files() {
    let site = tiny_site("the_output_cannot_overlap_the_static_files");
    let options = Options::default();
    let refused = |output: &Path| {
        let failure = build::build(&site, output, &options).unwrap_err();
        assert!(failure.files.is_empty());
        failure.errors
    };

    // The input itself: every static file would be copied onto itself.
    assert_eq!(
        refused(&site),
        [format!(
            "cannot build into {0}: the output overlaps the static files \
             {0}/images, {0}/robots.txt",
            site.display()
        )]
    );
    // Inside a static directory, which would be copied into itself, however
    // the path is spelled.
    for output in [
        site.join("images/preview"),
        site.join("posts/../images/preview"),
        site.join("missing/../images"),
    ] {
        let errors = refused(&output);
        assert_eq!(errors.len(), 1, "{errors:?}");
        assert!(errors[0].ends_with("images"), "{errors:?}");
    }
    assert_eq!(
        fs::read_to_string(site.join("robots.txt")).unwrap(),
        "User-agent: *\n"
    );
    assert!(!site.join("index.html").exists());
    assert!(!site.join("images/preview").exists());
    assert!(!site.join("missing").exists());

    // A directory of its own inside the input is fine.
    let summary = build::build(&site, &site.join("_site"), &options).unwrap();
    assert_eq!(summary.static_files, 2);
    assert!(site.join("_site/images/logo.svg").is_file());

    // With a broken site, both kinds of problems are reported.
    fs::write(site.join("posts/02-broken.rftex"), "\\begin{document}\n").unwrap();
    let failure = build::build(&site, &site, &options).unwrap_err();
    assert_eq!(failure.errors.len(), 1);
    assert!(failure.errors[0].starts_with("cannot build into"));
    assert_eq!(failure.files.len(), 1);
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

    // Building a site into itself.
    let site = tiny_site("command_line_overlap");
    let (code, stdout, stderr) = blogware(&[
        "build",
        "--input",
        site.to_str().unwrap(),
        "--output",
        site.join(".").to_str().unwrap(),
    ]);
    assert_eq!((code, stdout.as_str()), (Some(1), ""));
    assert!(stderr.starts_with("error: cannot build into "), "{stderr}");
    assert!(!site.join("index.html").exists());

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
