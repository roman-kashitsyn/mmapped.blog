//! Syntax highlighting of code listings.
//!
//! The highlighter works on the inlines of a listing, not on plain text: a
//! listing may hold links, anchors and styled text. Text is split into
//! tokens; each token gets a role from its kind (keywords, strings,
//! comments) and from a few patterns per language that find definitions:
//! function names, parameters, variables and types. Malformed code is never
//! an error: an unterminated string or comment ends where the text ends.
//!
//! A comment that starts in text and goes on past an inline (`// see
//! \href{...}{here}`) takes the inline with it.
//!
//! Supported languages: Go, C, Rust and OCaml. Other listings stay as they
//! are.
//!
//! The module is self-contained: the renderer calls [`highlight`] and
//! nothing else.

use rftex_doc::document::{HighlightRole as Role, Inline};

use languages::LANGUAGES;
use lexer::{lex, Kind, Language, Token};

mod languages;
mod lexer;
// The patterns walk tokens by position, as the OCaml engine they were ported
// from does; keeping them close to it eases the comparison of the output.
#[allow(clippy::needless_range_loop)]
mod patterns;
#[cfg(test)]
mod tests;

/// Highlights the content of a code block whose classes name a supported
/// language. Content in any other language is returned unchanged.
pub fn highlight(classes: &[String], content: Vec<Inline>) -> Vec<Inline> {
    match LANGUAGES
        .iter()
        .find(|language| classes.iter().any(|class| class == language.name))
    {
        Some(language) => highlight_with(language, content),
        None => content,
    }
}

/// Gives every token its role and turns the tokens into inlines. Adjacent
/// tokens of one role share an inline; no inline crosses a line break.
fn inlines_of_tokens(language: &Language, mut tokens: Vec<Token>) -> Vec<Inline> {
    for token in &mut tokens {
        token.role = match token.kind {
            Kind::Keyword => Some(Role::Keyword),
            Kind::Comment => Some(Role::Comment),
            Kind::String => Some(Role::String),
            _ => None,
        };
    }
    (language.classify)(&mut tokens);
    for token in &mut tokens {
        if token.kind == Kind::Ident && token.role.is_none() {
            token.role = Some(Role::Identifier);
        }
    }

    let mut out = Vec::new();
    let mut pending: Option<(Option<Role>, String)> = None;
    let push = |pending: &mut Option<(Option<Role>, String)>,
                out: &mut Vec<Inline>,
                role: Option<Role>,
                text: &str| {
        if text.is_empty() {
            return;
        }
        match pending {
            Some((pending_role, pending_text)) if *pending_role == role => {
                pending_text.push_str(text)
            }
            _ => {
                if let Some(previous) = pending.replace((role, text.to_string())) {
                    out.push(make_inline(previous));
                }
            }
        }
    };
    for token in &tokens {
        let mut pieces = token.text.split('\n');
        if let Some(first) = pieces.next() {
            push(&mut pending, &mut out, token.role, first);
        }
        for piece in pieces {
            push(&mut pending, &mut out, None, "\n");
            push(&mut pending, &mut out, token.role, piece);
        }
    }
    if let Some(last) = pending {
        out.push(make_inline(last));
    }
    out
}

fn make_inline((role, text): (Option<Role>, String)) -> Inline {
    match role {
        None => Inline::Str(text),
        Some(role) => Inline::Highlighted(role, vec![Inline::Str(text)]),
    }
}

fn comment(body: Vec<Inline>) -> Inline {
    Inline::Highlighted(Role::Comment, body)
}

/// Where the highlighter is.
enum State {
    Code,
    /// Inside a line comment that started in an earlier text, with what the
    /// comment holds so far.
    LineComment(Vec<Inline>),
    BlockComment(Vec<Inline>),
}

fn highlight_with(language: &Language, content: Vec<Inline>) -> Vec<Inline> {
    let lexical = &language.lexical;
    let mut queue: std::collections::VecDeque<Inline> = content.into();
    let mut out = Vec::new();
    let mut state = State::Code;
    loop {
        state = match state {
            State::Code => match queue.pop_front() {
                None => break,
                Some(Inline::Str(mut text)) => {
                    while let Some(Inline::Str(next)) = queue.front() {
                        text.push_str(next);
                        queue.pop_front();
                    }
                    let mut tokens = lex(language, &text);
                    // A comment that is still open where the text ends goes
                    // on into the inlines that follow.
                    let open_comment = tokens.last().and_then(|last| {
                        if last.kind != Kind::Comment {
                            return None;
                        }
                        if lexical
                            .line_comments
                            .iter()
                            .any(|prefix| last.text.starts_with(prefix))
                        {
                            return Some(State::LineComment(vec![Inline::Str(
                                last.text.to_string(),
                            )]));
                        }
                        lexical
                            .block_comments
                            .iter()
                            .any(|(open, close)| {
                                last.text.starts_with(open) && !last.text.ends_with(close)
                            })
                            .then(|| State::BlockComment(vec![Inline::Str(last.text.to_string())]))
                    });
                    if open_comment.is_some() {
                        tokens.pop();
                    }
                    out.extend(inlines_of_tokens(language, tokens));
                    open_comment.unwrap_or(State::Code)
                }
                Some(inline) => {
                    out.push(inline);
                    State::Code
                }
            },
            State::LineComment(mut body) => match queue.pop_front() {
                None => {
                    out.push(comment(body));
                    break;
                }
                Some(Inline::Str(text)) => match text.find(['\n', '\r']) {
                    None => {
                        body.push(Inline::Str(text));
                        State::LineComment(body)
                    }
                    Some(index) => {
                        body.push(Inline::Str(text[..index].to_string()));
                        out.push(comment(body));
                        out.push(Inline::Str(text[index..index + 1].to_string()));
                        queue.push_front(Inline::Str(text[index + 1..].to_string()));
                        State::Code
                    }
                },
                Some(inline) => {
                    body.push(inline);
                    State::LineComment(body)
                }
            },
            State::BlockComment(mut body) => {
                let close = lexical.block_comments[0].1;
                match queue.pop_front() {
                    None => {
                        out.push(comment(body));
                        break;
                    }
                    Some(Inline::Str(text)) => {
                        if let Some(index) = text.find(close) {
                            let end = index + close.len();
                            body.push(Inline::Str(text[..end].to_string()));
                            out.push(comment(body));
                            queue.push_front(Inline::Str(text[end..].to_string()));
                            State::Code
                        } else if let Some(index) = text.find(['\n', '\r']) {
                            // Each line of the comment is a span of its own.
                            // The rest of the text joins the next one whole.
                            body.push(Inline::Str(text[..index].to_string()));
                            out.push(comment(body));
                            out.push(Inline::Str(text[index..index + 1].to_string()));
                            State::BlockComment(vec![Inline::Str(text[index + 1..].to_string())])
                        } else {
                            body.push(Inline::Str(text));
                            State::BlockComment(body)
                        }
                    }
                    Some(inline) => {
                        body.push(inline);
                        State::BlockComment(body)
                    }
                }
            }
        };
    }
    out
}
