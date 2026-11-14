//! Lowering: from the syntax tree to the [`ast`](crate::ast).
//!
//! This is where syntax becomes values: runs of text tokens are joined,
//! names are resolved, table rows get their borders, `align*` gets its
//! column alignment. Lowering never fails. Where the tree has errors, the
//! broken piece is dropped or takes a neutral value, so callers that need a
//! faithful result must check the parse errors first.
//!
//! The output is kept identical to the OCaml parser's (`tex_parser.ml`),
//! node boundaries included; the differential test enforces that.

use crate::ast::{self, ArgValue, ColSpec, MathDisplay, MathNode, Name, Node, NodeKind, RowBorder};
use crate::kind::SyntaxKind::{self, *};
use crate::registry::{ArgSpec, MathSig, Sym};
use crate::tree::{Children, NodeId, TextRange, Tree};

/// Lowers a parsed document. `src` must be the source `tree` was parsed from.
pub fn lower(tree: &Tree, src: &str) -> Vec<Node> {
    let lower = Lower { tree, src };
    lower.content(lower.children(tree.root()), Ctx::Plain)
}

/// How text tokens combine into text nodes.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Ctx {
    Plain,
    /// Inside a quotation every apostrophe is a node of its own.
    Quote,
    /// In a table cell quotes and backticks are ordinary text.
    Cell,
    Code,
}

impl Ctx {
    /// Whether adjacent tokens of this kind join into one text node.
    fn joins(self, kind: SyntaxKind) -> bool {
        match self {
            Ctx::Plain => matches!(kind, Text | ParBreak | CloseQuote),
            Ctx::Quote => matches!(kind, Text | ParBreak),
            Ctx::Cell => matches!(kind, Text | ParBreak | CloseQuote | OpenQuote | Backtick),
            Ctx::Code => kind == Text,
        }
    }
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

    fn name(&self, text: &str) -> Name {
        Name {
            sym: Sym::from_name(text),
            text: text.to_string(),
        }
    }

    // ------------------------------------------------------------ content

    fn content(&self, items: impl IntoIterator<Item = NodeId>, ctx: Ctx) -> Vec<Node> {
        let mut out = Vec::new();
        self.content_into(items, ctx, 0, &mut out);
        out
    }

    /// Lowers a sequence of sibling elements. Text before `min_start` is
    /// dropped.
    fn content_into(
        &self,
        items: impl IntoIterator<Item = NodeId>,
        ctx: Ctx,
        min_start: u32,
        out: &mut Vec<Node>,
    ) {
        let mut run: Option<(NodeId, TextRange)> = None;
        for id in items {
            let kind = self.kind(id);
            let range = self.tree.range(id);
            if ctx.joins(kind) {
                let start = range.start.max(min_start);
                match &mut run {
                    Some((_, joined)) => joined.end = range.end,
                    None => run = Some((id, TextRange::new(start, range.end))),
                }
                continue;
            }
            // Anything else ends the run, comments included: text on the two
            // sides of a comment stays in two nodes.
            self.flush(run.take(), ctx, out);
            match kind {
                // An escape stands for the character after the backslash.
                Escape | DoubleBackslash => out.push(Node {
                    syntax: id,
                    range,
                    kind: NodeKind::Text(self.text(id)[1..].to_string()),
                }),
                LBracket | RBracket | Backtick | OpenQuote | CloseQuote => {
                    out.push(self.text_node(id, range))
                }
                Command => out.push(self.command(id)),
                Group => out.push(Node {
                    syntax: id,
                    range,
                    kind: NodeKind::Group(self.content(self.children(id), Ctx::Plain)),
                }),
                Quotation => {
                    let inner = self.inner_children(id, CloseQuote);
                    out.push(Node {
                        syntax: id,
                        range,
                        kind: NodeKind::Quotation(self.content(inner, Ctx::Quote)),
                    });
                }
                UnclosedQuotation => {
                    // The quote never closes, so the two backticks are
                    // literal and the rest is ordinary content of the parent.
                    for offset in [range.start, range.start + 1] {
                        out.push(self.text_node(id, TextRange::new(offset, offset + 1)));
                    }
                    self.content_into(self.children(id).skip(1), ctx, 0, out);
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
        self.flush(run, ctx, out);
    }

    fn flush(&self, run: Option<(NodeId, TextRange)>, ctx: Ctx, out: &mut Vec<Node>) {
        let Some((id, range)) = run else { return };
        if range.is_empty() {
            return;
        }
        if ctx != Ctx::Quote {
            out.push(self.text_node(id, range));
            return;
        }
        let mut start = range.start;
        for (index, _) in range.slice(self.src).match_indices('\'') {
            let quote = range.start + index as u32;
            if start < quote {
                out.push(self.text_node(id, TextRange::new(start, quote)));
            }
            out.push(self.text_node(id, TextRange::new(quote, quote + 1)));
            start = quote + 1;
        }
        if start < range.end {
            out.push(self.text_node(id, TextRange::new(start, range.end)));
        }
    }

    // ----------------------------------------------------------- commands

    fn command(&self, id: NodeId) -> Node {
        let name = self.child_text(id, ControlWord).unwrap_or("\\");
        let name = self.name(name[1..].trim_end_matches(' '));
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
                        pos: self.tree.range(child).start + 1,
                        value: ArgValue::Nodes(self.content(inner, Ctx::Plain)),
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
            ArgSpec::Seq(_) => ArgValue::Nodes(self.content(self.children(id), Ctx::Plain)),
            ArgSpec::Symbol | ArgSpec::BibKey => ArgValue::Symbol(atom.to_string()),
            ArgSpec::Number => ArgValue::Number(atom.parse().unwrap_or(0)),
            ArgSpec::Url => ArgValue::Url(atom.to_string()),
            ArgSpec::AlignSpec => ArgValue::Align(col_specs(atom)),
        };
        ast::Arg {
            pos: self.tree.range(id).start + 1,
            value,
        }
    }

    // ------------------------------------------------------- environments

    /// Lowers an environment. One without a name has no meaning and yields
    /// nothing.
    fn environment(&self, id: NodeId) -> Option<Node> {
        let begin = self.tree.child(id, Begin)?;
        let name = self.name(self.child_text(begin, Atom)?);
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
                self.content_into(body.iter().copied(), Ctx::Code, after_newline, &mut nodes);
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
                body: self.content(body.iter().copied(), Ctx::Plain),
            },
        };
        Some(Node {
            syntax: id,
            range,
            kind,
        })
    }

    /// Groups table content into rows. This replays the row state machine of
    /// the OCaml parser, quirks included:
    ///
    /// - a row counts only once `\\` ends it, so a last row without `\\` is
    ///   dropped;
    /// - `\hrule` marks the top border of the row being built, or the bottom
    ///   border of the previous row when it comes last;
    /// - `\multicolumn` replaces the cell being built and starts a new one.
    fn table_rows(&self, body: &[NodeId], spec: &[ColSpec]) -> Vec<ast::Row> {
        let spec_at = |index: usize| spec.get(index).copied().unwrap_or(ColSpec::Left);
        let fresh = |align| ast::Cell {
            align,
            colspan: 1,
            body: Vec::new(),
        };

        let mut rows: Vec<ast::Row> = Vec::new();
        let mut border = RowBorder::None;
        let mut cells: Vec<ast::Cell> = Vec::new();
        let mut current = fresh(spec_at(0));
        let mut count: usize = 1;

        for &row in body.iter().filter(|&&child| self.kind(child) == Row) {
            let mut first_cell = true;
            for child in self.tree.children(row) {
                match self.kind(child) {
                    Cell => {
                        if !first_cell {
                            let next = fresh(spec_at(count));
                            cells.push(std::mem::replace(&mut current, next));
                            count = count.saturating_add(1);
                        }
                        first_cell = false;
                        for node in self.content(self.children(child), Ctx::Cell) {
                            match self.table_item(node) {
                                TableItem::HRule => border = RowBorder::Top,
                                TableItem::Multicolumn(cell) => {
                                    let span = usize::try_from(cell.colspan).unwrap_or(0);
                                    cells.push(cell);
                                    count = count.saturating_add(span);
                                    current = fresh(spec_at(count.saturating_sub(1)));
                                }
                                TableItem::Content(node) => current.body.push(node),
                            }
                        }
                    }
                    DoubleBackslash => {
                        let next = fresh(spec_at(0));
                        cells.push(std::mem::replace(&mut current, next));
                        rows.push(ast::Row {
                            border,
                            cells: std::mem::take(&mut cells),
                        });
                        border = RowBorder::None;
                        count = 1;
                    }
                    _ => {}
                }
            }
        }

        if border == RowBorder::Top && cells.is_empty() {
            if let Some(last) = rows.last_mut() {
                last.border = match last.border {
                    RowBorder::None | RowBorder::Bottom => RowBorder::Bottom,
                    RowBorder::Top | RowBorder::Both => RowBorder::Both,
                };
            }
        }
        rows
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
        let name = self.child_text(id, ControlWord).unwrap_or("\\");
        let name = self.name(name[1..].trim_end_matches(' '));
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
