//! The rftex grammar as resilient recursive-descent functions.
//!
//! Every loop consumes at least one token per iteration, and every construct
//! with a closer decides what to do with a token it did not expect by asking
//! [`flow`]: a closer that belongs to an enclosing construct ends the current
//! one (which then reports that its own closer is missing), and a closer that
//! belongs to nothing is skipped as a stray. This is what keeps a forgotten
//! `}` or `\end` from swallowing the rest of the document.

use crate::error::ErrorKind;
use crate::kind::SyntaxKind::{self, *};
use crate::lexer::{Charset, Mode};
use crate::parser::{Delim, Parser};
use crate::registry::{ArgSpec, Flow as ArgFlow, MathArg, MathSig, OptSpec, Sym};
use crate::tree::TextRange;

/// What a content loop does with the current token.
enum Flow {
    /// The token is content for the current construct.
    Go,
    /// The token ends the current construct: its own closer, the closer of an
    /// enclosing construct, or the end of input.
    Stop,
    /// The token closes nothing that is open.
    Stray(ErrorKind),
}

/// Which closers are local to the content loop that is running. Nested
/// groups and arguments start over with [`Ctx::Plain`].
#[derive(Clone, Copy, PartialEq, Eq)]
enum Ctx {
    Plain,
    /// Inside a quotation: two apostrophes close it.
    Quote,
    /// Inside a bracketed argument: `]` closes it.
    Bracket,
    /// Inside a table cell: `&` and `\\` separate cells and rows.
    Cell,
}

/// Whether the innermost open construct ends at a paragraph break.
fn in_inline(p: &Parser) -> bool {
    p.delims
        .last()
        .is_some_and(|delim| delim.ends_at_par_break())
}

fn flow(p: &mut Parser, in_math: bool) -> Flow {
    let top = p.delims.last().copied();
    // A closer for the innermost construct or for an enclosing one stops the
    // loop; a closer for nothing is a stray.
    let closes = |p: &Parser, matches: &dyn Fn(Delim) -> bool, stray: ErrorKind| {
        if p.delims.iter().any(|&delim| matches(delim)) {
            Flow::Stop
        } else {
            Flow::Stray(stray)
        }
    };
    match p.nth(0) {
        Eof => Flow::Stop,
        RBrace => closes(
            p,
            &|d| matches!(d, Delim::Brace { .. }),
            ErrorKind::UnmatchedCloseBrace,
        ),
        ParBreak if in_inline(p) => Flow::Stop,
        // Math has no paragraph token: a break is two adjacent newlines.
        Newline if in_math && in_inline(p) && p.next_raw() == Newline => Flow::Stop,
        Dollar if in_math => closes(
            p,
            &|d| d == Delim::InlineMath,
            ErrorKind::UnmatchedMathDelimiter,
        ),
        DisplayClose => closes(
            p,
            &|d| d == Delim::DisplayMath,
            ErrorKind::UnmatchedMathDelimiter,
        ),
        DisplayOpen if in_math => Flow::Stray(ErrorKind::UnmatchedMathDelimiter),
        ControlWord => match p.command_name(0) {
            "end" => match end_name(p) {
                Some(name) => closes(p, &|d| d == Delim::Env(name), ErrorKind::UnmatchedEnd),
                None => Flow::Stray(ErrorKind::UnmatchedEnd),
            },
            // A section heading cannot sit inside braces or math, so it ends
            // whatever is still open since the enclosing environment began.
            "section" | "section*" | "subsection"
                if top.is_some_and(|delim| !matches!(delim, Delim::Env(_))) =>
            {
                Flow::Stop
            }
            _ => Flow::Go,
        },
        _ => Flow::Go,
    }
}

/// The name in `\end{name}` when the parser is at a well-formed one.
fn end_name<'a>(p: &mut Parser<'a>) -> Option<&'a str> {
    p.in_mode(Mode::Atom(Charset::Symbol), |p| {
        (p.nth(1) == LBrace && p.nth(2) == Atom && p.nth(3) == RBrace).then(|| p.nth_text(2))
    })
}

fn at_end_of(p: &mut Parser, name: &str) -> bool {
    p.at(ControlWord) && p.command_name(0) == "end" && end_name(p) == Some(name)
}

/// Skips a token that closes nothing. A stray `\end{name}` goes as a whole.
fn stray(p: &mut Parser, kind: ErrorKind) {
    if kind != ErrorKind::UnmatchedEnd {
        p.advance_with_error(kind);
        return;
    }
    let mark = p.open();
    p.error_here(kind);
    p.advance();
    if p.peek_byte() == Some(b'{') {
        p.in_mode(Mode::Atom(Charset::Symbol), |p| {
            p.advance();
            let _ = p.eat(Atom) && p.eat(RBrace);
        });
    }
    p.close(mark, ErrorTree);
}

pub(crate) fn document(p: &mut Parser) {
    let mark = p.open();
    text_content(p, Ctx::Plain);
    p.close(mark, Document);
}

// ---------------------------------------------------------------- text

fn text_content(p: &mut Parser, ctx: Ctx) {
    p.in_mode(Mode::Text, |p| loop {
        let local_stop = match ctx {
            Ctx::Plain => false,
            Ctx::Quote => p.at(CloseQuote),
            Ctx::Bracket => p.at(RBracket),
            Ctx::Cell => p.at(Amp) || p.at(DoubleBackslash),
        };
        if local_stop {
            break;
        }
        match flow(p, false) {
            Flow::Stop => break,
            Flow::Stray(kind) => stray(p, kind),
            Flow::Go => text_item(p, ctx),
        }
    })
}

fn text_item(p: &mut Parser, ctx: Ctx) {
    match p.nth(0) {
        Text | ParBreak | Escape | DoubleBackslash | LBracket | RBracket | Backtick
        | CloseQuote => p.advance(),
        // Quotations do not exist in table cells: backticks are plain text.
        OpenQuote if ctx == Ctx::Cell => p.advance(),
        OpenQuote => quotation(p),
        ControlWord => command_or_environment(p),
        LBrace => group(p),
        Dollar => inline_math(p),
        DisplayOpen => display_math(p),
        Amp => p.advance_with_error(ErrorKind::UnexpectedAmp),
        ErrorToken => p.advance_with_error(ErrorKind::InvalidEscape),
        _ => p.advance_with_error(ErrorKind::UnexpectedToken),
    }
}

/// The body of a `code` environment: braces and brackets are literal, while
/// commands, math and comments stay live.
fn code_content(p: &mut Parser) {
    p.in_mode(Mode::Code, |p| loop {
        match flow(p, false) {
            Flow::Stop => break,
            Flow::Stray(kind) => stray(p, kind),
            Flow::Go => match p.nth(0) {
                Text | Escape | DoubleBackslash => p.advance(),
                ControlWord => command_or_environment(p),
                Dollar => inline_math(p),
                DisplayOpen => display_math(p),
                ErrorToken => p.advance_with_error(ErrorKind::InvalidEscape),
                _ => p.advance_with_error(ErrorKind::UnexpectedToken),
            },
        }
    })
}

fn group(p: &mut Parser) {
    let mark = p.open();
    let inline = in_inline(p);
    braced_content(p, inline);
    p.close(mark, Group);
}

/// `{ content }`, starting at the opening brace.
fn braced_content(p: &mut Parser, inline: bool) {
    p.in_mode(Mode::Text, |p| {
        let opener = p.current_range();
        p.advance();
        p.delims.push(Delim::Brace { inline });
        text_content(p, Ctx::Plain);
        p.delims.pop();
        if !p.eat(RBrace) {
            p.error(ErrorKind::UnclosedBrace, opener);
        }
    })
}

/// A quotation closes at the first pair of apostrophes on its own level.
/// One that never closes is kept as a node of a different kind; it is valid
/// input that reads as literal backticks followed by ordinary content.
fn quotation(p: &mut Parser) {
    let mark = p.open();
    p.advance();
    text_content(p, Ctx::Quote);
    let kind = if p.eat(CloseQuote) {
        Quotation
    } else {
        UnclosedQuotation
    };
    p.close(mark, kind);
}

// ------------------------------------------------------------ commands

fn command_or_environment(p: &mut Parser) {
    if p.command_name(0) == "begin" {
        environment(p);
    } else {
        command(p);
    }
}

/// `\name[options]{arg}...`. The registry says how many arguments follow and
/// how each one is lexed. Options and arguments must touch what precedes
/// them. The control word token covers one following space, so `\item [x]`
/// has options and `\item  [x]` does not.
fn command(p: &mut Parser) {
    let mark = p.open();
    let sym = Sym::from_name(p.command_name(0));
    let spec = sym.spec();
    p.advance();

    if p.peek_byte() == Some(b'[') {
        match spec.opt {
            OptSpec::Symbols => options(p),
            OptSpec::Seq => bracket_arg(p),
        }
    }
    for &arg_spec in spec.args {
        if p.peek_byte() != Some(b'{') {
            p.error_missing(ErrorKind::MissingArgument);
            break;
        }
        let value = arg(p, arg_spec);
        if sym == Sym::Multicolumn && arg_spec == ArgSpec::AlignSpec {
            let (text, range) = value;
            let columns = text
                .bytes()
                .filter(|c| matches!(c, b'l' | b'r' | b'c'))
                .count();
            if columns != 1 {
                p.error(ErrorKind::InvalidMulticolumnAlignment, range);
            }
        }
    }
    p.close(mark, Command);
}

/// One braced argument, starting at its opening brace. Returns the text and
/// range of the value of a non-content argument.
fn arg<'a>(p: &mut Parser<'a>, spec: ArgSpec) -> (&'a str, TextRange) {
    let mark = p.open();
    let value = match spec.charset() {
        None => {
            braced_content(p, spec == ArgSpec::Seq(ArgFlow::Inline));
            ("", TextRange::empty(0))
        }
        Some(charset) => p.in_mode(Mode::Atom(charset), |p| {
            let opener = p.current_range();
            p.advance();
            let value = (p.nth_text(0), p.current_range());
            if p.at(Atom) {
                if spec == ArgSpec::Number && value.0.parse::<i64>().is_err() {
                    p.error_here(ErrorKind::InvalidNumber);
                }
                p.advance();
                junk(p, true);
            } else {
                p.error_here(ErrorKind::ExpectedArgumentValue);
                junk(p, false);
            }
            if !p.eat(RBrace) {
                p.error(ErrorKind::UnclosedBrace, opener);
            }
            value
        }),
    };
    p.close(mark, Arg);
    value
}

/// Skips whatever follows the value of a single-value argument, up to the
/// closing brace. `report` is false when the value itself was already
/// reported as malformed.
fn junk(p: &mut Parser, report: bool) {
    if !(p.at(Atom) || p.at(ErrorToken)) {
        return;
    }
    let mark = p.open();
    let start = p.current_range().start;
    while p.at(Atom) || p.at(ErrorToken) {
        p.advance();
    }
    if report {
        let end = p.current_range().start;
        p.error(ErrorKind::UnexpectedInArgument, TextRange::new(start, end));
    }
    p.close(mark, ErrorTree);
}

/// `[name, name, ...]`, starting at the opening bracket.
fn options(p: &mut Parser) {
    p.in_mode(Mode::Options, |p| {
        let mark = p.open();
        let opener = p.current_range();
        p.advance();
        p.eat(Whitespace);
        let mut well_formed = true;
        if p.eat(Atom) {
            p.eat(Whitespace);
            while p.eat(Comma) {
                p.eat(Whitespace);
                if !p.eat(Atom) {
                    well_formed = false;
                    break;
                }
                p.eat(Whitespace);
            }
        }
        // Whatever else sits before the closing bracket on this level is junk.
        while matches!(p.nth(0), Atom | Comma | Whitespace | ErrorToken) {
            well_formed = false;
            p.advance();
        }
        if !well_formed {
            let end = p.current_range().start;
            p.error(ErrorKind::MalformedOptions, TextRange::new(opener.end, end));
        }
        if !p.eat(RBracket) {
            p.error(ErrorKind::UnclosedBracket, opener);
        }
        p.close(mark, Options);
    })
}

/// `[ content ]`, starting at the opening bracket.
fn bracket_arg(p: &mut Parser) {
    p.in_mode(Mode::Text, |p| {
        let mark = p.open();
        let opener = p.current_range();
        p.advance();
        p.delims.push(Delim::Bracket);
        text_content(p, Ctx::Bracket);
        p.delims.pop();
        if !p.eat(RBracket) {
            p.error(ErrorKind::UnclosedBracket, opener);
        }
        p.close(mark, BracketArg);
    })
}

// -------------------------------------------------------- environments

fn environment(p: &mut Parser) {
    let mark = p.open();
    let begin_range = p.current_range();
    let Some(name) = begin(p) else {
        // Without a name there is no telling where the body ends.
        p.close(mark, Environment);
        return;
    };
    if p.peek_byte() == Some(b'[') {
        options(p);
    }

    p.delims.push(Delim::Env(name));
    match name {
        "verbatim" => {
            p.raw_until("\\end{verbatim}");
        }
        "tabular" | "tabular*" => table_body(p),
        "code" => code_content(p),
        "align*" => align_body(p),
        _ => text_content(p, Ctx::Plain),
    }
    p.delims.pop();

    if at_end_of(p, name) {
        let end = p.open();
        p.advance();
        p.in_mode(Mode::Atom(Charset::Symbol), |p| {
            p.advance();
            p.advance();
            p.advance();
        });
        p.close(end, End);
    } else {
        p.error(ErrorKind::UnclosedEnvironment, begin_range);
    }
    p.close(mark, Environment);
}

/// `\begin{name}`. Returns the name if there is one.
fn begin<'a>(p: &mut Parser<'a>) -> Option<&'a str> {
    let mark = p.open();
    p.advance();
    let name = if p.peek_byte() == Some(b'{') {
        p.in_mode(Mode::Atom(Charset::Symbol), |p| {
            let opener = p.current_range();
            p.advance();
            let name = p.at(Atom).then(|| p.nth_text(0));
            match name {
                Some(_) => p.advance(),
                None => p.error_here(ErrorKind::ExpectedEnvironmentName),
            }
            junk(p, name.is_some());
            if !p.eat(RBrace) {
                p.error(ErrorKind::UnclosedBrace, opener);
            }
            name
        })
    } else {
        p.error_missing(ErrorKind::ExpectedEnvironmentName);
        None
    };
    p.close(mark, Begin);
    name
}

/// `{colspec}` followed by rows of cells. Rows end at `\\`, cells at `&`.
fn table_body(p: &mut Parser) {
    if p.peek_byte() == Some(b'{') {
        arg(p, ArgSpec::AlignSpec);
    } else {
        p.error_missing(ErrorKind::MissingArgument);
    }
    rows(p, Mode::Text, |p| text_content(p, Ctx::Cell));
}

/// Rows of math cells. Rows end at `\\`, cells at `&`.
fn align_body(p: &mut Parser) {
    rows(p, Mode::Math, |p| math_list(p, true));
}

/// The row and cell delimiters are shared by tables and aligned math.
fn rows(p: &mut Parser, mode: Mode, cell_content: impl Fn(&mut Parser)) {
    p.in_mode(mode, |p| loop {
        match flow(p, mode == Mode::Math) {
            Flow::Stop => break,
            Flow::Stray(kind) => stray(p, kind),
            Flow::Go => {
                let row = p.open();
                loop {
                    let cell = p.open();
                    cell_content(p);
                    p.close(cell, Cell);
                    if !p.eat(Amp) {
                        break;
                    }
                }
                p.eat(DoubleBackslash);
                p.close(row, Row);
            }
        }
    })
}

// ---------------------------------------------------------------- math

fn inline_math(p: &mut Parser) {
    math(p, Delim::InlineMath, Dollar, InlineMath);
}

fn display_math(p: &mut Parser) {
    math(p, Delim::DisplayMath, DisplayClose, DisplayMath);
}

fn math(p: &mut Parser, delim: Delim<'static>, closer: SyntaxKind, kind: SyntaxKind) {
    let mark = p.open();
    let opener = p.current_range();
    p.advance();
    p.delims.push(delim);
    p.in_mode(Mode::Math, |p| {
        math_list(p, false);
        if !p.eat(closer) {
            p.error(ErrorKind::UnclosedMath, opener);
        }
    });
    p.delims.pop();
    p.close(mark, kind);
}

/// A sequence of math terms. In a cell of `align*`, `&` and `\\` on this
/// level end the sequence; elsewhere they are operators.
fn math_list(p: &mut Parser, align_cell: bool) {
    // A minus sign binds to the digits after it at the start of a list and
    // after an operator: `a = -1` holds the number -1, `a - 1` does not.
    let mut after_operator = true;
    loop {
        if align_cell && (p.at(Amp) || p.at(DoubleBackslash)) {
            break;
        }
        match flow(p, true) {
            Flow::Stop => break,
            Flow::Stray(kind) => stray(p, kind),
            Flow::Go => after_operator = math_term(p, after_operator),
        }
    }
}

/// An atom with optional scripts. Returns whether it reads as an operator.
/// Script markers must touch what they attach to.
fn math_term(p: &mut Parser, allow_negative: bool) -> bool {
    let start = p.checkpoint();
    let is_operator = math_atom(p, allow_negative);
    let second = match p.peek_byte() {
        Some(b'_') => b'^',
        Some(b'^') => b'_',
        _ => return is_operator,
    };
    let mark = p.open_at(start);
    script(p);
    if p.peek_byte() == Some(second) {
        script(p);
    }
    p.close(mark, MathTerm);
    false
}

/// `_` or `^` and the atom it attaches.
fn script(p: &mut Parser) {
    p.advance();
    match flow(p, true) {
        Flow::Go => {
            math_atom(p, true);
        }
        _ => p.error_missing(ErrorKind::ExpectedMathAtom),
    }
}

/// One math atom. Returns whether it reads as an operator.
fn math_atom(p: &mut Parser, allow_negative: bool) -> bool {
    match p.nth(0) {
        LBrace => {
            math_group(p);
            false
        }
        ControlWord => math_command(p),
        Operator if allow_negative && p.nth_text(0) == "-" && p.next_raw() == Number => {
            let mark = p.open();
            p.advance();
            p.advance();
            p.close(mark, MathNegNumber);
            false
        }
        Operator | Newline | Amp | Escape | DoubleBackslash => {
            p.advance();
            true
        }
        Number | Letter => {
            p.advance();
            false
        }
        _ => {
            p.advance_with_error(ErrorKind::UnexpectedInMath);
            false
        }
    }
}

fn math_group(p: &mut Parser) {
    let mark = p.open();
    let opener = p.current_range();
    let inline = in_inline(p);
    p.advance();
    p.delims.push(Delim::Brace { inline });
    math_list(p, false);
    p.delims.pop();
    if !p.eat(RBrace) {
        p.error(ErrorKind::UnclosedBrace, opener);
    }
    p.close(mark, MathGroup);
}

/// `\name` in math. Returns whether it reads as an operator, which only
/// `\left` does.
fn math_command(p: &mut Parser) -> bool {
    let mark = p.open();
    let sym = Sym::from_name(p.command_name(0));
    p.advance();
    match sym.spec().math {
        MathSig::Plain => {}
        MathSig::Delimiter => match p.nth(0) {
            Operator | Newline | Amp => p.advance(),
            Escape if matches!(p.nth_text(0), "\\{" | "\\}") => p.advance(),
            _ => p.error_missing(ErrorKind::ExpectedDelimiter),
        },
        MathSig::Args(args) => {
            for arg in args {
                if !p.at(LBrace) {
                    p.error_missing(ErrorKind::MissingArgument);
                    break;
                }
                match arg {
                    MathArg::Expr => math_group(p),
                    MathArg::Symbol => math_symbol_arg(p),
                }
            }
        }
    }
    p.close(mark, MathCommand);
    sym == Sym::Left
}

/// `{symbol}` after a math command, starting at the opening brace.
fn math_symbol_arg(p: &mut Parser) {
    p.in_mode(Mode::Atom(Charset::Symbol), |p| {
        let mark = p.open();
        let opener = p.current_range();
        p.advance();
        let has_value = p.eat(Atom);
        if !has_value {
            p.error_here(ErrorKind::ExpectedArgumentValue);
        }
        junk(p, has_value);
        if !p.eat(RBrace) {
            p.error(ErrorKind::UnclosedBrace, opener);
        }
        p.close(mark, MathArg);
    })
}
