//! Kinds of tokens and nodes in the syntax tree.

/// The kind of an element of the syntax tree: a token (a leaf that covers
/// source text) or a node (an inner element made of tokens and nodes).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
#[repr(u8)]
pub enum SyntaxKind {
    // ------------------------------------------------------------ tokens
    /// End of input. Never stored in the tree.
    Eof,
    /// Text the lexer could not classify in the current mode.
    ErrorToken,
    /// `%` up to and including the end of the line.
    Comment,
    /// A run of literal text.
    Text,
    /// Two or more consecutive newlines in text.
    ParBreak,
    /// `\name`. In text and code the token also covers one following space.
    ControlWord,
    /// A backslash followed by one escaped character.
    Escape,
    /// `\\`: a literal backslash, or a row separator in tables and `align*`.
    DoubleBackslash,
    /// `\[`
    DisplayOpen,
    /// `\]`
    DisplayClose,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    /// `&`: a cell separator in tables and `align*`, an operator in math.
    Amp,
    Dollar,
    /// Two backticks.
    OpenQuote,
    /// Two apostrophes.
    CloseQuote,
    /// A single backtick.
    Backtick,
    /// A run of spaces in math.
    Space,
    /// A single newline in math.
    Newline,
    /// A run of digits in math.
    Number,
    /// A single letter in math.
    Letter,
    /// A single operator character in math.
    Operator,
    Underscore,
    Caret,
    /// The value of a symbol, number, URL or column-spec argument, an
    /// environment name, or one option.
    Atom,
    Comma,
    /// Whitespace inside an option list.
    Whitespace,
    /// The body of a `verbatim` environment.
    RawText,

    // ------------------------------------------------------------- nodes
    Document,
    /// `\name[options]{arg}...`
    Command,
    /// `[a, b]`
    Options,
    /// `[...]` holding content, as in `\bibref[p. 5]{key}`.
    BracketArg,
    /// `{...}` consumed by a command.
    Arg,
    /// `{...}` in the text flow.
    Group,
    /// Balanced double-backtick ... double-apostrophe quotation.
    Quotation,
    /// An opening quote that never closes. Not an error: the quote reads as
    /// literal text.
    UnclosedQuotation,
    /// `\begin{name}[options] ... \end{name}`
    Environment,
    /// `\begin{name}`
    Begin,
    /// `\end{name}`
    End,
    /// A row of a table or of `align*`.
    Row,
    /// A cell of a table or of `align*`.
    Cell,
    /// `$...$`
    InlineMath,
    /// `\[...\]`
    DisplayMath,
    /// `{...}` in math.
    MathGroup,
    /// A nucleus with a subscript, a superscript, or both.
    MathTerm,
    /// `\name` in math, with its delimiter or arguments.
    MathCommand,
    /// `{symbol}` consumed by a math command.
    MathArg,
    /// `-` glued to the digits that follow it.
    MathNegNumber,
    /// Input the parser skipped while recovering.
    ErrorTree,
}

impl SyntaxKind {
    /// Whether elements of this kind are leaves covering source text.
    pub fn is_token(self) -> bool {
        (self as u8) < (SyntaxKind::Document as u8)
    }

    /// Whether the parser steps over tokens of this kind when it looks ahead.
    pub fn is_trivia(self) -> bool {
        matches!(self, SyntaxKind::Comment | SyntaxKind::Space)
    }
}
