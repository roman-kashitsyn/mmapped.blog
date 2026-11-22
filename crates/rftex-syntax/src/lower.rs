//! Lowering: from the syntax tree to the [`ast`](crate::ast).
//!
//! This is where syntax becomes values: runs of text tokens are joined,
//! names are resolved, table rows get their borders, `align*` gets its
//! column alignment. Lowering never fails. Where the tree has errors, the
//! broken piece is dropped or takes a neutral value, so callers that need a
//! faithful result must check the parse errors first.

use crate::ast::{self, ArgValue, ColSpec, MathDisplay, MathNode, Name, Node, NodeKind, RowBorder};
use crate::kind::SyntaxKind::{self, *};
use crate::registry::{ArgSpec, MathSig, Sym};
use crate::tree::{Children, NodeId, TextRange, Tree};

/// Lowers a parsed document. `src` must be the source `tree` was parsed from.
pub fn lower(tree: &Tree, src: &str) -> Vec<Node> {
    let lower = Lower { tree, src };
    lower.content(lower.children(tree.root()))
}

/// Tells whether a token stands for its own source text.
/// Adjacent tokens of this kind form one text node.
fn is_literal(kind: SyntaxKind) -> bool {
    matches!(
        kind,
        Text | ParBreak | OpenQuote | CloseQuote | Backtick | LBracket | RBracket
    )
}

/// A lowered table cell, with what the row builder needs to know about it.
struct TableCell {
    cell: ast::Cell,
    /// Whether the cell contains `\hrule`.
    hrule: bool,
    /// Whether the cell has nothing but whitespace in it.
    blank: bool,
}

/// What a lowered node means to the table row builder.
enum TableItem {
    HRule,
    Multicolumn(ast::Cell),
    Content(Node),
}

struct Lower<'a> {
    tree: &'a Tree,
    src: &'a str,
}

impl<'a> Lower<'a> {
    fn children(&self, id: NodeId) -> Children<'_> {
        self.tree.children(id)
    }

    /// Children after the opener and before the closer, if it is present.
    fn inner_children(&self, id: NodeId, closer: SyntaxKind) -> impl Iterator<Item = NodeId> + '_ {
        self.children(id)
            .skip(1)
            .take_while(move |&child| self.kind(child) != closer)
    }

    /// The range between the opener of `id` and its closer. Without a
    /// closer the range extends to the end of the element.
    fn inner_range(&self, id: NodeId, closer: SyntaxKind) -> TextRange {
        let range = self.tree.range(id);
        let start = (range.start + 1).min(range.end);
        let end = self
            .children(id)
            .skip(1)
            .find(|&child| self.kind(child) == closer)
            .map_or(range.end, |closer| self.tree.range(closer).start);
        TextRange::new(start, end.max(start))
    }

    fn kind(&self, id: NodeId) -> SyntaxKind {
        self.tree.kind(id)
    }

    fn text(&self, id: NodeId) -> &'a str {
        self.tree.text(id, self.src)
    }

    fn child_text(&self, id: NodeId, kind: SyntaxKind) -> Option<&'a str> {
        self.tree.child(id, kind).map(|child| self.text(child))
    }

    fn text_node(&self, syntax: NodeId, range: TextRange) -> Node {
        Node {
            syntax,
            range,
            kind: NodeKind::Text(range.slice(self.src).to_string()),
        }
    }

    fn name(&self, text: &str, range: TextRange) -> Name {
        Name {
            sym: Sym::from_name(text),
            text: text.to_string(),
            range,
        }
    }

    /// The name of a command: its control word without the backslash and
    /// without the spaces that follow it.
    fn command_name(&self, id: NodeId) -> Name {
        let start = self.tree.range(id).start;
        let word = self.child_text(id, ControlWord).unwrap_or("\\");
        let text = word[1..].trim_end_matches(' ');
        self.name(text, TextRange::new(start, start + 1 + text.len() as u32))
    }

    // ------------------------------------------------------------ content

    fn content(&self, items: impl IntoIterator<Item = NodeId>) -> Vec<Node> {
        let mut out = Vec::new();
        self.content_into(items, 0, &mut out);
        out
    }

    /// Lowers a sequence of sibling elements. Text before `min_start` is
    /// dropped.
    fn content_into(
        &self,
        items: impl IntoIterator<Item = NodeId>,
        min_start: u32,
        out: &mut Vec<Node>,
    ) {
        let mut run: Option<(NodeId, TextRange)> = None;
        for id in items {
            let kind = self.kind(id);
            let range = self.tree.range(id);
            if is_literal(kind) {
                let start = range.start.max(min_start);
                match &mut run {
                    Some((_, joined)) => joined.end = range.end,
                    None => run = Some((id, TextRange::new(start, range.end))),
                }
                continue;
            }
            // Anything else ends the run, comments included: a text node
            // covers a contiguous piece of the source.
            self.flush(run.take(), out);
            match kind {
                // An escape stands for the character after the backslash.
                Escape | DoubleBackslash => out.push(Node {
                    syntax: id,
                    range,
                    kind: NodeKind::Text(self.text(id)[1..].to_string()),
                }),
                Command => out.push(self.command(id)),
                Group => out.push(Node {
                    syntax: id,
                    range,
                    kind: NodeKind::Group(self.content(self.children(id))),
                }),
                Quotation => {
                    let inner = self.inner_children(id, CloseQuote);
                    out.push(Node {
                        syntax: id,
                        range,
                        kind: NodeKind::Quotation(self.content(inner)),
                    });
                }
                UnclosedQuotation => {
                    // The quote never closes, so the two backticks are
                    // literal and the rest is ordinary content of the parent.
                    // Two separate backticks do not read as an opening quote.
                    for offset in [range.start, range.start + 1] {
                        out.push(self.text_node(id, TextRange::new(offset, offset + 1)));
                    }
                    self.content_into(self.children(id).skip(1), 0, out);
                }
                Environment => out.extend(self.environment(id)),
                InlineMath | DisplayMath => {
                    let display = if kind == InlineMath {
                        MathDisplay::Inline
                    } else {
                        MathDisplay::Display
                    };
                    let body = self.math_items(self.children(id));
                    out.push(Node {
                        syntax: id,
                        range,
                        kind: NodeKind::Math { display, body },
                    });
                }
                _ => {}
            }
        }
        self.flush(run, out);
    }

    fn flush(&self, run: Option<(NodeId, TextRange)>, out: &mut Vec<Node>) {
        if let Some((id, range)) = run.filter(|(_, range)| !range.is_empty()) {
            out.push(self.text_node(id, range));
        }
    }

    // ----------------------------------------------------------- commands

    fn command(&self, id: NodeId) -> Node {
        let name = self.command_name(id);
        let mut specs = name.sym.spec().args.iter();
        let mut opts = Vec::new();
        let mut args = Vec::new();
        let mut bracket = None;
        for child in self.tree.children(id) {
            match self.kind(child) {
                Options => opts = self.options(child),
                BracketArg => {
                    let inner = self.inner_children(child, RBracket);
                    bracket = Some(ast::Arg {
                        range: self.inner_range(child, RBracket),
                        value: ArgValue::Nodes(self.content(inner)),
                    });
                }
                Arg => {
                    let spec = specs.next().copied().unwrap_or(ArgSpec::Symbol);
                    args.push(self.arg(child, spec));
                }
                _ => {}
            }
        }
        // The bracketed argument is written first but comes last.
        args.extend(bracket);
        Node {
            syntax: id,
            range: self.tree.range(id),
            kind: NodeKind::Cmd { name, opts, args },
        }
    }

    fn options(&self, id: NodeId) -> Vec<String> {
        self.tree
            .children(id)
            .filter(|&child| self.kind(child) == Atom)
            .map(|child| self.text(child).to_string())
            .collect()
    }

    fn arg(&self, id: NodeId, spec: ArgSpec) -> ast::Arg {
        let atom = self.child_text(id, Atom).unwrap_or("");
        let value = match spec {
            ArgSpec::Seq(_) => ArgValue::Nodes(self.content(self.children(id))),
            ArgSpec::Symbol | ArgSpec::BibKey => ArgValue::Symbol(atom.to_string()),
            ArgSpec::Number => ArgValue::Number(atom.parse().unwrap_or(0)),
            ArgSpec::Url => ArgValue::Url(atom.to_string()),
            ArgSpec::AlignSpec => ArgValue::Align(col_specs(atom)),
        };
        ast::Arg {
            range: self.inner_range(id, RBrace),
            value,
        }
    }

    // ------------------------------------------------------- environments

    /// Lowers an environment. One without a name has no meaning and yields
    /// nothing.
    fn environment(&self, id: NodeId) -> Option<Node> {
        let begin = self.tree.child(id, Begin)?;
        let name = self.name(self.child_text(begin, Atom)?, self.tree.range(begin));
        let options = self.tree.child(id, Options);
        let opts = options
            .map(|options| self.options(options))
            .unwrap_or_default();
        let body: Vec<NodeId> = self
            .tree
            .children(id)
            .filter(|&child| !matches!(self.kind(child), Begin | End | Options))
            .collect();
        // Verbatim and code bodies start after one newline that follows the
        // opening line.
        let body_start = self.tree.range(options.unwrap_or(begin)).end;
        let after_newline = match self.src.as_bytes().get(body_start as usize) {
            Some(b'\n') => body_start + 1,
            _ => body_start,
        };
        let range = self.tree.range(id);

        let kind = match name.text.as_str() {
            "verbatim" => {
                let end = body
                    .iter()
                    .find(|&&child| self.kind(child) == RawText)
                    .map_or(body_start, |&raw| self.tree.range(raw).end);
                let text = TextRange::new(after_newline.min(end), end);
                NodeKind::Env {
                    name,
                    opts,
                    body: vec![self.text_node(id, text)],
                }
            }
            "tabular" | "tabular*" => {
                let spec = body
                    .iter()
                    .find(|&&child| self.kind(child) == Arg)
                    .and_then(|&arg| self.child_text(arg, Atom))
                    .map(col_specs)
                    .unwrap_or_default();
                let rows = self.table_rows(&body, &spec);
                NodeKind::Table {
                    name,
                    opts,
                    spec,
                    rows,
                }
            }
            "code" => {
                let mut nodes = Vec::new();
                self.content_into(body.iter().copied(), after_newline, &mut nodes);
                NodeKind::Env {
                    name,
                    opts,
                    body: nodes,
                }
            }
            "align*" => NodeKind::Math {
                display: MathDisplay::Display,
                body: vec![self.align(&body)],
            },
            _ => NodeKind::Env {
                name,
                opts,
                body: self.content(body.iter().copied()),
            },
        };
        Some(Node {
            syntax: id,
            range,
            kind,
        })
    }

    /// Groups table content into rows.
    /// A row ends at `\\` or at the end of the table.
    /// `\hrule` draws a border above the row it starts, or below the last row
    /// when nothing follows it.
    fn table_rows(&self, body: &[NodeId], spec: &[ColSpec]) -> Vec<ast::Row> {
        let mut rows: Vec<ast::Row> = Vec::new();
        for &row in body.iter().filter(|&&child| self.kind(child) == Row) {
            let mut border = RowBorder::None;
            let mut cells = Vec::new();
            let mut column: usize = 0;
            let mut ended = false;
            let mut all_blank = true;
            for child in self.children(row) {
                match self.kind(child) {
                    Cell => {
                        let align = spec.get(column).copied().unwrap_or(ColSpec::Left);
                        let TableCell { cell, hrule, blank } = self.table_cell(child, align);
                        if hrule {
                            border = RowBorder::Top;
                        }
                        all_blank &= blank;
                        let span = usize::try_from(cell.colspan).unwrap_or(0);
                        column = column.saturating_add(span);
                        cells.push(cell);
                    }
                    DoubleBackslash => ended = true,
                    _ => {}
                }
            }
            // What follows the last `\\` is a row only if it has content.
            if ended || !all_blank {
                rows.push(ast::Row { border, cells });
            } else if border == RowBorder::Top {
                if let Some(last) = rows.last_mut() {
                    last.border = match last.border {
                        RowBorder::None | RowBorder::Bottom => RowBorder::Bottom,
                        RowBorder::Top | RowBorder::Both => RowBorder::Both,
                    };
                }
            }
        }
        rows
    }

    /// Lowers a table cell with the given column alignment.
    fn table_cell(&self, id: NodeId, align: ColSpec) -> TableCell {
        let mut multicolumn = None;
        let mut hrule = false;
        let mut body = Vec::new();
        for node in self.content(self.children(id)) {
            match self.table_item(node) {
                TableItem::HRule => hrule = true,
                // The parser makes sure that only blank text surrounds it.
                TableItem::Multicolumn(cell) => multicolumn = Some(cell),
                TableItem::Content(node) => body.push(node),
            }
        }
        let blank = multicolumn.is_none() && body.iter().all(is_blank);
        let cell = multicolumn.unwrap_or(ast::Cell {
            align,
            colspan: 1,
            body,
        });
        TableCell { cell, hrule, blank }
    }

    fn table_item(&self, mut node: Node) -> TableItem {
        let NodeKind::Cmd { name, args, .. } = &mut node.kind else {
            return TableItem::Content(node);
        };
        match (name.sym, args.as_mut_slice()) {
            (Sym::Hrule, _) => TableItem::HRule,
            (
                Sym::Multicolumn,
                [ast::Arg {
                    value: ArgValue::Number(colspan),
                    ..
                }, ast::Arg {
                    value: ArgValue::Align(align),
                    ..
                }, ast::Arg {
                    value: ArgValue::Nodes(body),
                    ..
                }],
            ) if align.len() == 1 => TableItem::Multicolumn(ast::Cell {
                align: align[0],
                colspan: *colspan,
                body: std::mem::take(body),
            }),
            _ => TableItem::Content(node),
        }
    }

    // --------------------------------------------------------------- math

    fn math_items(&self, items: impl IntoIterator<Item = NodeId>) -> Vec<MathNode> {
        items
            .into_iter()
            .filter_map(|id| self.math_item(id))
            .collect()
    }

    fn math_item(&self, id: NodeId) -> Option<MathNode> {
        let text = self.text(id);
        let op = |text: &str| MathNode::Op {
            text: text.to_string(),
            stretchy: false,
        };
        Some(match self.kind(id) {
            Letter => MathNode::Text(text.to_string()),
            Number | MathNegNumber => MathNode::Num(text.to_string()),
            Operator | Newline | Amp => op(text),
            Escape | DoubleBackslash => op(&text[1..]),
            MathGroup => MathNode::Group(self.math_items(self.children(id))),
            MathCommand => self.math_command(id),
            MathTerm => return self.math_term(id),
            _ => return None,
        })
    }

    fn math_command(&self, id: NodeId) -> MathNode {
        let name = self.command_name(id);
        let args = match name.sym.spec().math {
            MathSig::Plain => Vec::new(),
            MathSig::Delimiter => self
                .tree
                .children(id)
                .find(|&child| matches!(self.kind(child), Operator | Newline | Amp | Escape))
                .map(|delimiter| {
                    let text = self.text(delimiter);
                    let text = if self.kind(delimiter) == Escape {
                        &text[1..]
                    } else {
                        text
                    };
                    MathNode::Op {
                        text: text.to_string(),
                        stretchy: true,
                    }
                })
                .into_iter()
                .collect(),
            MathSig::Args(_) => self
                .tree
                .children(id)
                .filter_map(|child| match self.kind(child) {
                    MathGroup => self.math_item(child),
                    MathArg => Some(MathNode::Op {
                        text: self.child_text(child, Atom).unwrap_or("").to_string(),
                        stretchy: false,
                    }),
                    _ => None,
                })
                .collect(),
        };
        MathNode::Cmd { name, args }
    }

    fn math_term(&self, id: NodeId) -> Option<MathNode> {
        let mut parts = self
            .tree
            .children(id)
            .filter(|&child| !self.kind(child).is_trivia());
        let nucleus = Box::new(self.math_item(parts.next()?)?);
        let (mut sub, mut sup) = (None, None);
        let mut marker = None;
        for part in parts {
            match self.kind(part) {
                kind @ (Underscore | Caret) => marker = Some(kind),
                _ => {
                    let script = self.math_item(part).map(Box::new);
                    match marker.take() {
                        Some(Underscore) => sub = script,
                        Some(Caret) => sup = script,
                        _ => {}
                    }
                }
            }
        }
        Some(MathNode::Term { nucleus, sub, sup })
    }

    /// Lowers the body of `align*`. Newlines between atoms carry no meaning
    /// here, rows without content are dropped, and the column alignment
    /// follows from the widest row: right, centered..., left.
    fn align(&self, body: &[NodeId]) -> MathNode {
        let is_newline =
            |node: &MathNode| matches!(node, MathNode::Op { text, .. } if text == "\n");
        let rows: Vec<Vec<Vec<MathNode>>> = body
            .iter()
            .filter(|&&child| self.kind(child) == Row)
            .map(|&row| {
                self.tree
                    .children(row)
                    .filter(|&child| self.kind(child) == Cell)
                    .map(|cell| {
                        let mut nodes = self.math_items(self.children(cell));
                        nodes.retain(|node| !is_newline(node));
                        nodes
                    })
                    .collect::<Vec<_>>()
            })
            .filter(|row| !row.iter().all(Vec::is_empty))
            .collect();
        let columns = rows.iter().map(Vec::len).max().unwrap_or(0);
        let spec = (0..columns)
            .map(|index| match index {
                0 => ColSpec::Right,
                _ if index == columns - 1 => ColSpec::Left,
                _ => ColSpec::Center,
            })
            .collect();
        MathNode::Align { spec, rows }
    }
}

/// Tells whether a node is text made of whitespace only.
fn is_blank(node: &Node) -> bool {
    matches!(&node.kind, NodeKind::Text(text) if text.trim_ascii().is_empty())
}

/// Reads a column specification: `l`, `r` and `c` name columns, everything
/// else is decoration.
fn col_specs(text: &str) -> Vec<ColSpec> {
    text.bytes()
        .filter_map(|c| match c {
            b'l' => Some(ColSpec::Left),
            b'r' => Some(ColSpec::Right),
            b'c' => Some(ColSpec::Center),
            _ => None,
        })
        .collect()
}

#[cfg(test)]
mod tests;
