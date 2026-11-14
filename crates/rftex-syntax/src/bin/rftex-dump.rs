//! Prints the syntax tree or the AST of rftex files.
//!
//! Usage: rftex-dump (cst|ast) FILE...

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (mode, paths) = match args.split_first() {
        Some((mode, paths)) if matches!(mode.as_str(), "cst" | "ast") && !paths.is_empty() => {
            (mode.as_str(), paths)
        }
        _ => {
            eprintln!("usage: rftex-dump (cst|ast) FILE...");
            return ExitCode::from(2);
        }
    };
    let mut failed = false;
    for path in paths {
        let src = match std::fs::read_to_string(path) {
            Ok(src) => src,
            Err(err) => {
                eprintln!("{path}: {err}");
                failed = true;
                continue;
            }
        };
        let parse = rftex_syntax::parse(&src);
        if mode == "cst" {
            print!("{}", parse.dump(&src));
        } else {
            print!(
                "{}",
                rftex_syntax::dump::dump_document(&rftex_syntax::lower(&parse.tree, &src))
            );
        }
        for error in &parse.errors {
            eprintln!("{path}: {error}");
            failed = true;
        }
    }
    if failed {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
