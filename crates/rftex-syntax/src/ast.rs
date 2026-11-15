//! The abstract syntax tree: what the elaborator consumes.
//!
//! [`lower`](crate::lower::lower) derives it from the syntax tree. Unlike the
//! syntax tree it is lossy (comments and delimiters are gone) and carries
//! values: resolved names, parsed numbers, table rows with their borders.
//! Each node remembers the syntax element it came from.

use crate::registry::Sym;
use crate::tree::{NodeId, TextRange};

#[derive(Clone, PartialEq, Debug)]
pub struct Node {
    /// The syntax element this node was lowered from. For text made of
    /// several tokens, the first of them.
    pub syntax: NodeId,
    /// The source range. Its start is the position reported in diagnostics.
    pub range: TextRange,
    pub kind: NodeKind,
}

#[derive(Clone, PartialEq, Debug)]
pub enum NodeKind {
    Text(String),
    /// `\name[opts]{arg}...`. A bracketed content argument comes last.
    Cmd {
        name: Name,
        opts: Vec<String>,
        args: Vec<Arg>,
    },
    /// `\begin{name}[opts] ... \end{name}`
    Env {
        name: Name,
        opts: Vec<String>,
        body: Vec<Node>,
    },
    Group(Vec<Node>),
    Quotation(Vec<Node>),
    Table {
        name: Name,
        opts: Vec<String>,
        spec: Vec<ColSpec>,
        rows: Vec<Row>,
    },
    Math {
        display: MathDisplay,
        body: Vec<MathNode>,
    },
}

/// A command or environment name: the registry entry it resolves to, and the
/// spelling for names the registry does not know.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Name {
    pub sym: Sym,
    pub text: String,
    /// Where the name is written: the control word of a command, backslash
    /// included, or the whole `\begin{name}` of an environment.
    pub range: TextRange,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Arg {
    /// The range between the delimiters. For a value argument this is the
    /// range of the value, as nothing else may stand between the braces.
    pub range: TextRange,
    pub value: ArgValue,
}

#[derive(Clone, PartialEq, Debug)]
pub enum ArgValue {
    Nodes(Vec<Node>),
    Symbol(String),
    Number(i64),
    Url(String),
    Align(Vec<ColSpec>),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ColSpec {
    Left,
    Right,
    Center,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum RowBorder {
    None,
    Top,
    Bottom,
    Both,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Row {
    pub border: RowBorder,
    pub cells: Vec<Cell>,
}

#[derive(Clone, PartialEq, Debug)]
pub struct Cell {
    pub align: ColSpec,
    pub colspan: i64,
    pub body: Vec<Node>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MathDisplay {
    Inline,
    Display,
}

#[derive(Clone, PartialEq, Debug)]
pub enum MathNode {
    /// A nucleus with an optional subscript and superscript.
    Term {
        nucleus: Box<MathNode>,
        sub: Option<Box<MathNode>>,
        sup: Option<Box<MathNode>>,
    },
    Cmd {
        name: Name,
        args: Vec<MathNode>,
    },
    /// An operator. Delimiters after `\left` and `\right` are stretchy.
    Op {
        text: String,
        stretchy: bool,
    },
    Num(String),
    /// A single letter.
    Text(String),
    Group(Vec<MathNode>),
    /// The rows and cells of `align*`, with one alignment per column.
    Align {
        spec: Vec<ColSpec>,
        rows: Vec<Vec<Vec<MathNode>>>,
    },
}
