//! Tokens, and the description of a language that the lexer works from.

use rftex_doc::document::HighlightRole as Role;

pub(super) struct StringRule {
    pub(super) quote: u8,
    pub(super) allow_newline: bool,
    /// A raw string has no escapes.
    pub(super) raw: bool,
}

pub(super) struct Lexical {
    pub(super) line_comments: &'static [&'static str],
    /// Opening and closing delimiters.
    pub(super) block_comments: &'static [(&'static str, &'static str)],
    pub(super) strings: &'static [StringRule],
    pub(super) is_ident_start: fn(u8) -> bool,
    pub(super) is_ident_part: fn(u8) -> bool,
    pub(super) is_delim: fn(u8) -> bool,
    pub(super) is_operator: fn(u8) -> bool,
}

pub(super) struct Language {
    pub(super) name: &'static str,
    pub(super) keywords: &'static [&'static str],
    pub(super) lexical: Lexical,
    /// Marks the definitions among the tokens.
    pub(super) classify: fn(&mut [Token]),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(super) enum Kind {
    Whitespace,
    Ident,
    Keyword,
    Comment,
    String,
    Delim,
    Operator,
    Unknown,
}

#[derive(Debug)]
pub(super) struct Token<'a> {
    pub(super) kind: Kind,
    pub(super) text: &'a str,
    pub(super) role: Option<Role>,
}

pub(super) fn is_whitespace(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | b'\x0C')
}

pub(super) fn is_newline(byte: u8) -> bool {
    matches!(byte, b'\n' | b'\r')
}

/// Splits text into tokens that cover it without gaps. Every token ends
/// before an ASCII character or at the end of the text, so slicing is safe.
pub(super) fn lex<'a>(language: &Language, text: &'a str) -> Vec<Token<'a>> {
    let lexical = &language.lexical;
    let bytes = text.as_bytes();
    let len = bytes.len();
    let skip_while = |mut pos: usize, accept: &dyn Fn(u8) -> bool| {
        while pos < len && accept(bytes[pos]) {
            pos += 1;
        }
        pos
    };
    let mut tokens = Vec::new();
    let mut pos = 0;
    while pos < len {
        let start = pos;
        let byte = bytes[pos];
        let rest = &text[pos..];
        let kind = if is_whitespace(byte) {
            pos = skip_while(pos, &is_whitespace);
            Kind::Whitespace
        } else if lexical
            .line_comments
            .iter()
            .any(|prefix| rest.starts_with(prefix))
        {
            pos = skip_while(pos, &|byte| !is_newline(byte));
            Kind::Comment
        } else if let Some((open, close)) = lexical
            .block_comments
            .iter()
            .find(|(open, _)| rest.starts_with(open))
        {
            pos += open.len();
            pos = match text[pos..].find(close) {
                Some(offset) => pos + offset + close.len(),
                None => len,
            };
            Kind::Comment
        } else if let Some(rule) = lexical.strings.iter().find(|rule| rule.quote == byte) {
            pos += 1;
            while pos < len {
                let byte = bytes[pos];
                if byte == rule.quote {
                    pos += 1;
                    break;
                } else if byte == b'\\' && !rule.raw {
                    pos += 1;
                    if pos < len && !(is_newline(bytes[pos]) && !rule.allow_newline) {
                        pos += 1;
                    } else if pos < len {
                        break;
                    }
                } else if is_newline(byte) && !rule.allow_newline && !rule.raw {
                    break;
                } else {
                    pos += 1;
                }
            }
            Kind::String
        } else if (lexical.is_ident_start)(byte) {
            pos = skip_while(pos + 1, &lexical.is_ident_part);
            if language.keywords.contains(&&text[start..pos]) {
                Kind::Keyword
            } else {
                Kind::Ident
            }
        } else if (lexical.is_delim)(byte) {
            pos += 1;
            Kind::Delim
        } else if (lexical.is_operator)(byte) {
            pos = skip_while(pos, &lexical.is_operator);
            Kind::Operator
        } else {
            // A single byte. It is ASCII: every byte from 0x80 up starts an
            // identifier.
            pos += 1;
            Kind::Unknown
        };
        tokens.push(Token {
            kind,
            text: &text[start..pos],
            role: None,
        });
    }
    tokens
}
