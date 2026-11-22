//! Building the site: every page, the feed and the static files, written to
//! an output directory.

use std::fs;
use std::path::Path;

use crate::feed;
use crate::pages::{self, Options};
use crate::site::{self, display, Failure, Site};

/// The files and directories of the input that are copied as they are.
pub const STATIC: [&str; 4] = ["css", "fonts", "images", "robots.txt"];

/// A generated file.
#[derive(Clone, Debug)]
pub struct Page {
    /// Relative to the output directory, with `/` as the separator.
    pub path: String,
    pub content: String,
}

/// Every generated file of the site.
pub fn pages(site: &Site, options: &Options) -> Vec<Page> {
    let mut out = Vec::new();
    let mut add = |path: String, content: String| out.push(Page { path, content });
    for (index, article) in site.articles.iter().enumerate() {
        add(
            format!("posts/{}.html", article.slug),
            pages::post_page(site, index, options),
        );
    }
    for (index, note) in site.notes.iter().enumerate() {
        add(
            format!("notes/{}.html", note.slug),
            pages::note_page(site, index, options),
        );
    }
    add("posts.html".into(), pages::post_list_page(site, options));
    add(
        "notes/index.html".into(),
        pages::note_list_page(site, options),
    );
    add(
        "feed.xml".into(),
        feed::atom(&options.root_url, &site.articles),
    );
    add("index.html".into(), pages::index_page(site, options));
    out
}

/// What a build wrote.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Summary {
    pub pages: usize,
    pub static_files: usize,
}

/// Builds the site in `input` into `output`. Files already in `output` stay
/// unless the build replaces them.
///
/// Nothing is written unless the whole site is correct. A file that cannot
/// be written does not stop the others.
pub fn build(input: &Path, output: &Path, options: &Options) -> Result<Summary, Failure> {
    let site = site::load(input)?;
    let pages = pages(&site, options);
    let mut errors = Vec::new();
    let mut summary = Summary {
        pages: 0,
        static_files: 0,
    };
    for name in STATIC {
        let src = input.join(name);
        if src.exists() {
            copy(
                &src,
                &output.join(name),
                &mut summary.static_files,
                &mut errors,
            );
        }
    }
    for page in &pages {
        let path = output.join(&page.path);
        match write(&path, &page.content) {
            Ok(()) => summary.pages += 1,
            Err(err) => errors.push(format!("cannot write {}: {err}", display(&path))),
        }
    }
    if errors.is_empty() {
        Ok(summary)
    } else {
        Err(Failure {
            errors,
            files: Vec::new(),
        })
    }
}

fn write(path: &Path, content: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, content)
}

/// Copies a file, or a directory with everything in it.
fn copy(src: &Path, dst: &Path, count: &mut usize, errors: &mut Vec<String>) {
    if !src.is_dir() {
        let copied = dst
            .parent()
            .map_or(Ok(()), fs::create_dir_all)
            .and_then(|()| fs::copy(src, dst));
        match copied {
            Ok(_) => *count += 1,
            Err(err) => errors.push(format!("cannot copy {}: {err}", display(src))),
        }
        return;
    }
    let entries = fs::create_dir_all(dst)
        .and_then(|()| fs::read_dir(src)?.collect::<std::io::Result<Vec<_>>>());
    let mut entries = match entries {
        Ok(entries) => entries,
        Err(err) => {
            errors.push(format!("cannot copy {}: {err}", display(src)));
            return;
        }
    };
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        copy(&entry.path(), &dst.join(entry.file_name()), count, errors);
    }
}
