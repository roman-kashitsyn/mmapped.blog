//! S-expression dump of the AST.
//!
//! The format is the contract of the differential test against the OCaml
//! parser (`blogware/lib/ast_dump.ml`): both sides print the same bytes for
//! the same input. Change them together.
//!
//! Layout rule: atoms follow the opening parenthesis on the same line, and
//! every nested list starts a new line indented by two spaces.

use crate::ast::*;

enum Sexp {
    Atom(String),
    List(Vec<Sexp>),
}

fn atom(text: impl Into<String>) -> Sexp {
    Sexp::Atom(text.into())
}

fn int(value: impl std::fmt::Display) -> Sexp {
    Sexp::Atom(value.to_string())
}

fn string(text: &str) -> Sexp {
    let mut quoted = String::with_capacity(text.len() + 2);
    quoted.push('"');
    for c in text.chars() {
        match c {
            '"' => quoted.push_str("\\\""),
            '\\' => quoted.push_str("\\\\"),
            '\n' => quoted.push_str("\\n"),
            '\t' => quoted.push_str("\\t"),
            c => quoted.push(c),
        }
    }
    quoted.push('"');
    Sexp::Atom(quoted)
}

fn list(head: &str, items: impl IntoIterator<Item = Sexp>) -> Sexp {
    Sexp::List(std::iter::once(atom(head)).chain(items).collect())
}

fn spec_string(spec: &[ColSpec]) -> Sexp {
    let letters: String = spec
        .iter()
        .map(|column| match column {
            ColSpec::Left => 'l',
            ColSpec::Right => 'r',
            ColSpec::Center => 'c',
        })
        .collect();
    string(&letters)
}

fn opts(opts: &[String]) -> Sexp {
    list("opts", opts.iter().map(|opt| string(opt)))
}

fn math(node: &MathNode) -> Sexp {
    match node {
        MathNode::Term { nucleus, sub, sup } => {
            let script = |script: &Option<Box<MathNode>>| match script {
                Some(node) => math(node),
                None => atom("_"),
            };
            list("term", [math(nucleus), script(sub), script(sup)])
        }
        MathNode::Cmd { name, args } => list(
            "mcmd",
            std::iter::once(atom(&name.text)).chain(args.iter().map(math)),
        ),
        MathNode::Op { text, stretchy } => {
            list(if *stretchy { "sop" } else { "op" }, [string(text)])
        }
        MathNode::Num(text) => list("num", [string(text)]),
        MathNode::Text(text) => list("mtext", [string(text)]),
        MathNode::Group(nodes) => list("mgroup", nodes.iter().map(math)),
        MathNode::Align { spec, rows } => {
            let cell = |cell: &Vec<MathNode>| list("cell", cell.iter().map(math));
            let row = |row: &Vec<Vec<MathNode>>| list("row", row.iter().map(cell));
            list(
                "align",
                std::iter::once(spec_string(spec)).chain(rows.iter().map(row)),
            )
        }
    }
}

fn arg(arg: &Arg) -> Sexp {
    let pos = int(arg.pos);
    match &arg.value {
        ArgValue::Nodes(nodes) => list("nodes", std::iter::once(pos).chain(nodes.iter().map(node))),
        ArgValue::Symbol(text) => list("sym", [pos, string(text)]),
        ArgValue::Number(value) => list("num", [pos, int(value)]),
        ArgValue::Url(text) => list("url", [pos, string(text)]),
        ArgValue::Align(spec) => list("align", [pos, spec_string(spec)]),
    }
}

fn row(row: &Row) -> Sexp {
    let border = match row.border {
        RowBorder::None => "none",
        RowBorder::Top => "top",
        RowBorder::Bottom => "bottom",
        RowBorder::Both => "both",
    };
    let cell = |cell: &Cell| {
        let head = [spec_string(&[cell.align]), int(cell.colspan)];
        list("cell", head.into_iter().chain(cell.body.iter().map(node)))
    };
    list(
        "row",
        std::iter::once(atom(border)).chain(row.cells.iter().map(cell)),
    )
}

fn node(n: &Node) -> Sexp {
    let start = int(n.range.start);
    let end = int(n.range.end);
    match &n.kind {
        NodeKind::Text(text) => list("text", [start, string(text)]),
        NodeKind::Cmd {
            name,
            opts: options,
            args,
        } => {
            let head = [start, atom(&name.text), opts(options)];
            list("cmd", head.into_iter().chain(args.iter().map(arg)))
        }
        NodeKind::Env {
            name,
            opts: options,
            body,
        } => {
            let head = [start, end, atom(&name.text), opts(options)];
            list("env", head.into_iter().chain(body.iter().map(node)))
        }
        NodeKind::Group(body) => list("group", std::iter::once(start).chain(body.iter().map(node))),
        NodeKind::Quotation(body) => {
            list("quote", std::iter::once(start).chain(body.iter().map(node)))
        }
        NodeKind::Table {
            name,
            opts: options,
            spec,
            rows,
        } => {
            let head = [
                start,
                end,
                atom(&name.text),
                opts(options),
                spec_string(spec),
            ];
            list("table", head.into_iter().chain(rows.iter().map(row)))
        }
        NodeKind::Math { display, body } => {
            let mode = match display {
                MathDisplay::Inline => "inline",
                MathDisplay::Display => "display",
            };
            list(
                "math",
                [start, atom(mode)].into_iter().chain(body.iter().map(math)),
            )
        }
    }
}

fn print(sexp: &Sexp, indent: usize, out: &mut String) {
    match sexp {
        Sexp::Atom(text) => out.push_str(text),
        Sexp::List(items) => {
            out.push('(');
            for (index, item) in items.iter().enumerate() {
                match item {
                    Sexp::Atom(_) if index > 0 => out.push(' '),
                    Sexp::Atom(_) => {}
                    Sexp::List(_) => {
                        out.push('\n');
                        out.push_str(&" ".repeat(indent + 2));
                    }
                }
                print(item, indent + 2, out);
            }
            out.push(')');
        }
    }
}

/// Renders a lowered document, one top-level node after another.
pub fn dump_document(nodes: &[Node]) -> String {
    let mut out = String::new();
    for n in nodes {
        print(&node(n), 0, &mut out);
        out.push('\n');
    }
    out
}
