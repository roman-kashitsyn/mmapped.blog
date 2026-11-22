use super::*;
use crate::error::ErrorKind;
use crate::parse;

/// Parses a table and returns the errors and the content of each cell.
fn table(src: &str) -> (Vec<ErrorKind>, Vec<Vec<String>>) {
    let result = parse(src);
    let errors = result.errors.iter().map(|error| error.kind).collect();
    let nodes = lower(&result.tree, src);
    let NodeKind::Table { rows, .. } = &nodes[0].kind else {
        panic!("expected a table");
    };
    let text = |cell: &ast::Cell| {
        cell.body
            .iter()
            .map(|node| match &node.kind {
                NodeKind::Text(text) => text.trim().to_string(),
                _ => "?".to_string(),
            })
            .collect::<String>()
    };
    let rows = rows
        .iter()
        .map(|row| row.cells.iter().map(text).collect())
        .collect();
    (errors, rows)
}

#[test]
fn a_last_row_without_a_row_end_is_reported_and_kept() {
    let (errors, rows) = table("\\begin{tabular}{ll}a & b \\\\ c & d\n\\end{tabular}");
    assert_eq!(errors, [ErrorKind::MissingRowEnd]);
    assert_eq!(rows, [["a", "b"], ["c", "d"]]);
}

#[test]
fn blank_text_after_the_last_row_end_is_not_a_row() {
    let (errors, rows) = table("\\begin{tabular}{l}a \\\\ \n\\hrule % rule\n\\end{tabular}");
    assert_eq!(errors, []);
    assert_eq!(rows, [["a"]]);
}

#[test]
fn an_empty_multicolumn_is_content() {
    let src = "\\begin{tabular}{l}a \\\\ \\multicolumn{1}{c}{}\\end{tabular}";
    let (errors, rows) = table(src);
    assert_eq!(errors, [ErrorKind::MissingRowEnd]);
    assert_eq!(rows, [vec!["a"], vec![""]]);
}

#[test]
fn a_nonbreaking_space_next_to_multicolumn_is_content() {
    let src = "\\begin{tabular}{l}\u{a0}\\multicolumn{1}{c}{x} \\\\\\end{tabular}";
    let (errors, _) = table(src);
    assert_eq!(errors, [ErrorKind::MisplacedMulticolumn]);
}
