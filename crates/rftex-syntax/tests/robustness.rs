//! The parser must return a well-formed tree for any input.
//!
//! This takes real documents, damages them the way an editing session does
//! (cut the file short, delete a closer, insert a stray special character)
//! and checks that parsing neither panics nor loses a byte.

mod support;

use rftex_syntax::{ast::NodeKind, lower, parse, ErrorKind};
use support::*;

/// xorshift64*: deterministic, good enough for picking edit positions.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }
}

/// Scales the number of random rounds; set `RFTEX_FUZZ_SCALE=100` for a
/// longer hunt.
fn rounds(base: usize) -> usize {
    let scale = std::env::var("RFTEX_FUZZ_SCALE")
        .ok()
        .and_then(|scale| scale.parse().ok());
    base * scale.unwrap_or(1)
}

fn check(src: &str, origin: &str) {
    let result = parse(src);
    if let Err(message) = check_invariants(src, &result) {
        panic!("{origin}: {message}\n--- input ---\n{src}");
    }
    let _ = lower(&result.tree, src);
}

const FRAGMENTS: &[&str] = &[
    "{",
    "}",
    "[",
    "]",
    "$",
    "\\[",
    "\\]",
    "\\",
    "%",
    "&",
    "\\\\",
    "``",
    "''",
    "`",
    "_",
    "^",
    "\n\n",
    "\\begin{",
    "\\end{",
    "\\begin{code}",
    "\\end{code}",
    "\\begin{verbatim}",
    "\\end{verbatim}",
    "\\begin{tabular}{l}",
    "\\end{tabular}",
    "\\begin{align*}",
    "\\end{align*}",
    "\\section{",
    "\\emph{",
    "\\href{",
    "\\left",
    "\\frac",
    "é",
    " ",
];

#[test]
fn recovery_unwinds_deeply_nested_constructs() {
    let depth = 128;
    let openers = "{".repeat(depth);
    for ending in ["", "\\section*", "\\end{document}"] {
        let prefix = if ending.starts_with("\\end") {
            "\\begin{document}"
        } else {
            ""
        };
        let src = format!("{prefix}{openers}{ending}");
        check(&src, "deep recovery");
        let result = parse(&src);
        assert_eq!(result.errors.len(), depth);
        assert!(result
            .errors
            .iter()
            .all(|error| error.kind == ErrorKind::UnclosedBrace));
    }
}

#[test]
fn oversized_table_spans_do_not_overflow() {
    let src = concat!(
        "\\begin{tabular}{l}",
        "\\multicolumn{9223372036854775807}{l}{x}&",
        "\\multicolumn{9223372036854775807}{l}{y}&",
        "\\multicolumn{2}{l}{z}&w\\\\",
        "\\end{tabular}",
    );
    let result = parse(src);
    assert!(result.errors.is_empty());
    let nodes = lower(&result.tree, src);
    let NodeKind::Table { rows, .. } = &nodes[0].kind else {
        panic!("expected a table");
    };
    assert_eq!(rows.len(), 1);
    let spans: Vec<_> = rows[0].cells.iter().map(|cell| cell.colspan).collect();
    assert_eq!(spans, [i64::MAX, i64::MAX, 2, 1]);
}

/// A random position in `src` that does not split a character.
fn position(rng: &mut Rng, src: &str) -> usize {
    let mut at = rng.below(src.len() + 1);
    while !src.is_char_boundary(at) {
        at -= 1;
    }
    at
}

#[test]
fn every_prefix_of_the_fixtures_parses() {
    let mut files = rftex_files(&data_dir("ok"));
    files.extend(rftex_files(&data_dir("err")));
    for path in files {
        let src = read(&path);
        for end in (0..=src.len()).filter(|&end| src.is_char_boundary(end)) {
            check(&src[..end], &format!("{} cut at {end}", path.display()));
        }
    }
}

#[test]
fn damaged_documents_parse() {
    let mut rng = Rng(0x9E37_79B9_7F4A_7C15);
    let mut files = corpus();
    files.extend(rftex_files(&data_dir("ok")));
    for path in files {
        let original = read(&path);
        for round in 0..rounds(40) {
            let mut src = original.clone();
            for _ in 0..=rng.below(3) {
                let at = position(&mut rng, &src);
                match rng.below(3) {
                    0 => src.insert_str(at, FRAGMENTS[rng.below(FRAGMENTS.len())]),
                    1 => {
                        // Delete up to 20 bytes.
                        let mut end = (at + rng.below(20)).min(src.len());
                        while !src.is_char_boundary(end) {
                            end += 1;
                        }
                        src.replace_range(at..end, "");
                    }
                    _ => src.truncate(at),
                }
            }
            check(&src, &format!("{} round {round}", path.display()));
        }
    }
}

#[test]
fn fragment_soup_parses() {
    let mut rng = Rng(0xD1B5_4A32_D192_ED03);
    for round in 0..rounds(3000) {
        let mut src = String::new();
        for _ in 0..rng.below(24) {
            match rng.below(4) {
                0 => src.push_str(["a", "b c", "1", "x-1", "-2", "it's"][rng.below(6)]),
                _ => src.push_str(FRAGMENTS[rng.below(FRAGMENTS.len())]),
            }
        }
        check(&src, &format!("soup {round}"));
    }
}
