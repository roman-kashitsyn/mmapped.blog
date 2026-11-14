//! Differential test against the OCaml parser.
//!
//! For every article of the blog and every valid fixture, the AST this crate
//! produces must print exactly as the OCaml parser's does. The OCaml side is
//! `blogware -dump-ast FILE`; point `RFTEX_ORACLE` at that binary to run the
//! test (`make diff-ast` does). Without the variable the test passes without
//! checking anything, so that `cargo test` works without an OCaml toolchain.
//!
//! Known, intended differences, all on input the corpus does not contain:
//!
//! - A paragraph break ends an inline argument and inline math with an
//!   error; OCaml lets them span paragraphs.
//! - A section heading ends open braces and math with an error; OCaml
//!   accepts a heading inside them.
//! - Some input OCaml rejects parses here without errors: brackets in table
//!   cells, an empty option list, a space in `\end {name}`.

mod support;

use std::process::Command;

use rftex_syntax::{dump::dump_document, lower, parse};
use support::*;

#[test]
fn ast_matches_the_ocaml_parser() {
    let Some(oracle) = std::env::var_os("RFTEX_ORACLE") else {
        eprintln!("RFTEX_ORACLE is not set; skipping the differential test");
        return;
    };

    let mut files = corpus();
    files.extend(rftex_files(&data_dir("ok")));
    let mut failures = Vec::new();
    for path in &files {
        let output = Command::new(&oracle)
            .arg("-dump-ast")
            .arg(path)
            .output()
            .unwrap_or_else(|err| panic!("cannot run {}: {err}", oracle.to_string_lossy()));
        if !output.status.success() {
            failures.push(format!(
                "{}: the oracle rejects the file:\n{}",
                path.display(),
                String::from_utf8_lossy(&output.stderr)
            ));
            continue;
        }
        let expected = String::from_utf8(output.stdout).expect("the oracle prints UTF-8");

        let src = read(path);
        let result = parse(&src);
        if let Some(error) = result.errors.first() {
            failures.push(format!("{}: {error}", path.display()));
        }
        let actual = dump_document(&lower(&result.tree, &src));
        if actual != expected {
            failures.push(format!(
                "{}: {}",
                path.display(),
                first_difference(&expected, &actual)
            ));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
    eprintln!("{} files match the oracle", files.len());
}
