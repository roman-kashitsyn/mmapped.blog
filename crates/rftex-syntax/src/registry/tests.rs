use super::*;

#[test]
fn names_round_trip() {
    for &sym in Sym::ALL {
        assert_eq!(Sym::from_name(sym.name()), sym);
    }
    assert_eq!(Sym::from_name("nonsense"), Sym::Other);
    assert_eq!(Sym::Other.name(), "");
    assert!(Sym::Other.spec().args.is_empty());
}

#[test]
fn specs_line_up_with_variants() {
    assert_eq!(Sym::Section.spec().args, &[SYMBOL, INLINE]);
    assert_eq!(Sym::Bibref.spec().opt, OptSpec::Seq);
    assert_eq!(Sym::TabularStar.name(), "tabular*");
    assert_eq!(Sym::Left.spec().math, MathSig::Delimiter);
    assert_eq!(Sym::Exists.spec().replacement, Some("\u{2203}"));
    assert_eq!(Sym::Href.spec().doc(), "A hyperlink: `\\href{url}{text}`.");
    assert_eq!(Sym::Ldots.spec().doc(), "");
}
