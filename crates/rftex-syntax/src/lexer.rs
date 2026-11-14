//! The modal lexer.
//!
//! rftex cannot be tokenized up front: `%` starts a comment in text but is an
//! ordinary character in a URL, braces are literal inside `code`, and so on.
//! The parser therefore asks for one token at a time and says which [`Mode`]
//! applies at that point.
//!
//! Two rules keep error recovery workable in every mode:
//!
//! - Characters whose role depends on the surrounding construct (`&`, `[`,
//!   `]`, quotes, `\\`) are always tokens of their own. The parser decides
//!   whether they are structure or text.
//! - Every mode produces the tokens recovery relies on: braces and control
//!   words. Anything a mode cannot classify becomes an [`ErrorToken`].
//!
//! [`ErrorToken`]: SyntaxKind::ErrorToken

use crate::kind::SyntaxKind::{self, *};

/// The lexical context of the next token.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// Prose: the default.
    Text,
    /// The body of a `code` environment: only `\`, `$` and `%` are special.
    Code,
    /// Inside `$...$`, `\[...\]` and `align*`.
    Math,
    /// A braced argument holding a single value made of `Charset` characters.
    Atom(Charset),
    /// A bracketed, comma-separated list of symbols.
    Options,
}

/// The characters that make up the value of an [`Mode::Atom`] argument.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Charset {
    /// Labels, environment names, dates: letters, digits, `*`, `-`, `.`.
    Symbol,
    /// BibTeX entry keys.
    BibKey,
    /// Integer literals.
    Number,
    /// URLs. Includes `%`, `$`, `&`, `[` and `]`, which are special in text.
    Url,
    /// Column specifications: `c`, `l`, `r`, `|` and spaces.
    AlignSpec,
}

impl Charset {
    fn contains(self, c: u8) -> bool {
        match self {
            Charset::Symbol => is_symbolic(c),
            Charset::BibKey => c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_' | b':' | b'.'),
            Charset::Number => c.is_ascii_digit() || c == b'-',
            Charset::Url => {
                c.is_ascii_alphanumeric()
                    || matches!(
                        c,
                        b'-' | b'.'
                            | b'_'
                            | b'~'
                            | b':'
                            | b'/'
                            | b'?'
                            | b'#'
                            | b'['
                            | b']'
                            | b'@'
                            | b'!'
                            | b'$'
                            | b'&'
                            | b'('
                            | b')'
                            | b'*'
                            | b'+'
                            | b','
                            | b';'
                            | b'%'
                            | b'='
                            | b'\''
                    )
            }
            Charset::AlignSpec => matches!(c, b'c' | b'l' | b'r' | b'|' | b' '),
        }
    }
}

/// A token: its kind and its length in bytes. The offset is implied by the
/// tokens before it.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Token {
    pub kind: SyntaxKind,
    pub len: u32,
}

fn is_symbolic(c: u8) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, b'*' | b'-' | b'.')
}

fn is_cmd_name_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'*'
}

fn is_math_operator(c: u8) -> bool {
    matches!(
        c,
        b'+' | b'-' | b'=' | b',' | b';' | b'[' | b']' | b'|' | b'(' | b')' | b'<' | b'>' | b':'
    )
}

/// Length of the run of bytes at the start of `bytes` that satisfy `pred`.
fn run(bytes: &[u8], pred: impl Fn(u8) -> bool) -> usize {
    bytes.iter().position(|&c| !pred(c)).unwrap_or(bytes.len())
}

/// Returns the token that starts at byte `pos` of `src` when read in `mode`.
///
/// At the end of input the result is a zero-length [`Eof`]; every other token
/// is non-empty and ends on a character boundary.
pub fn next_token(src: &str, pos: usize, mode: Mode) -> Token {
    let rest = &src.as_bytes()[pos..];
    let Some(&first) = rest.first() else {
        return Token { kind: Eof, len: 0 };
    };
    let (kind, len) = match mode {
        Mode::Text => text(src, pos, rest, first),
        Mode::Code => code(src, pos, rest, first),
        Mode::Math => math(src, pos, rest, first),
        Mode::Atom(charset) => atom(src, pos, rest, first, charset),
        Mode::Options => options(src, pos, rest, first),
    };
    debug_assert!(len > 0 && src.is_char_boundary(pos + len));
    Token {
        kind,
        len: len as u32,
    }
}

/// Length in bytes of the character at `pos`.
fn char_len(src: &str, pos: usize) -> usize {
    src[pos..].chars().next().map_or(0, char::len_utf8)
}

fn comment(rest: &[u8]) -> (SyntaxKind, usize) {
    let len = match rest.iter().position(|&c| c == b'\n') {
        Some(newline) => newline + 1,
        None => rest.len(),
    };
    (Comment, len)
}

/// A token that starts with a backslash. `escapes` lists the characters that
/// form an [`Escape`] in the current mode, and `eat_space` says whether a
/// control word swallows one following space, as it does in text.
fn backslash(
    src: &str,
    pos: usize,
    rest: &[u8],
    escapes: &[u8],
    eat_space: bool,
) -> (SyntaxKind, usize) {
    match rest.get(1) {
        None => (ErrorToken, 1),
        Some(b'[') => (DisplayOpen, 2),
        Some(b']') => (DisplayClose, 2),
        Some(b'\\') => (DoubleBackslash, 2),
        Some(c) if escapes.contains(c) => (Escape, 2),
        Some(&c) if is_cmd_name_char(c) => {
            let mut len = 1 + run(&rest[1..], is_cmd_name_char);
            if eat_space && rest.get(len) == Some(&b' ') {
                len += 1;
            }
            (ControlWord, len)
        }
        Some(_) => (ErrorToken, 1 + char_len(src, pos + 1)),
    }
}

const TEXT_ESCAPES: &[u8] = b"%&#_{}\n$";
const MATH_ESCAPES: &[u8] = b"%{}^_";

fn text(src: &str, pos: usize, rest: &[u8], first: u8) -> (SyntaxKind, usize) {
    match first {
        b'\\' => backslash(src, pos, rest, TEXT_ESCAPES, true),
        b'{' => (LBrace, 1),
        b'}' => (RBrace, 1),
        b'[' => (LBracket, 1),
        b']' => (RBracket, 1),
        b'&' => (Amp, 1),
        b'$' => (Dollar, 1),
        b'%' => comment(rest),
        b'`' if rest.get(1) == Some(&b'`') => (OpenQuote, 2),
        b'`' => (Backtick, 1),
        b'\'' if rest.get(1) == Some(&b'\'') => (CloseQuote, 2),
        b'\n' if rest.get(1) == Some(&b'\n') => (ParBreak, run(rest, |c| c == b'\n')),
        _ => {
            let mut len = 1;
            while let Some(&c) = rest.get(len) {
                let next = rest.get(len + 1);
                let stop = match c {
                    b'%' | b'{' | b'}' | b'\\' | b'[' | b']' | b'&' | b'$' | b'`' => true,
                    b'\n' | b'\'' => next == Some(&c),
                    _ => false,
                };
                if stop {
                    break;
                }
                len += 1;
            }
            (Text, len)
        }
    }
}

fn code(src: &str, pos: usize, rest: &[u8], first: u8) -> (SyntaxKind, usize) {
    match first {
        b'\\' => backslash(src, pos, rest, TEXT_ESCAPES, true),
        b'$' => (Dollar, 1),
        b'%' => comment(rest),
        _ => (Text, run(rest, |c| !matches!(c, b'\\' | b'$' | b'%'))),
    }
}

fn math(src: &str, pos: usize, rest: &[u8], first: u8) -> (SyntaxKind, usize) {
    match first {
        b'\\' => backslash(src, pos, rest, MATH_ESCAPES, false),
        b'{' => (LBrace, 1),
        b'}' => (RBrace, 1),
        b'_' => (Underscore, 1),
        b'^' => (Caret, 1),
        b'$' => (Dollar, 1),
        b'&' => (Amp, 1),
        b'%' => comment(rest),
        b'\n' => (Newline, 1),
        b' ' => (Space, run(rest, |c| c == b' ')),
        c if c.is_ascii_digit() => (Number, run(rest, |c| c.is_ascii_digit())),
        c if c.is_ascii_alphabetic() => (Letter, 1),
        c if is_math_operator(c) => (Operator, 1),
        _ => {
            let known = |c: u8| {
                c.is_ascii_alphanumeric()
                    || is_math_operator(c)
                    || matches!(
                        c,
                        b'\\' | b'{' | b'}' | b'_' | b'^' | b'$' | b'&' | b'%' | b'\n' | b' '
                    )
            };
            (ErrorToken, run(rest, |c| !known(c)))
        }
    }
}

fn atom(src: &str, pos: usize, rest: &[u8], first: u8, charset: Charset) -> (SyntaxKind, usize) {
    match first {
        c if charset.contains(c) => (Atom, run(rest, |c| charset.contains(c))),
        b'{' => (LBrace, 1),
        b'}' => (RBrace, 1),
        b'\\' => backslash(src, pos, rest, TEXT_ESCAPES, true),
        b'\n' => (Newline, 1),
        _ => {
            let stop = |c: u8| charset.contains(c) || matches!(c, b'{' | b'}' | b'\\' | b'\n');
            (ErrorToken, run(rest, |c| !stop(c)))
        }
    }
}

fn options(src: &str, pos: usize, rest: &[u8], first: u8) -> (SyntaxKind, usize) {
    let is_space = |c: u8| matches!(c, b' ' | b'\t' | b'\n');
    match first {
        b'[' => (LBracket, 1),
        b']' => (RBracket, 1),
        b',' => (Comma, 1),
        b'{' => (LBrace, 1),
        b'}' => (RBrace, 1),
        b'\\' => backslash(src, pos, rest, TEXT_ESCAPES, true),
        c if is_space(c) => (Whitespace, run(rest, is_space)),
        c if is_symbolic(c) => (Atom, run(rest, is_symbolic)),
        _ => {
            let stop = |c: u8| {
                is_space(c)
                    || is_symbolic(c)
                    || matches!(c, b'[' | b']' | b',' | b'{' | b'}' | b'\\')
            };
            (ErrorToken, run(rest, |c| !stop(c)))
        }
    }
}

/// Returns the raw token that runs from `pos` up to, but not including, the
/// first occurrence of `terminator`, and whether the terminator was found.
/// Without a terminator the token runs to the end of input. The token may be
/// empty.
pub fn raw_until(src: &str, pos: usize, terminator: &str) -> (Token, bool) {
    let rest = &src[pos..];
    let (len, found) = match rest.find(terminator) {
        Some(len) => (len, true),
        None => (rest.len(), false),
    };
    (
        Token {
            kind: RawText,
            len: len as u32,
        },
        found,
    )
}

#[cfg(test)]
mod tests;
