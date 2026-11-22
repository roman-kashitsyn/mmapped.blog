//! Building the site: every page, the feed and the static files, written to
//! an output directory.

use std::fs;
use std::path::{Component, Path, PathBuf};

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
        format!("notes/{}.html", site::NOTE_LIST),
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
/// Nothing is written unless the whole site is correct and `output` does not
/// overlap the static files, which would be copied onto or into themselves.
/// A file that cannot be written does not stop the others.
pub fn build(input: &Path, output: &Path, options: &Options) -> Result<Summary, Failure> {
    let site = match (site::load(input), overlap(input, output)) {
        (Ok(site), None) => site,
        (loaded, clash) => {
            let mut failure = loaded.err().unwrap_or_default();
            failure.errors.splice(0..0, clash);
            return Err(failure);
        }
    };
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

/// Explains why `output` cannot hold a build of `input`: some static file or
/// directory would be its own copy, or contain it.
fn overlap(input: &Path, output: &Path) -> Option<String> {
    let clashes: Vec<String> = STATIC
        .iter()
        .map(|name| (input.join(name), output.join(name)))
        .filter(|(src, _)| src.exists())
        .filter(|(src, dst)| {
            let (src, dst) = (resolve(src), resolve(dst));
            src.starts_with(&dst) || dst.starts_with(&src)
        })
        .map(|(src, _)| display(&src))
        .collect();
    (!clashes.is_empty()).then(|| {
        format!(
            "cannot build into {}: the output overlaps the static files {}",
            display(output),
            clashes.join(", ")
        )
    })
}

/// The absolute path that `path` names, without symbolic links, `.` or
/// `..`, as it will be once its missing directories are created.
fn resolve(path: &Path) -> PathBuf {
    for existing in path.ancestors() {
        let dir = if existing.as_os_str().is_empty() {
            Path::new(".")
        } else {
            existing
        };
        let Ok(mut resolved) = dir.canonicalize() else {
            continue;
        };
        // A missing directory is no symbolic link, so its `..` is its parent.
        let missing = path.strip_prefix(existing).unwrap_or(path);
        for component in missing.components() {
            match component {
                Component::ParentDir => {
                    resolved.pop();
                }
                Component::Normal(name) => resolved.push(name),
                _ => {}
            }
        }
        return resolved;
    }
    path.to_path_buf()
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
