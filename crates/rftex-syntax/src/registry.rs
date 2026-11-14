//! The registry of known commands, environments and math commands.
//!
//! Every name lives in one table. The parser reads it to learn how many
//! arguments a command takes and how each is lexed; later passes use the same
//! table for validation, completion and hover text. Adding a command is one
//! entry in [`symbols!`](self) below.
//!
//! Commands, environments and math commands share one namespace, so `\code`
//! and `\begin{code}` resolve to the same [`Sym`].

use crate::lexer::Charset;

/// Whether an argument may contain paragraph breaks.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Flow {
    /// A paragraph break ends the argument: the closing brace is missing.
    Inline,
    /// The argument may hold several paragraphs.
    Block,
}

/// The kind of one braced argument.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ArgSpec {
    /// Arbitrary content.
    Seq(Flow),
    /// A label, name or date.
    Symbol,
    /// A BibTeX entry key.
    BibKey,
    /// An integer.
    Number,
    /// A URL.
    Url,
    /// A column specification such as `l r c`.
    AlignSpec,
}

impl ArgSpec {
    /// The characters of the argument's value, or `None` for content.
    pub fn charset(self) -> Option<Charset> {
        match self {
            ArgSpec::Seq(_) => None,
            ArgSpec::Symbol => Some(Charset::Symbol),
            ArgSpec::BibKey => Some(Charset::BibKey),
            ArgSpec::Number => Some(Charset::Number),
            ArgSpec::Url => Some(Charset::Url),
            ArgSpec::AlignSpec => Some(Charset::AlignSpec),
        }
    }
}

/// What the optional bracketed argument of a command holds.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum OptSpec {
    /// `[a, b]`: a list of symbols. The default.
    Symbols,
    /// `[...]`: inline content, as in `\bibref[p. 5]{key}`.
    Seq,
}

/// One argument of a math command.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MathArg {
    /// `{...}` holding a math expression.
    Expr,
    /// `{...}` holding a symbol.
    Symbol,
}

/// How a name behaves in math.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MathSig {
    /// Takes nothing.
    Plain,
    /// Takes one delimiter character, as `\left(` does.
    Delimiter,
    /// Takes braced arguments.
    Args(&'static [MathArg]),
}

/// Everything known about one name.
#[derive(Clone, Copy, Debug)]
pub struct Spec {
    /// The name as written, without the backslash.
    pub name: &'static str,
    doc: &'static str,
    /// Braced arguments the name takes as a command in text.
    pub args: &'static [ArgSpec],
    /// The shape of the optional bracketed argument.
    pub opt: OptSpec,
    /// Behavior in math.
    pub math: MathSig,
    /// The text a symbol command stands for, such as `…` for `\ldots`.
    pub replacement: Option<&'static str>,
}

impl Spec {
    /// A one-line description for hover and completion. May be empty.
    pub fn doc(&self) -> &'static str {
        self.doc.trim()
    }
}

const BASE: Spec = Spec {
    name: "",
    doc: "",
    args: &[],
    opt: OptSpec::Symbols,
    math: MathSig::Plain,
    replacement: None,
};

/// A command with braced arguments.
const fn cmd(args: &'static [ArgSpec]) -> Spec {
    Spec { args, ..BASE }
}

/// A command or environment without arguments.
const PLAIN: Spec = BASE;

/// A math command with braced arguments.
const fn math(args: &'static [MathArg]) -> Spec {
    Spec {
        math: MathSig::Args(args),
        ..BASE
    }
}

/// A math command followed by a delimiter character.
const DELIMITER: Spec = Spec {
    math: MathSig::Delimiter,
    ..BASE
};

/// A symbol command that stands for fixed text.
const fn symbol(replacement: &'static str) -> Spec {
    Spec {
        replacement: Some(replacement),
        ..BASE
    }
}

const INLINE: ArgSpec = ArgSpec::Seq(Flow::Inline);
const BLOCK: ArgSpec = ArgSpec::Seq(Flow::Block);
const SYMBOL: ArgSpec = ArgSpec::Symbol;
const URL: ArgSpec = ArgSpec::Url;
const NUMBER: ArgSpec = ArgSpec::Number;
const EXPR: MathArg = MathArg::Expr;
const MSYMBOL: MathArg = MathArg::Symbol;

macro_rules! symbols {
    ($( $(#[doc = $doc:literal])* $variant:ident = $name:literal => $spec:expr, )*) => {
        /// A resolved command, environment or math command name.
        #[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
        pub enum Sym {
            $( $(#[doc = $doc])* $variant, )*
            /// A name that is not in the registry.
            Other,
        }

        static SPECS: &[Spec] = &[
            $( Spec { name: $name, doc: concat!($($doc, "\n"),*), ..$spec }, )*
            BASE,
        ];

        impl Sym {
            /// Every registered name, in declaration order.
            pub const ALL: &'static [Sym] = &[ $( Sym::$variant, )* ];

            /// Resolves a name written without the backslash.
            pub fn from_name(name: &str) -> Sym {
                match name {
                    $( $name => Sym::$variant, )*
                    _ => Sym::Other,
                }
            }
        }
    };
}

impl Sym {
    /// What the registry knows about this name. [`Sym::Other`] takes no
    /// arguments.
    pub fn spec(self) -> &'static Spec {
        &SPECS[self as usize]
    }

    /// The name as written, without the backslash. Empty for [`Sym::Other`].
    pub fn name(self) -> &'static str {
        self.spec().name
    }
}

symbols! {
    // ------------------------------------------------------------ commands
    /// Opens an environment: `\begin{name}`.
    Begin = "begin" => cmd(&[SYMBOL]),
    /// Closes an environment: `\end{name}`.
    End = "end" => cmd(&[SYMBOL]),
    /// Places an anchor that `\ref` and `\nameref` can point to.
    Label = "label" => cmd(&[SYMBOL]),
    /// Inserts a named dingbat, such as `heavy-check`.
    Dingbat = "dingbat" => cmd(&[SYMBOL]),
    /// Starts a section: `\section{anchor}{title}`.
    Section = "section" => cmd(&[SYMBOL, INLINE]),
    /// Starts a section without a title.
    SectionStar = "section*" => PLAIN,
    /// Starts a subsection: `\subsection{anchor}{title}`.
    Subsection = "subsection" => cmd(&[SYMBOL, INLINE]),
    /// A hyperlink: `\href{url}{text}`.
    Href = "href" => cmd(&[URL, INLINE]),
    /// Links the article's Reddit discussion.
    Reddit = "reddit" => cmd(&[URL]),
    /// Links the article's Hacker News discussion.
    Hackernews = "hackernews" => cmd(&[URL]),
    /// Links the article's Lobsters discussion.
    Lobsters = "lobsters" => cmd(&[URL]),
    /// Declares the document class: `article` or `note`.
    Documentclass = "documentclass" => cmd(&[SYMBOL]),
    /// Inserts an image: `\includegraphics{path}`.
    Includegraphics = "includegraphics" => cmd(&[INLINE]),
    /// The publication date, as `YYYY-MM-DD`.
    Date = "date" => cmd(&[SYMBOL]),
    /// A collapsible block: `\details{summary}{body}`.
    Details = "details" => cmd(&[INLINE, BLOCK]),
    /// The date of the last modification, as `YYYY-MM-DD`.
    Modified = "modified" => cmd(&[SYMBOL]),
    /// Tags the article with a keyword.
    Keyword = "keyword" => cmd(&[SYMBOL]),
    /// The document title.
    Title = "title" => cmd(&[INLINE]),
    /// The document subtitle.
    Subtitle = "subtitle" => cmd(&[INLINE]),
    /// Marks the article as featured.
    Featured = "featured" => PLAIN,
    /// Bold text.
    B = "b" => cmd(&[INLINE]),
    /// Italic text.
    Textit = "textit" => cmd(&[INLINE]),
    /// Underlined text.
    U = "u" => cmd(&[INLINE]),
    /// Text in the normal style.
    Normal = "normal" => cmd(&[INLINE]),
    /// Emphasized text.
    Emph = "emph" => cmd(&[INLINE]),
    /// Text in small capitals.
    Textsc = "textsc" => cmd(&[INLINE]),
    /// A circled number.
    Circled = "circled" => cmd(&[NUMBER]),
    /// Inline code as a command; a code listing as an environment.
    Code = "code" => cmd(&[INLINE]),
    /// Centered content.
    Center = "center" => cmd(&[BLOCK]),
    /// Starts an item of a list.
    Item = "item" => PLAIN,
    /// Text set as math.
    Math = "math" => cmd(&[INLINE]),
    /// Subscript text.
    Sub = "sub" => cmd(&[INLINE]),
    /// Superscript text.
    Sup = "sup" => cmd(&[INLINE]),
    /// A function name.
    Fun = "fun" => cmd(&[INLINE]),
    /// Struck-through text.
    Strikethrough = "strikethrough" => cmd(&[INLINE]),
    /// The end-of-proof mark.
    Qed = "qed" => PLAIN,
    /// A highlighted piece of advice: `\advice{anchor}{text}`.
    Advice = "advice" => cmd(&[SYMBOL, INLINE]),
    /// A note in the margin: `\marginnote{anchor}{text}`.
    Marginnote = "marginnote" => cmd(&[SYMBOL, BLOCK]),
    /// A side note: `\sidenote{anchor}{text}`.
    Sidenote = "sidenote" => cmd(&[SYMBOL, BLOCK]),
    /// A line break.
    Newline = "newline" => PLAIN,
    /// A space as wide as a digit.
    Numspace = "numspace" => PLAIN,
    /// A horizontal rule; in a table, a border between rows.
    Hrule = "hrule" => PLAIN,
    /// An epigraph: `\epigraph{quote}{attribution}`.
    Epigraph = "epigraph" => cmd(&[BLOCK, INLINE]),
    /// A block quotation: `\blockquote{quote}{attribution}`.
    Blockquote = "blockquote" => cmd(&[BLOCK, INLINE]),
    /// The title of a cited work.
    Cite = "cite" => cmd(&[INLINE]),
    /// A bibliography reference: `\bibref[postnote]{key}`.
    Bibref = "bibref" => Spec { opt: OptSpec::Seq, ..cmd(&[ArgSpec::BibKey]) },
    /// A table cell spanning columns: `\multicolumn{n}{alignment}{content}`.
    Multicolumn = "multicolumn" => cmd(&[NUMBER, ArgSpec::AlignSpec, INLINE]),
    /// An entry of a description list: `\term{term}{description}`.
    Term = "term" => cmd(&[INLINE, BLOCK]),
    /// A keyboard key.
    Kbd = "kbd" => cmd(&[INLINE]),
    /// A link to a label, showing the title of its section.
    Nameref = "nameref" => cmd(&[SYMBOL]),
    /// A link to a label: `\ref{label}{text}`.
    Ref = "ref" => cmd(&[SYMBOL, INLINE]),
    /// The caption of a figure.
    Figcaption = "figcaption" => cmd(&[INLINE]),

    // -------------------------------------------------------- environments
    /// The body of the document.
    Document = "document" => PLAIN,
    /// The abstract of the article.
    Abstract = "abstract" => PLAIN,
    /// A numbered list.
    Enumerate = "enumerate" => PLAIN,
    /// A bulleted list.
    Itemize = "itemize" => PLAIN,
    /// A list of checkboxes.
    Checklist = "checklist" => PLAIN,
    /// A figure.
    Figure = "figure" => PLAIN,
    /// A table whose first row is the header.
    Tabular = "tabular" => PLAIN,
    /// A table without a header row.
    TabularStar = "tabular*" => PLAIN,
    /// A description list made of `\term` entries.
    Description = "description" => PLAIN,
    /// Text reproduced exactly as written.
    Verbatim = "verbatim" => PLAIN,
    /// Display math aligned at `&`.
    AlignStar = "align*" => PLAIN,

    // ------------------------------------------------------- math commands
    /// A fraction: `\frac{numerator}{denominator}`.
    Frac = "frac" => math(&[EXPR, EXPR]),
    /// A binomial coefficient: `\binom{n}{k}`.
    Binom = "binom" => math(&[EXPR, EXPR]),
    /// A named operator, such as `\operatorname{argmax}`.
    Operatorname = "operatorname" => math(&[MSYMBOL]),
    /// Upright text in math.
    Mathrm = "mathrm" => math(&[MSYMBOL]),
    /// Calligraphic letters in math.
    Mathcal = "mathcal" => math(&[MSYMBOL]),
    /// A stretchy opening delimiter: `\left(`.
    Left = "left" => DELIMITER,
    /// A stretchy closing delimiter: `\right)`.
    Right = "right" => DELIMITER,

    // ------------------------------------------------------------- symbols
    Ldots = "ldots" => symbol("\u{2026}"),
    Cdots = "cdots" => symbol("\u{22EF}"),
    Delta = "delta" => symbol("\u{03B4}"),
    DeltaUpper = "Delta" => symbol("\u{0394}"),
    Pi = "pi" => symbol("\u{03C0}"),
    Fracslash = "fracslash" => symbol("\u{2215}"),
    Prime = "prime" => symbol("\u{2032}"),
    Times = "times" => symbol("\u{00D7}"),
    /// An invisible multiplication sign.
    Itimes = "itimes" => symbol("\u{2062}"),
    /// An invisible function application.
    ApplyFun = "applyFun" => symbol("\u{2061}"),
    Circ = "circ" => symbol("\u{2218}"),
    In = "in" => symbol("\u{2208}"),
    Ni = "ni" => symbol("\u{220B}"),
    Notin = "notin" => symbol("\u{2209}"),
    Inf = "inf" => symbol("\u{221E}"),
    Notni = "notni" => symbol("\u{220C}"),
    Setminus = "setminus" => symbol("\u{2216}"),
    Rightarrow = "rightarrow" => symbol("\u{2192}"),
    RightarrowUpper = "Rightarrow" => symbol("\u{21D2}"),
    Leftarrow = "leftarrow" => symbol("\u{2190}"),
    LeftarrowUpper = "Leftarrow" => symbol("\u{21D0}"),
    Sum = "sum" => symbol("\u{2211}"),
    Oplus = "oplus" => symbol("\u{2295}"),
    Prod = "prod" => symbol("\u{220F}"),
    Log = "log" => symbol("log"),
    Int = "int" => symbol("\u{222B}"),
    Lim = "lim" => symbol("lim"),
    Leq = "leq" => symbol("\u{2264}"),
    Approx = "approx" => symbol("\u{2248}"),
    Iff = "iff" => symbol("\u{21D4}"),
    Forall = "forall" => symbol("\u{2200}"),
    Exists = "exists" => symbol("\u{2203}"),
}

#[cfg(test)]
mod tests;
