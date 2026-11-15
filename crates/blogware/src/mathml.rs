//! Math as MathML.

use rftex_doc::document::{ColSpec, MathDisplay, MathNode};
use rftex_syntax::registry::Sym;

use crate::html::Html;

/// Appends `text` with `<`, `>` and `&` escaped. Math text never goes into an
/// attribute, so quotes stay.
fn escape_math(h: &mut Html, text: &str) {
    let mut rest = text;
    while let Some(index) = rest.find(['<', '>', '&']) {
        h.raw(&rest[..index]);
        h.raw(match rest.as_bytes()[index] {
            b'<' => "&lt;",
            b'>' => "&gt;",
            _ => "&amp;",
        });
        rest = &rest[index + 1..];
    }
    h.raw(rest);
}

fn math_text(h: &mut Html, tag: &str, attrs: &[(&str, &str)], text: &str) {
    h.open(tag, attrs);
    escape_math(h, text);
    h.close(tag);
}

/// The calligraphic form of an ASCII letter. Several letters live in the
/// Letterlike Symbols block rather than in the Mathematical Script range.
fn mathcal(c: char) -> char {
    let code = match c {
        'B' => 0x212C,
        'E' => 0x2130,
        'F' => 0x2131,
        'H' => 0x210B,
        'I' => 0x2110,
        'L' => 0x2112,
        'M' => 0x2133,
        'R' => 0x211B,
        'e' => 0x212F,
        'g' => 0x210A,
        'o' => 0x2134,
        'A'..='Z' => 0x1D49C + (c as u32 - 'A' as u32),
        'a'..='z' => 0x1D4B6 + (c as u32 - 'a' as u32),
        _ => return c,
    };
    char::from_u32(code).unwrap_or(c)
}

fn op(h: &mut Html, text: &str, stretchy: bool) {
    if stretchy {
        math_text(h, "mo", &[], text);
    } else {
        math_text(h, "mo", &[("stretchy", "false")], text);
    }
}

fn mrow(h: &mut Html, node: &MathNode) {
    h.elem("mrow", &[], |h| node_into(h, node));
}

fn command(h: &mut Html, sym: Sym, name: &str, args: &[MathNode]) {
    match (sym, args) {
        (Sym::Frac, [numerator, denominator]) => {
            h.elem("mrow", &[], |h| {
                h.elem("mfrac", &[], |h| {
                    mrow(h, numerator);
                    mrow(h, denominator);
                });
            });
        }
        (Sym::Binom, [n, k]) => {
            h.elem("mrow", &[], |h| {
                h.raw("<mo>(</mo>");
                h.elem("mfrac", &[("linethickness", "0")], |h| {
                    mrow(h, n);
                    mrow(h, k);
                });
                h.raw("<mo>)</mo>");
            });
        }
        (Sym::Operatorname, [MathNode::Op { text, .. }]) => math_text(h, "mi", &[], text),
        (Sym::Mathrm, [MathNode::Op { text, .. }]) => {
            math_text(h, "mi", &[("mathvariant", "normal")], text)
        }
        (Sym::Mathcal, [MathNode::Op { text, .. }]) => {
            let letters: String = text.chars().map(mathcal).collect();
            math_text(h, "mi", &[], &letters);
        }
        (Sym::Left | Sym::Right, [MathNode::Op { text, stretchy }]) => op(h, text, *stretchy),
        (_, []) => {
            let text = sym.spec().replacement.unwrap_or(name);
            h.raw("<mo>").raw(text).raw("</mo>");
        }
        (_, args) => {
            h.raw("<mo>").raw(name).raw("</mo>");
            for arg in args {
                node_into(h, arg);
            }
        }
    }
}

fn node_into(h: &mut Html, node: &MathNode) {
    match node {
        MathNode::Text(text) => math_text(h, "mi", &[], text),
        MathNode::Num(text) => {
            h.raw("<mn>").raw(text).raw("</mn>");
        }
        MathNode::Op { text, stretchy } => op(h, text, *stretchy),
        MathNode::Group(nodes) => {
            h.elem("mrow", &[], |h| nodes_into(h, nodes));
        }
        MathNode::Cmd { name, args } => command(h, name.sym, &name.text, args),
        MathNode::Term { nucleus, sub, sup } => {
            // Big operators take their limits above and below.
            let limits = matches!(
                &**nucleus,
                MathNode::Cmd { name, .. }
                    if matches!(name.sym, Sym::Sum | Sym::Prod | Sym::Int | Sym::Lim)
            );
            let tag = match (sub, sup, limits) {
                (None, None, _) => return node_into(h, nucleus),
                (Some(_), None, false) => "msub",
                (None, Some(_), false) => "msup",
                (Some(_), Some(_), false) => "msubsup",
                (Some(_), None, true) => "munder",
                (None, Some(_), true) => "mover",
                (Some(_), Some(_), true) => "munderover",
            };
            h.elem(tag, &[], |h| {
                node_into(h, nucleus);
                for script in [sub, sup].into_iter().flatten() {
                    node_into(h, script);
                }
            });
        }
        MathNode::Align { spec, rows } => {
            let columns: String = spec
                .iter()
                .map(|column| match column {
                    ColSpec::Left => "left ",
                    ColSpec::Right => "right ",
                    ColSpec::Center => "center ",
                })
                .collect();
            let attrs: &[(&str, &str)] = if spec.is_empty() {
                &[]
            } else {
                &[("columnalign", &columns)]
            };
            h.elem("mtable", attrs, |h| {
                for row in rows {
                    h.elem("mtr", &[], |h| {
                        for cell in row {
                            h.elem("mtd", &[], |h| {
                                h.elem("mrow", &[], |h| nodes_into(h, cell));
                            });
                        }
                    });
                }
            });
        }
    }
}

fn nodes_into(h: &mut Html, nodes: &[MathNode]) {
    for node in nodes {
        node_into(h, node);
    }
}

/// Renders one node, for tests.
pub fn node(node: &MathNode) -> String {
    let mut h = Html::new();
    node_into(&mut h, node);
    h.finish()
}

/// Appends a `math` element.
pub fn math(h: &mut Html, display: MathDisplay, nodes: &[MathNode]) {
    let mut attrs = vec![
        ("xmlns", "http://www.w3.org/1998/Math/MathML"),
        ("class", "math"),
    ];
    if display == MathDisplay::Display {
        attrs.push(("display", "block"));
    }
    h.elem("math", &attrs, |h| nodes_into(h, nodes));
}

#[cfg(test)]
mod tests;
