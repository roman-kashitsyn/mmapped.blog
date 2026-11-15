use rftex_syntax::ast::Name;
use rftex_syntax::TextRange;

use super::*;

fn text(s: &str) -> MathNode {
    MathNode::Text(s.to_string())
}

fn num(s: &str) -> MathNode {
    MathNode::Num(s.to_string())
}

fn op(s: &str, stretchy: bool) -> MathNode {
    MathNode::Op {
        text: s.to_string(),
        stretchy,
    }
}

fn cmd(name: &str, args: Vec<MathNode>) -> MathNode {
    MathNode::Cmd {
        name: Name {
            sym: Sym::from_name(name),
            text: name.to_string(),
            range: TextRange::empty(0),
        },
        args,
    }
}

fn term(nucleus: MathNode, sub: Option<MathNode>, sup: Option<MathNode>) -> MathNode {
    MathNode::Term {
        nucleus: Box::new(nucleus),
        sub: sub.map(Box::new),
        sup: sup.map(Box::new),
    }
}

fn render(display: MathDisplay, nodes: &[MathNode]) -> String {
    let mut h = Html::new();
    math(&mut h, display, nodes);
    h.finish()
}

#[test]
fn math_elements() {
    assert_eq!(
        render(MathDisplay::Inline, &[text("x")]),
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" class=\"math\"><mi>x</mi></math>"
    );
    assert_eq!(
        render(MathDisplay::Display, &[num("42")]),
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" class=\"math\" \
         display=\"block\"><mn>42</mn></math>"
    );
}

#[test]
fn operators() {
    assert_eq!(node(&op("<", false)), "<mo stretchy=\"false\">&lt;</mo>");
    assert_eq!(node(&op("(", true)), "<mo>(</mo>");
    assert_eq!(node(&cmd("setminus", vec![])), "<mo>∖</mo>");
    assert_eq!(node(&cmd("alpha", vec![])), "<mo>alpha</mo>");
}

#[test]
fn scripts() {
    assert_eq!(
        node(&term(text("x"), Some(text("i")), None)),
        "<msub><mi>x</mi><mi>i</mi></msub>"
    );
    assert_eq!(
        node(&term(text("x"), None, Some(num("2")))),
        "<msup><mi>x</mi><mn>2</mn></msup>"
    );
    assert_eq!(
        node(&term(text("x"), Some(text("i")), Some(num("2")))),
        "<msubsup><mi>x</mi><mi>i</mi><mn>2</mn></msubsup>"
    );
    assert_eq!(
        node(&term(cmd("sum", vec![]), Some(num("1")), Some(text("n")))),
        "<munderover><mo>∑</mo><mn>1</mn><mi>n</mi></munderover>"
    );
    assert_eq!(
        node(&term(cmd("lim", vec![]), Some(text("n")), None)),
        "<munder><mo>lim</mo><mi>n</mi></munder>"
    );
    assert_eq!(node(&term(text("x"), None, None)), "<mi>x</mi>");
}

#[test]
fn commands() {
    assert_eq!(
        node(&cmd("frac", vec![text("a"), text("b")])),
        "<mrow><mfrac><mrow><mi>a</mi></mrow><mrow><mi>b</mi></mrow></mfrac></mrow>"
    );
    assert_eq!(
        node(&cmd("binom", vec![text("n"), text("k")])),
        "<mrow><mo>(</mo><mfrac linethickness=\"0\"><mrow><mi>n</mi></mrow>\
         <mrow><mi>k</mi></mrow></mfrac><mo>)</mo></mrow>"
    );
    assert_eq!(
        node(&cmd("operatorname", vec![op("max", false)])),
        "<mi>max</mi>"
    );
    assert_eq!(
        node(&cmd("mathrm", vec![op("d", false)])),
        "<mi mathvariant=\"normal\">d</mi>"
    );
    assert_eq!(
        node(&cmd("mathcal", vec![op("Abz", false)])),
        "<mi>\u{1D49C}\u{1D4B7}\u{1D4CF}</mi>"
    );
    assert_eq!(
        node(&cmd("mathcal", vec![op("BEeo1", false)])),
        "<mi>\u{212C}\u{2130}\u{212F}\u{2134}1</mi>"
    );
    assert_eq!(node(&cmd("left", vec![op("(", true)])), "<mo>(</mo>");
    // A command with arguments it does not expect shows its name.
    assert_eq!(
        node(&cmd("frac", vec![text("a")])),
        "<mo>frac</mo><mi>a</mi>"
    );
}

#[test]
fn align_table() {
    let align = MathNode::Align {
        spec: vec![ColSpec::Right, ColSpec::Left],
        rows: vec![
            vec![vec![text("a")], vec![op("=", false), text("b")]],
            vec![vec![text("c")], vec![op("=", false), text("d")]],
        ],
    };
    assert_eq!(
        node(&align),
        "<mtable columnalign=\"right left \"><mtr><mtd><mrow><mi>a</mi></mrow></mtd>\
         <mtd><mrow><mo stretchy=\"false\">=</mo><mi>b</mi></mrow></mtd></mtr><mtr>\
         <mtd><mrow><mi>c</mi></mrow></mtd><mtd><mrow><mo stretchy=\"false\">=</mo>\
         <mi>d</mi></mrow></mtd></mtr></mtable>"
    );
}
