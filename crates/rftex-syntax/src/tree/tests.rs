use super::*;
use crate::kind::SyntaxKind::*;

/// `a{bc}d` as Document(Text, Group(LBrace, Text, RBrace), Text).
fn sample() -> Tree {
    let mut b = TreeBuilder::new();
    b.open(Document);
    b.token(Text, 1);
    b.open(Group);
    b.token(LBrace, 1);
    b.token(Text, 2);
    b.token(RBrace, 1);
    b.close();
    b.token(Text, 1);
    b.close();
    b.finish()
}

#[test]
fn navigation() {
    let tree = sample();
    let root = tree.root();
    assert_eq!(tree.range(root), TextRange::new(0, 6));
    let kinds: Vec<_> = tree.children(root).map(|c| tree.kind(c)).collect();
    assert_eq!(kinds, [Text, Group, Text]);

    let group = tree.child(root, Group).unwrap();
    assert_eq!(tree.range(group), TextRange::new(1, 5));
    assert_eq!(tree.parent(group), Some(root));
    assert_eq!(tree.children(group).count(), 3);
    assert_eq!(tree.descendants(group).count(), 4);
    assert_eq!(tree.parent(root), None);

    let inner = tree.token_at_offset(3).unwrap();
    assert_eq!((tree.kind(inner), tree.text(inner, "a{bc}d")), (Text, "bc"));
    assert_eq!(tree.ancestors(inner).collect::<Vec<_>>(), [group, root]);
    assert_eq!(tree.token_at_offset(6), None);

    assert_eq!(tree.covering_element(TextRange::new(2, 5)), group);
    assert_eq!(tree.covering_element(TextRange::new(0, 3)), root);
    assert_eq!(tree.covering_element(TextRange::new(2, 3)), inner);
}

#[test]
fn dump() {
    assert_eq!(
        sample().dump("a{bc}d"),
        "Document@0..6\n  Text@0..1 \"a\"\n  Group@1..5\n    LBrace@1..2 \"{\"\n    Text@2..4 \"bc\"\n    RBrace@4..5 \"}\"\n  Text@5..6 \"d\"\n"
    );
}
