//! Syntax errors.

use std::fmt;

use crate::tree::TextRange;

/// What went wrong. The message is rendered on demand, so tests and tools can
/// match on the kind.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ErrorKind {
    /// A backslash followed by a character that cannot be escaped.
    InvalidEscape,
    /// `&` outside a table or `align*`.
    UnexpectedAmp,
    /// A token that cannot appear at this point.
    UnexpectedToken,
    /// `}` without a matching `{`.
    UnmatchedCloseBrace,
    /// `\end{name}` without a matching `\begin{name}`.
    UnmatchedEnd,
    /// `\]` or `$` that closes nothing, or `\[` inside math.
    UnmatchedMathDelimiter,
    /// `{` whose `}` is missing. Reported at the opening brace.
    UnclosedBrace,
    /// `[` whose `]` is missing. Reported at the opening bracket.
    UnclosedBracket,
    /// `$` or `\[` whose closing delimiter is missing. Reported at the opener.
    UnclosedMath,
    /// `\begin{name}` whose `\end{name}` is missing. Reported at `\begin`.
    UnclosedEnvironment,
    /// `\begin` without a well-formed `{name}`.
    ExpectedEnvironmentName,
    /// A command with fewer braced arguments than it requires.
    MissingArgument,
    /// An argument that should hold a symbol, number, URL or column
    /// specification and holds nothing of the kind.
    ExpectedArgumentValue,
    /// Extra characters after the value of an argument.
    UnexpectedInArgument,
    /// A number argument that is not an integer.
    InvalidNumber,
    /// `\multicolumn` whose alignment is not exactly one of `l`, `r`, `c`.
    InvalidMulticolumnAlignment,
    /// An option list that is not `[name, name, ...]`.
    MalformedOptions,
    /// A character that has no meaning in math.
    UnexpectedInMath,
    /// `_` or `^` without something to attach.
    ExpectedMathAtom,
    /// `\left` or `\right` without a delimiter character.
    ExpectedDelimiter,
}

impl ErrorKind {
    pub fn message(self) -> &'static str {
        match self {
            ErrorKind::InvalidEscape => "invalid escape sequence",
            ErrorKind::UnexpectedAmp => "unexpected & outside a table",
            ErrorKind::UnexpectedToken => "unexpected input",
            ErrorKind::UnmatchedCloseBrace => "unmatched }",
            ErrorKind::UnmatchedEnd => "\\end without a matching \\begin",
            ErrorKind::UnmatchedMathDelimiter => "unmatched math delimiter",
            ErrorKind::UnclosedBrace => "missing closing }",
            ErrorKind::UnclosedBracket => "missing closing ]",
            ErrorKind::UnclosedMath => "missing closing math delimiter",
            ErrorKind::UnclosedEnvironment => "missing \\end for this environment",
            ErrorKind::ExpectedEnvironmentName => "expected an environment name in braces",
            ErrorKind::MissingArgument => "missing argument",
            ErrorKind::ExpectedArgumentValue => "missing or malformed argument value",
            ErrorKind::UnexpectedInArgument => "unexpected characters in argument",
            ErrorKind::InvalidNumber => "invalid number",
            ErrorKind::InvalidMulticolumnAlignment => {
                "\\multicolumn requires {N}{alignment}{content}"
            }
            ErrorKind::MalformedOptions => "malformed option list",
            ErrorKind::UnexpectedInMath => "unexpected character in math",
            ErrorKind::ExpectedMathAtom => "expected a subscript or superscript",
            ErrorKind::ExpectedDelimiter => "expected a delimiter",
        }
    }
}

impl fmt::Display for ErrorKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message())
    }
}

/// A syntax error at a source range. The range may be empty when something
/// is missing.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct SyntaxError {
    pub range: TextRange,
    pub kind: ErrorKind,
}

impl fmt::Display for SyntaxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.range, self.kind)
    }
}
