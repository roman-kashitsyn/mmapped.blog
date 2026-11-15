use super::*;

fn at(src: &str, offset: u32) -> (u32, u32) {
    let position = LineIndex::new(src).line_col(src, offset);
    (position.line, position.column)
}

#[test]
fn offsets_resolve_to_lines_and_columns() {
    let src = "ab\ncd\n";
    assert_eq!(at(src, 0), (1, 1));
    assert_eq!(at(src, 2), (1, 3));
    assert_eq!(at(src, 3), (2, 1));
    assert_eq!(at(src, 5), (2, 3));
    assert_eq!(at(src, 6), (3, 1));
    assert_eq!(at(src, 100), (3, 1));
    assert_eq!(at("", 0), (1, 1));
}

#[test]
fn columns_count_characters() {
    let src = "é \\end";
    assert_eq!(at(src, 3), (1, 3));
    // Inside the two bytes of `é`.
    assert_eq!(at(src, 1), (1, 1));
}

#[test]
fn line_ranges_exclude_the_newline() {
    let src = "ab\n\ncd";
    let index = LineIndex::new(src);
    assert_eq!(index.line_count(), 3);
    assert_eq!(index.line_range(1), Some(TextRange::new(0, 2)));
    assert_eq!(index.line_range(2), Some(TextRange::new(3, 3)));
    assert_eq!(index.line_range(3), Some(TextRange::new(4, 6)));
    assert_eq!(index.line_range(0), None);
    assert_eq!(index.line_range(4), None);
}
