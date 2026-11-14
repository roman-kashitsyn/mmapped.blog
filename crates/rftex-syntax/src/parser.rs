//! Parser machinery: lookahead over the modal lexer, tree events, and the
//! stack of open delimiters that drives error recovery.
//!
//! The grammar itself lives in [`crate::grammar`]. The design follows
//! <https://matklad.github.io/2023/05/21/resilient-ll-parsing-tutorial.html>:
//! grammar functions emit a flat list of events that is turned into a tree at
//! the end. Because tokens depend on the lexer mode, there is no token vector;
//! the parser lexes lazily into a small buffer that is dropped whenever the
//! mode changes.

use std::collections::VecDeque;

use crate::error::{ErrorKind, SyntaxError};
use crate::kind::SyntaxKind::{self, *};
use crate::lexer::{self, Mode, Token};
use crate::tree::{TextRange, Tree, TreeBuilder};

enum Event {
    Open { kind: SyntaxKind },
    Close,
    Token { kind: SyntaxKind, len: u32 },
}

/// A node that has been opened and must be closed.
pub(crate) struct MarkOpened {
    index: usize,
    pos: usize,
}

/// A position in the event list at which a node can still be opened, to wrap
/// everything emitted since.
#[derive(Clone, Copy)]
pub(crate) struct Checkpoint {
    index: usize,
    pos: usize,
}

/// A construct that is open at the current position and waits for its closer.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Delim<'a> {
    /// `{`. `inline` braces also end at a paragraph break.
    Brace { inline: bool },
    /// `[` of a bracketed content argument. Ends at a paragraph break.
    Bracket,
    /// `\begin{name}`.
    Env(&'a str),
    /// `$`. Ends at a paragraph break.
    InlineMath,
    /// `\[`.
    DisplayMath,
}

impl Delim<'_> {
    /// Whether a paragraph break implicitly closes the construct.
    pub(crate) fn ends_at_par_break(self) -> bool {
        matches!(
            self,
            Delim::Brace { inline: true } | Delim::Bracket | Delim::InlineMath
        )
    }
}

/// The number of lookups allowed without consuming input or finishing a node
/// that began before the current position. Finishing such a node is progress
/// during recovery, when several nested constructs may share a missing closer.
/// Running out means a grammar function is looping without progress.
const FUEL: u32 = 256;

pub(crate) struct Parser<'a> {
    src: &'a str,
    /// Offset of the first token that has not been consumed.
    pos: usize,
    mode: Mode,
    /// Tokens lexed at `pos` in `mode` and not consumed yet.
    lookahead: VecDeque<Token>,
    /// Offset just past the last token in `lookahead`.
    lexed: usize,
    fuel: u32,
    events: Vec<Event>,
    errors: Vec<SyntaxError>,
    /// Open constructs, innermost last.
    pub(crate) delims: Vec<Delim<'a>>,
}

impl<'a> Parser<'a> {
    pub(crate) fn new(src: &'a str) -> Parser<'a> {
        assert!(
            src.len() <= u32::MAX as usize,
            "sources over 4 GiB are not supported"
        );
        Parser {
            src,
            pos: 0,
            mode: Mode::Text,
            lookahead: VecDeque::new(),
            lexed: 0,
            fuel: FUEL,
            events: Vec::new(),
            errors: Vec::new(),
            delims: Vec::new(),
        }
    }

    // ------------------------------------------------------------- modes

    fn set_mode(&mut self, mode: Mode) {
        if self.mode != mode {
            self.mode = mode;
            self.lookahead.clear();
            self.lexed = self.pos;
        }
    }

    /// Runs `f` with the lexer in `mode`, then restores the previous mode.
    pub(crate) fn in_mode<R>(&mut self, mode: Mode, f: impl FnOnce(&mut Self) -> R) -> R {
        let outer = self.mode;
        self.set_mode(mode);
        let result = f(self);
        self.set_mode(outer);
        result
    }

    // --------------------------------------------------------- lookahead

    /// Lexes until `count` tokens are buffered or the input ends.
    fn fill(&mut self, count: usize) {
        while self.lookahead.len() < count {
            if self.lookahead.back().is_some_and(|token| token.kind == Eof) {
                break;
            }
            let token = lexer::next_token(self.src, self.lexed, self.mode);
            self.lexed += token.len as usize;
            self.lookahead.push_back(token);
        }
    }

    /// Moves trivia at the current position into the tree. It lands in
    /// whichever node is open when the parser next looks ahead.
    fn skip_trivia(&mut self) {
        loop {
            self.fill(1);
            match self.lookahead.front() {
                Some(token) if token.kind.is_trivia() => self.bump(),
                _ => break,
            }
        }
    }

    /// Consumes the first buffered token.
    fn bump(&mut self) {
        let token = self
            .lookahead
            .pop_front()
            .expect("bump with an empty buffer");
        debug_assert!(token.kind != Eof);
        self.events.push(Event::Token {
            kind: token.kind,
            len: token.len,
        });
        self.pos += token.len as usize;
        self.fuel = FUEL;
    }

    /// The `n`-th token ahead, not counting trivia, and its range.
    fn nth_token(&mut self, n: usize) -> (SyntaxKind, TextRange) {
        self.skip_trivia();
        assert!(self.fuel > 0, "parser is stuck at offset {}", self.pos);
        self.fuel -= 1;

        let mut offset = self.pos;
        let mut seen = 0;
        let mut index = 0;
        loop {
            self.fill(index + 1);
            let Some(&token) = self.lookahead.get(index) else {
                // Only happens past a buffered Eof.
                return (Eof, TextRange::empty(self.src.len() as u32));
            };
            let range = TextRange::new(offset as u32, offset as u32 + token.len);
            if token.kind == Eof {
                return (Eof, range);
            }
            if !token.kind.is_trivia() {
                if seen == n {
                    return (token.kind, range);
                }
                seen += 1;
            }
            offset += token.len as usize;
            index += 1;
        }
    }

    /// The kind of the `n`-th token ahead, not counting trivia. Past the end
    /// of input this is [`Eof`].
    pub(crate) fn nth(&mut self, n: usize) -> SyntaxKind {
        self.nth_token(n).0
    }

    /// The text of the `n`-th token ahead, not counting trivia.
    pub(crate) fn nth_text(&mut self, n: usize) -> &'a str {
        let src = self.src;
        self.nth_token(n).1.slice(src)
    }

    /// The range of the current token; empty at the end of input.
    pub(crate) fn current_range(&mut self) -> TextRange {
        self.nth_token(0).1
    }

    pub(crate) fn at(&mut self, kind: SyntaxKind) -> bool {
        self.nth(0) == kind
    }

    /// The kind of the token right after the current one, trivia included.
    /// This answers whether two tokens touch.
    pub(crate) fn next_raw(&mut self) -> SyntaxKind {
        self.skip_trivia();
        self.fill(2);
        self.lookahead.get(1).map_or(Eof, |token| token.kind)
    }

    /// The byte right after the last consumed token. Unlike [`Parser::nth`],
    /// this neither depends on the mode nor steps over trivia.
    pub(crate) fn peek_byte(&self) -> Option<u8> {
        self.src.as_bytes().get(self.pos).copied()
    }

    /// The name of a control word token ahead: no backslash, no swallowed
    /// space.
    pub(crate) fn command_name(&mut self, n: usize) -> &'a str {
        let text = self.nth_text(n);
        text.strip_prefix('\\')
            .unwrap_or(text)
            .trim_end_matches(' ')
    }

    // ------------------------------------------------------------ events

    pub(crate) fn open(&mut self) -> MarkOpened {
        let mark = MarkOpened {
            index: self.events.len(),
            pos: self.pos,
        };
        self.events.push(Event::Open { kind: ErrorTree });
        mark
    }

    /// Remembers the current point so that a node can later be opened here.
    /// Trivia at the current position stays outside such a node.
    pub(crate) fn checkpoint(&mut self) -> Checkpoint {
        self.skip_trivia();
        Checkpoint {
            index: self.events.len(),
            pos: self.pos,
        }
    }

    /// Opens a node at `checkpoint`, around everything emitted since.
    pub(crate) fn open_at(&mut self, checkpoint: Checkpoint) -> MarkOpened {
        self.events
            .insert(checkpoint.index, Event::Open { kind: ErrorTree });
        MarkOpened {
            index: checkpoint.index,
            pos: checkpoint.pos,
        }
    }

    pub(crate) fn close(&mut self, mark: MarkOpened, kind: SyntaxKind) {
        self.events[mark.index] = Event::Open { kind };
        self.events.push(Event::Close);
        // Empty nodes cannot refill the budget: a broken loop could keep
        // opening and closing them without consuming anything.
        if mark.pos < self.pos {
            self.fuel = FUEL;
        }
    }

    /// Consumes the current token.
    pub(crate) fn advance(&mut self) {
        self.skip_trivia();
        assert!(
            self.lookahead
                .front()
                .is_some_and(|token| token.kind != Eof),
            "advance at the end of input"
        );
        self.bump();
    }

    pub(crate) fn eat(&mut self, kind: SyntaxKind) -> bool {
        if self.at(kind) {
            self.advance();
            true
        } else {
            false
        }
    }

    /// Consumes the rest of the input up to `terminator` as one raw token.
    /// Returns whether the terminator was found.
    pub(crate) fn raw_until(&mut self, terminator: &str) -> bool {
        self.lookahead.clear();
        let (token, found) = lexer::raw_until(self.src, self.pos, terminator);
        if token.len > 0 {
            self.events.push(Event::Token {
                kind: token.kind,
                len: token.len,
            });
            self.pos += token.len as usize;
            self.fuel = FUEL;
        }
        self.lexed = self.pos;
        found
    }

    // ------------------------------------------------------------ errors

    pub(crate) fn error(&mut self, kind: ErrorKind, range: TextRange) {
        self.errors.push(SyntaxError { range, kind });
    }

    /// Reports an error at the current token.
    pub(crate) fn error_here(&mut self, kind: ErrorKind) {
        let range = self.current_range();
        self.error(kind, range);
    }

    /// Reports that something is missing right after the last consumed token.
    pub(crate) fn error_missing(&mut self, kind: ErrorKind) {
        self.error(kind, TextRange::empty(self.pos as u32));
    }

    /// Reports an error at the current token and skips it.
    pub(crate) fn advance_with_error(&mut self, kind: ErrorKind) {
        let mark = self.open();
        self.error_here(kind);
        self.advance();
        self.close(mark, ErrorTree);
    }

    // ------------------------------------------------------------ result

    pub(crate) fn finish(mut self) -> (Tree, Vec<SyntaxError>) {
        assert_eq!(
            self.pos,
            self.src.len(),
            "the parser stopped before the end of input"
        );
        let mut builder = TreeBuilder::new();
        for event in self.events {
            match event {
                Event::Open { kind } => builder.open(kind),
                Event::Close => builder.close(),
                Event::Token { kind, len } => builder.token(kind, len),
            }
        }
        self.errors
            .sort_by_key(|error| (error.range.start, error.range.end));
        (builder.finish(), self.errors)
    }
}

#[cfg(test)]
mod tests;
