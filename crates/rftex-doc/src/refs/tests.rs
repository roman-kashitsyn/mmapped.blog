use super::*;
use crate::analyze_article;
use crate::bib;

fn index(slugs: &[&str], bib: Option<&str>) -> Index {
    let entries = bib.map(|src| bib::parse(src).entries);
    Index::new(
        slugs.iter().map(|slug| slug.to_string()),
        entries.as_deref(),
    )
}

/// The messages of the unresolved references of an article, with the text
/// they point at.
fn unresolved(index: &Index, content: &str) -> Vec<(String, String)> {
    let src = format!("\\begin{{document}}{content}\\end{{document}}");
    let analysis = analyze_article("self", &src);
    assert_eq!(analysis.diagnostics, []);
    let article = analysis.doc.unwrap();
    index
        .check(&analysis.references, &section_anchors(&article.body))
        .into_iter()
        .map(|diagnostic| (diagnostic.message, diagnostic.range.slice(&src).to_string()))
        .collect()
}

const BIB: &str = "@misc{knuth, title = {TAOCP}}";

#[test]
fn slugs_sections_and_subsections_are_labels() {
    let index = index(&["other-post", "a-note"], Some(BIB));
    let content = "\\section{sec}{S}\\subsection{sub}{Sub}\
                   \\nameref{other-post} \\nameref{a-note} \\nameref{sec} \\ref{sub}{text} \
                   \\bibref{knuth} \\bibref[p. 1]{knuth}";
    assert_eq!(unresolved(&index, content), []);
}

#[test]
fn unknown_names_are_reported_where_they_are_written() {
    let index = index(&["other-post"], Some(BIB));
    let content = "\\nameref{nope} \\ref{other-post}{ok} \\ref{gone}{text} \\bibref{knuth97}";
    assert_eq!(
        unresolved(&index, content),
        [
            ("unknown reference `nope`".to_string(), "nope".to_string()),
            ("unknown reference `gone`".to_string(), "gone".to_string()),
            (
                "unknown bibliography entry `knuth97`".to_string(),
                "knuth97".to_string()
            ),
        ]
    );
}

#[test]
fn anchors_that_are_not_sections_are_not_labels() {
    let index = index(&[], Some(BIB));
    let content = "\\label{l}\\advice{a}{text}\\marginnote{m}{text}\\sidenote{s}{text}\
                   \\nameref{l}\\nameref{a}\\nameref{m}\\nameref{s}";
    let names: Vec<String> = unresolved(&index, content)
        .into_iter()
        .map(|(_, name)| name)
        .collect();
    assert_eq!(names, ["l", "a", "m", "s"]);
}

#[test]
fn a_document_is_not_its_own_label_unless_the_site_lists_it() {
    assert_eq!(
        unresolved(&index(&[], Some(BIB)), "\\nameref{self}").len(),
        1
    );
    assert_eq!(
        unresolved(&index(&["self"], Some(BIB)), "\\nameref{self}"),
        []
    );
}

#[test]
fn citations_are_not_checked_without_a_bibliography() {
    let content = "\\bibref{knuth} \\nameref{nope}";
    // An empty bibliography resolves nothing.
    assert_eq!(unresolved(&index(&[], Some("")), content).len(), 2);
    // A broken one is not held against the documents.
    assert_eq!(
        unresolved(&index(&[], None), content),
        [("unknown reference `nope`".to_string(), "nope".to_string())]
    );
}

#[test]
fn section_anchors_follow_the_document_order() {
    let src = "\\begin{document}pre\\section{a}{A}\\subsection{a1}{A1}\\section* \
               \\section{b}{B}\\subsection{b1}{B1}\\subsection{b2}{B2}\\end{document}";
    let article = analyze_article("self", src).doc.unwrap();
    assert_eq!(section_anchors(&article.body), ["a", "a1", "b", "b1", "b2"]);
}
