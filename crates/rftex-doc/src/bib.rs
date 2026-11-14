//! The bibliography: a parser for a subset of BibTeX.
//!
//! Supported:
//!
//! - field values in braces, with nested braces, and bare numbers;
//! - text between entries, which is a comment;
//! - `@comment`, `@preamble` and `@string`, which are skipped;
//! - a comma after the last field.
//!
//! Not supported: `@string` macros, `#` concatenation and values in double
//! quotes.
//!
//! Each kind of entry has its own type that says which fields it must have,
//! so an [`Entry`] is known to be complete. An entry of an unknown kind or
//! without a required field is an error. An error costs the entry it is in;
//! the parser goes on with the next one.

use rftex_syntax::TextRange;

use crate::diagnostic::Diagnostic;

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Book {
    pub key: String,
    pub author: String,
    pub title: String,
    pub year: Option<String>,
    pub url: Option<String>,
    pub isbn: Option<String>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Article {
    pub key: String,
    pub author: String,
    pub title: String,
    pub journal: Option<String>,
    pub year: Option<String>,
    pub url: Option<String>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Phdthesis {
    pub key: String,
    pub author: String,
    pub title: String,
    pub school: Option<String>,
    pub year: Option<String>,
    pub url: Option<String>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Blog {
    pub key: String,
    pub title: String,
    pub author: Option<String>,
    pub url: String,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Podcast {
    pub key: String,
    pub title: String,
    pub author: Option<String>,
    pub url: String,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Talk {
    pub key: String,
    pub author: String,
    pub title: String,
    pub year: Option<String>,
    pub url: Option<String>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Misc {
    pub key: String,
    pub title: String,
    pub author: Option<String>,
    pub year: Option<String>,
    pub url: Option<String>,
}

/// One entry of the bibliography.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Entry {
    Book(Book),
    Article(Article),
    Phdthesis(Phdthesis),
    Blog(Blog),
    Talk(Talk),
    Podcast(Podcast),
    Misc(Misc),
}

impl Entry {
    /// The key that `\bibref` refers to.
    pub fn key(&self) -> &str {
        match self {
            Entry::Book(entry) => &entry.key,
            Entry::Article(entry) => &entry.key,
            Entry::Phdthesis(entry) => &entry.key,
            Entry::Blog(entry) => &entry.key,
            Entry::Talk(entry) => &entry.key,
            Entry::Podcast(entry) => &entry.key,
            Entry::Misc(entry) => &entry.key,
        }
    }

    pub fn title(&self) -> &str {
        match self {
            Entry::Book(entry) => &entry.title,
            Entry::Article(entry) => &entry.title,
            Entry::Phdthesis(entry) => &entry.title,
            Entry::Blog(entry) => &entry.title,
            Entry::Talk(entry) => &entry.title,
            Entry::Podcast(entry) => &entry.title,
            Entry::Misc(entry) => &entry.title,
        }
    }

    pub fn author(&self) -> Option<&str> {
        match self {
            Entry::Book(entry) => Some(&entry.author),
            Entry::Article(entry) => Some(&entry.author),
            Entry::Phdthesis(entry) => Some(&entry.author),
            Entry::Talk(entry) => Some(&entry.author),
            Entry::Blog(entry) => entry.author.as_deref(),
            Entry::Podcast(entry) => entry.author.as_deref(),
            Entry::Misc(entry) => entry.author.as_deref(),
        }
    }

    pub fn url(&self) -> Option<&str> {
        match self {
            Entry::Blog(entry) => Some(&entry.url),
            Entry::Podcast(entry) => Some(&entry.url),
            Entry::Book(entry) => entry.url.as_deref(),
            Entry::Article(entry) => entry.url.as_deref(),
            Entry::Phdthesis(entry) => entry.url.as_deref(),
            Entry::Talk(entry) => entry.url.as_deref(),
            Entry::Misc(entry) => entry.url.as_deref(),
        }
    }
}

/// The result of parsing a bibliography: the entries that are well-formed,
/// in source order, and the errors found in the others.
#[derive(Clone, Debug, Default)]
pub struct Bibliography {
    pub entries: Vec<Entry>,
    pub diagnostics: Vec<Diagnostic>,
}

/// Parses a BibTeX file.
pub fn parse(src: &str) -> Bibliography {
    let mut parser = Parser { src, pos: 0 };
    let mut bibliography = Bibliography::default();
    // Everything up to the next `@` is a comment.
    while let Some(offset) = src[parser.pos..].find('@') {
        parser.pos += offset;
        let start = parser.pos;
        match parser.item() {
            Ok(Some(raw)) => match raw.classify() {
                Ok(entry) => bibliography.entries.push(entry),
                Err(diagnostics) => bibliography.diagnostics.extend(diagnostics),
            },
            Ok(None) => {}
            Err(diagnostic) => {
                bibliography.diagnostics.push(diagnostic);
                parser.recover(start);
            }
        }
    }
    bibliography
}

const KINDS: [&str; 7] = [
    "book",
    "article",
    "phdthesis",
    "blog",
    "talk",
    "podcast",
    "misc",
];

/// An entry as written: any kind, any fields.
struct RawEntry<'a> {
    /// The kind in lower case.
    kind: String,
    /// The range of `@kind`.
    kind_range: TextRange,
    key: &'a str,
    key_range: TextRange,
    fields: Vec<(&'a str, &'a str)>,
}

impl RawEntry<'_> {
    /// The value of a field. Field names are case-insensitive, and the first
    /// of several fields with one name wins.
    fn field(&self, name: &str) -> Option<String> {
        self.fields
            .iter()
            .find(|(field, _)| field.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.to_string())
    }

    fn classify(&self) -> Result<Entry, Vec<Diagnostic>> {
        let mut missing = Vec::new();
        let mut require = |name: &'static str| {
            self.field(name).unwrap_or_else(|| {
                missing.push(name);
                String::new()
            })
        };
        let key = self.key.to_string();
        let entry = match self.kind.as_str() {
            "book" => Entry::Book(Book {
                key,
                author: require("author"),
                title: require("title"),
                year: self.field("year"),
                url: self.field("url"),
                isbn: self.field("isbn"),
            }),
            "article" => Entry::Article(Article {
                key,
                author: require("author"),
                title: require("title"),
                journal: self.field("journal"),
                year: self.field("year"),
                url: self.field("url"),
            }),
            "phdthesis" => Entry::Phdthesis(Phdthesis {
                key,
                author: require("author"),
                title: require("title"),
                school: self.field("school"),
                year: self.field("year"),
                url: self.field("url"),
            }),
            "blog" => Entry::Blog(Blog {
                key,
                title: require("title"),
                author: self.field("author"),
                url: require("url"),
            }),
            "podcast" => Entry::Podcast(Podcast {
                key,
                title: require("title"),
                author: self.field("author"),
                url: require("url"),
            }),
            "talk" => Entry::Talk(Talk {
                key,
                author: require("author"),
                title: require("title"),
                year: self.field("year"),
                url: self.field("url"),
            }),
            "misc" => Entry::Misc(Misc {
                key,
                title: require("title"),
                author: self.field("author"),
                year: self.field("year"),
                url: self.field("url"),
            }),
            kind => {
                return Err(vec![Diagnostic::new(
                    self.kind_range,
                    format!("unknown entry type `@{kind}`"),
                )
                .with_help(format!("known types: {}", KINDS.join(", ")))]);
            }
        };
        if missing.is_empty() {
            return Ok(entry);
        }
        Err(missing
            .into_iter()
            .map(|field| {
                Diagnostic::new(
                    self.key_range,
                    format!(
                        "@{}{{{}}}: missing required field `{field}`",
                        self.kind, self.key
                    ),
                )
            })
            .collect())
    }
}

fn is_key_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b':' | b'.')
}

fn is_field_name_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-')
}

struct Parser<'a> {
    src: &'a str,
    pos: usize,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<u8> {
        self.src.as_bytes().get(self.pos).copied()
    }

    fn range(&self, start: usize) -> TextRange {
        TextRange::new(start as u32, self.pos as u32)
    }

    /// The range of the next character; empty at the end of the input.
    fn here(&self) -> TextRange {
        let len = self.src[self.pos..]
            .chars()
            .next()
            .map_or(0, char::len_utf8);
        TextRange::new(self.pos as u32, (self.pos + len) as u32)
    }

    fn take_while(&mut self, accept: impl Fn(u8) -> bool) -> &'a str {
        let start = self.pos;
        while self.peek().is_some_and(&accept) {
            self.pos += 1;
        }
        &self.src[start..self.pos]
    }

    fn skip_whitespace(&mut self) {
        self.take_while(|byte| matches!(byte, b' ' | b'\n' | b'\r' | b'\t'));
    }

    /// Skips whitespace and then the given character.
    fn expect(&mut self, expected: u8) -> Result<(), Diagnostic> {
        self.skip_whitespace();
        if self.peek() == Some(expected) {
            self.pos += 1;
            Ok(())
        } else {
            Err(Diagnostic::new(
                self.here(),
                format!("expected `{}`", expected as char),
            ))
        }
    }

    /// Reads up to the brace that closes the one before the current
    /// position, and past it. Returns the text in between.
    fn braced(&mut self) -> Result<&'a str, Diagnostic> {
        let start = self.pos;
        let mut depth = 0u32;
        while let Some(byte) = self.peek() {
            self.pos += 1;
            match byte {
                b'{' => depth += 1,
                b'}' if depth > 0 => depth -= 1,
                b'}' => return Ok(&self.src[start..self.pos - 1]),
                _ => {}
            }
        }
        let opener = TextRange::new(start as u32 - 1, start as u32);
        Err(Diagnostic::new(opener, "missing closing `}`").with_label("this brace is never closed"))
    }

    /// Parses what starts at `@`. Returns `None` for the kinds that are
    /// skipped.
    fn item(&mut self) -> Result<Option<RawEntry<'a>>, Diagnostic> {
        let start = self.pos;
        self.pos += 1;
        let kind = self.take_while(|byte| byte.is_ascii_alphabetic());
        let kind_range = self.range(start);
        if kind.is_empty() {
            return Err(Diagnostic::new(
                kind_range,
                "expected an entry type after `@`",
            ));
        }
        let kind = kind.to_ascii_lowercase();
        self.expect(b'{')?;
        if matches!(kind.as_str(), "comment" | "preamble" | "string") {
            self.braced()?;
            return Ok(None);
        }

        self.skip_whitespace();
        let key_start = self.pos;
        let key = self.take_while(is_key_char);
        let key_range = self.range(key_start);
        if key.is_empty() {
            return Err(Diagnostic::new(self.here(), "expected an entry key"));
        }
        self.expect(b',')?;

        let mut fields = Vec::new();
        loop {
            self.skip_whitespace();
            let name = self.take_while(is_field_name_char);
            if name.is_empty() {
                break;
            }
            self.expect(b'=')?;
            self.skip_whitespace();
            let value = match self.peek() {
                Some(b'{') => {
                    self.pos += 1;
                    self.braced()?
                }
                Some(byte) if byte.is_ascii_digit() => {
                    self.take_while(|byte| byte.is_ascii_digit())
                }
                _ => {
                    return Err(Diagnostic::new(self.here(), "expected a field value")
                        .with_label("expected `{...}` or a number"));
                }
            };
            fields.push((name, value));
            self.skip_whitespace();
            if self.peek() != Some(b',') {
                break;
            }
            self.pos += 1;
        }
        self.expect(b'}')?;
        Ok(Some(RawEntry {
            kind,
            kind_range,
            key,
            key_range,
            fields,
        }))
    }

    /// Moves to the next line that starts with `@` after an entry that
    /// starts at `start` turned out to be broken.
    fn recover(&mut self, start: usize) {
        let from = self.pos.max(start + 1).min(self.src.len());
        let rest = &self.src.as_bytes()[from..];
        self.pos = match rest.windows(2).position(|pair| pair == b"\n@") {
            Some(offset) => from + offset + 1,
            None => self.src.len(),
        };
    }
}

#[cfg(test)]
mod tests;
