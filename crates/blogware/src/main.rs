//! The command line of the blog engine.

use std::io::IsTerminal;
use std::path::PathBuf;
use std::process::ExitCode;

use blogware::{report, site};

const USAGE: &str = "\
Usage: blogware <command> [options]

Commands:
  check          Check the sources of the site and report every error

Options:
  --input DIR    The directory of the site (default: .)
  -h, --help     Print this help
";

enum Command {
    Check { input: PathBuf },
    Help,
}

fn parse_args(args: &[String]) -> Result<Command, String> {
    let mut command = None;
    let mut input = PathBuf::from(".");
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "--input" => {
                input = args
                    .next()
                    .map(PathBuf::from)
                    .ok_or("--input requires a directory")?;
            }
            option if option.starts_with('-') => return Err(format!("unknown option: {option}")),
            name if command.is_none() => command = Some(name),
            extra => return Err(format!("unexpected argument: {extra}")),
        }
    }
    match command {
        Some("check") => Ok(Command::Check { input }),
        Some(name) => Err(format!("unknown command: {name}")),
        None => Err("a command is required".to_string()),
    }
}

fn check(input: PathBuf) -> ExitCode {
    match site::load(&input) {
        Ok(site) => {
            println!(
                "ok: {} articles, {} notes, {} bibliography entries",
                site.articles.len(),
                site.notes.len(),
                site.bib.len()
            );
            ExitCode::SUCCESS
        }
        Err(failure) => {
            let stderr = std::io::stderr();
            let color = stderr.is_terminal() && std::env::var_os("NO_COLOR").is_none();
            eprint!("{}", report::render(&failure, color));
            ExitCode::FAILURE
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match parse_args(&args) {
        Ok(Command::Check { input }) => check(input),
        Ok(Command::Help) => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        Err(message) => {
            eprintln!("error: {message}\n\n{USAGE}");
            ExitCode::from(2)
        }
    }
}
