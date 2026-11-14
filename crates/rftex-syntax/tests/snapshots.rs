//! Data-driven parser tests.
//!
//! Each `tests/data/ok/NAME.rftex` is valid input: it must parse without
//! errors, and its syntax tree and AST must match `NAME.cst` and `NAME.ast`.
//! The `.ast` files are what the OCaml parser prints for the same input (the
//! differential test checks that), so they are never to be edited by hand.
//!
//! Each `tests/data/err/NAME.rftex` is malformed input that shows one way the
//! parser recovers; `NAME.cst` holds the tree and the errors.
//!
//! Run with `UPDATE_SNAPSHOTS=1` to rewrite the expectations.

mod support;

use rftex_syntax::{dump::dump_document, lower, parse};
use support::*;

#[test]
fn valid_inputs() {
    let mut failures = Vec::new();
    for path in rftex_files(&data_dir("ok")) {
        let src = read(&path);
        let result = parse(&src);
        if let Err(message) = check_invariants(&src, &result) {
            failures.push(format!("{}: {message}", path.display()));
        }
        if !result.errors.is_empty() {
            failures.push(format!(
                "{}: unexpected errors:\n{}",
                path.display(),
                result.dump(&src)
            ));
        }
        let ast = dump_document(&lower(&result.tree, &src));
        failures.extend(check_snapshot(&path.with_extension("cst"), &result.dump(&src)).err());
        failures.extend(check_snapshot(&path.with_extension("ast"), &ast).err());
    }
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}

#[test]
fn malformed_inputs() {
    let mut failures = Vec::new();
    for path in rftex_files(&data_dir("err")) {
        let src = read(&path);
        let result = parse(&src);
        if let Err(message) = check_invariants(&src, &result) {
            failures.push(format!("{}: {message}", path.display()));
        }
        if result.errors.is_empty() {
            failures.push(format!("{}: expected errors, found none", path.display()));
        }
        // Lowering must cope with any tree.
        let _ = lower(&result.tree, &src);
        failures.extend(check_snapshot(&path.with_extension("cst"), &result.dump(&src)).err());
    }
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}
