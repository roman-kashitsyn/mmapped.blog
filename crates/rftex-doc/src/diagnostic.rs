//! Diagnostics: what is wrong with a source file, and where.
//!
//! A diagnostic is plain data. How it is shown (in a terminal, in a browser,
//! in an editor) is up to the caller.

use rftex_syntax::{SyntaxError, TextRange};

/// One mistake in a source file. Every diagnostic is an error: a site with
/// diagnostics is not published.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Diagnostic {
    /// The offending piece of the source. May be empty when something is
    /// missing.
    pub range: TextRange,
    /// What is wrong, in one line.
    pub message: String,
    /// A remark about `range` itself, shown next to it. May be empty.
    pub label: String,
    /// Other places in the same file that explain the mistake.
    pub related: Vec<Related>,
    /// How to fix the mistake, if there is something useful to say.
    pub help: Option<String>,
}

/// A place in the source that helps to understand a [`Diagnostic`].
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Related {
    pub range: TextRange,
    pub message: String,
}

impl Diagnostic {
    pub fn new(range: TextRange, message: impl Into<String>) -> Diagnostic {
        Diagnostic {
            range,
            message: message.into(),
            label: String::new(),
            related: Vec::new(),
            help: None,
        }
    }

    pub fn with_label(mut self, label: impl Into<String>) -> Diagnostic {
        self.label = label.into();
        self
    }

    pub fn with_related(mut self, range: TextRange, message: impl Into<String>) -> Diagnostic {
        self.related.push(Related {
            range,
            message: message.into(),
        });
        self
    }

    pub fn with_help(mut self, help: impl Into<String>) -> Diagnostic {
        self.help = Some(help.into());
        self
    }
}

impl From<&SyntaxError> for Diagnostic {
    fn from(error: &SyntaxError) -> Diagnostic {
        Diagnostic::new(error.range, error.kind.message())
    }
}
