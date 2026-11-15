//! Loading the sources of the site.
//!
//! A site is a directory with this layout:
//!
//! ```text
//! index.rftex      the front page
//! posts/*.rftex    articles
//! notes/*.rftex    notes (optional)
//! library.bib      the bibliography (optional)
//! ```
//!
//! [`load`] reads all of it, or explains everything that is wrong with it.

use std::fs;
use std::path::Path;

use rftex_doc::bib::{self, Entry};
use rftex_doc::document::{Article, Note};
use rftex_doc::refs::{section_anchors, Index};
use rftex_doc::{Analysis, Diagnostic};

/// The documents of a site, all of them correct.
#[derive(Clone, Debug)]
pub struct Site {
    pub bib: Vec<Entry>,
    /// Ordered by file name, last first. File names start with the number of
    /// the post, so this is newest first.
    pub articles: Vec<Article>,
    /// Ordered by file name.
    pub notes: Vec<Note>,
    /// The front page.
    pub index: Article,
}

/// The mistakes in one source file.
#[derive(Clone, Debug)]
pub struct FileErrors {
    pub path: String,
    pub source: String,
    /// Ordered by position. Never empty.
    pub diagnostics: Vec<Diagnostic>,
}

/// Why a site cannot be loaded.
#[derive(Clone, Debug, Default)]
pub struct Failure {
    /// Problems that have no place in a source: a missing directory, a file
    /// that cannot be read.
    pub errors: Vec<String>,
    /// Ordered by path.
    pub files: Vec<FileErrors>,
}

impl Failure {
    pub fn is_empty(&self) -> bool {
        self.errors.is_empty() && self.files.is_empty()
    }

    /// The number of problems.
    pub fn error_count(&self) -> usize {
        let in_files: usize = self.files.iter().map(|file| file.diagnostics.len()).sum();
        self.errors.len() + in_files
    }
}

/// A source file and what the analysis made of it.
struct Loaded<T> {
    path: String,
    source: String,
    analysis: Analysis<T>,
}

/// The path as shown to the user: without the `./` of the default input
/// directory.
fn display(path: &Path) -> String {
    path.strip_prefix(".")
        .unwrap_or(path)
        .to_string_lossy()
        .into_owned()
}

fn read(path: &Path) -> Result<String, String> {
    fs::read_to_string(path).map_err(|err| format!("cannot read {}: {err}", display(path)))
}

/// The names of the `.rftex` files in a directory, sorted.
fn rftex_files(dir: &Path) -> Result<Vec<String>, String> {
    let entries =
        fs::read_dir(dir).map_err(|err| format!("cannot read {}: {err}", display(dir)))?;
    let mut names: Vec<String> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with(".rftex"))
        .collect();
    names.sort();
    Ok(names)
}

/// The slug of a document: the name of its file without the extension.
fn slug(path: &Path) -> String {
    path.file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Loads and analyzes one document.
fn load_document<T>(
    path: &Path,
    analyze: fn(&str, &str) -> Analysis<T>,
) -> Result<Loaded<T>, String> {
    let source = read(path)?;
    let analysis = analyze(&slug(path), &source);
    Ok(Loaded {
        path: display(path),
        source,
        analysis,
    })
}

/// Loads the given files of a directory, collecting the ones that cannot be
/// read into `failure`.
fn load_documents<T>(
    dir: &Path,
    names: &[String],
    analyze: fn(&str, &str) -> Analysis<T>,
    failure: &mut Failure,
) -> Vec<Loaded<T>> {
    names
        .iter()
        .filter_map(|name| {
            load_document(&dir.join(name), analyze)
                .map_err(|err| failure.errors.push(err))
                .ok()
        })
        .collect()
}

/// Loads the site in the directory `input`.
///
/// A file with syntax errors reports only those. Any other file reports
/// everything that is wrong with it, including the references that resolve
/// to nothing on the site.
pub fn load(input: &Path) -> Result<Site, Failure> {
    let mut failure = Failure::default();

    // The bibliography. Without the file, the site has no entries.
    let bib_path = input.join("library.bib");
    let mut bib = Some(Vec::new());
    if bib_path.is_file() {
        match read(&bib_path) {
            Ok(source) => {
                let bibliography = bib::parse(&source);
                if bibliography.diagnostics.is_empty() {
                    bib = Some(bibliography.entries);
                } else {
                    bib = None;
                    failure.files.push(FileErrors {
                        path: display(&bib_path),
                        source,
                        diagnostics: bibliography.diagnostics,
                    });
                }
            }
            Err(err) => {
                bib = None;
                failure.errors.push(err);
            }
        }
    }

    let posts_dir = input.join("posts");
    let mut post_names = Vec::new();
    if posts_dir.is_dir() {
        match rftex_files(&posts_dir) {
            Ok(names) => post_names = names,
            Err(err) => failure.errors.push(err),
        }
        post_names.reverse();
    } else {
        failure.errors.push(format!(
            "posts directory not found: {}",
            display(&posts_dir)
        ));
    }
    let articles = load_documents(
        &posts_dir,
        &post_names,
        rftex_doc::analyze_article,
        &mut failure,
    );

    let notes_dir = input.join("notes");
    let mut note_names = Vec::new();
    if notes_dir.is_dir() {
        match rftex_files(&notes_dir) {
            Ok(names) => note_names = names,
            Err(err) => failure.errors.push(err),
        }
    }
    let notes = load_documents(
        &notes_dir,
        &note_names,
        rftex_doc::analyze_note,
        &mut failure,
    );

    let index_path = input.join("index.rftex");
    let index = if index_path.is_file() {
        load_document(&index_path, rftex_doc::analyze_article)
            .map_err(|err| failure.errors.push(err))
            .ok()
    } else {
        failure
            .errors
            .push(format!("index file not found: {}", display(&index_path)));
        None
    };

    // Every article and note can be referred to by its slug, even if it has
    // errors of its own: a broken document must not break the ones that
    // point to it.
    let slugs = post_names
        .iter()
        .chain(&note_names)
        .map(|name| slug(Path::new(name)));
    let targets = Index::new(slugs, bib.as_deref());

    // The second pass: resolve the references and tell the good documents
    // from the bad.
    let articles: Vec<Article> = articles
        .into_iter()
        .filter_map(|loaded| finish(loaded, article_anchors, &targets, &mut failure))
        .collect();
    let notes: Vec<Note> = notes
        .into_iter()
        .filter_map(|loaded| finish(loaded, note_anchors, &targets, &mut failure))
        .collect();
    let index = index.and_then(|loaded| finish(loaded, no_anchors, &targets, &mut failure));

    failure.files.sort_by(|a, b| a.path.cmp(&b.path));
    match (failure.is_empty(), index, bib) {
        (true, Some(index), Some(bib)) => Ok(Site {
            bib,
            articles,
            notes,
            index,
        }),
        _ => Err(failure),
    }
}

fn article_anchors(article: &Article) -> Vec<&str> {
    section_anchors(&article.body)
}

fn note_anchors(note: &Note) -> Vec<&str> {
    section_anchors(&note.body)
}

/// The sections of the front page are not link targets.
fn no_anchors(_: &Article) -> Vec<&str> {
    Vec::new()
}

/// Checks the references of a loaded document against the site. Returns the
/// document if nothing is wrong with it, and files its errors otherwise.
fn finish<T>(
    loaded: Loaded<T>,
    anchors: fn(&T) -> Vec<&str>,
    targets: &Index,
    failure: &mut Failure,
) -> Option<T> {
    let Loaded {
        path,
        source,
        analysis,
    } = loaded;
    let mut diagnostics = analysis.diagnostics;
    let anchors = analysis.doc.as_ref().map(anchors).unwrap_or_default();
    diagnostics.extend(targets.check(&analysis.references, &anchors));
    diagnostics.sort_by_key(|diagnostic| (diagnostic.range.start, diagnostic.range.end));
    if diagnostics.is_empty() {
        return analysis.doc;
    }
    failure.files.push(FileErrors {
        path,
        source,
        diagnostics,
    });
    None
}
