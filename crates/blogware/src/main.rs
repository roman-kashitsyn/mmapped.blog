//! The command line of the blog engine.

use std::io::IsTerminal;
use std::path::PathBuf;
use std::process::ExitCode;

use blogware::pages::Options;
use blogware::site::Failure;
use blogware::{build, report, site};

const USAGE: &str = "\
Usage: blogware <command> [options]

Commands:
  check          Check the sources of the site and report every error
  build          Check the site, then write it to the output directory

Options:
  --input DIR    The directory of the site (default: .)
  --output DIR   Where `build` writes the site (required)
  --root URL     The URL `build` makes links from (default: https://mmapped.blog)
  -h, --help     Print this help
";

enum Command {
    Check {
        input: PathBuf,
    },
    Build {
        input: PathBuf,
        output: PathBuf,
        options: Options,
    },
    Help,
}

fn parse_args(args: &[String]) -> Result<Command, String> {
    let mut command = None;
    let mut input = PathBuf::from(".");
    let mut output = None;
    let mut root = None;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            option @ ("--input" | "--output" | "--root") => {
                let value = args
                    .next()
                    .ok_or_else(|| format!("{option} requires a value"))?;
                match option {
                    "--input" => input = PathBuf::from(value),
                    "--output" => output = Some(PathBuf::from(value)),
                    _ => root = Some(value.trim_end_matches('/').to_string()),
                }
            }
            option if option.starts_with('-') => return Err(format!("unknown option: {option}")),
            name if command.is_none() => command = Some(name),
            extra => return Err(format!("unexpected argument: {extra}")),
        }
    }
    match command {
        Some("check") => {
            if output.is_some() || root.is_some() {
                return Err("check takes only --input".to_string());
            }
            Ok(Command::Check { input })
        }
        Some("build") => {
            let output = output.ok_or("build requires --output")?;
            let mut options = Options::default();
            if let Some(root) = root {
                options.root_url = root;
            }
            Ok(Command::Build {
                input,
                output,
                options,
            })
        }
        Some(name) => Err(format!("unknown command: {name}")),
        None => Err("a command is required".to_string()),
    }
}

fn fail(failure: &Failure) -> ExitCode {
    let stderr = std::io::stderr();
    let color = stderr.is_terminal() && std::env::var_os("NO_COLOR").is_none();
    eprint!("{}", report::render(failure, color));
    ExitCode::FAILURE
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
        Err(failure) => fail(&failure),
    }
}

fn build(input: PathBuf, output: PathBuf, options: Options) -> ExitCode {
    match build::build(&input, &output, &options) {
        Ok(summary) => {
            println!(
                "ok: {} pages and {} static files in {}",
                summary.pages,
                summary.static_files,
                output.display()
            );
            ExitCode::SUCCESS
        }
        Err(failure) => fail(&failure),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match parse_args(&args) {
        Ok(Command::Check { input }) => check(input),
        Ok(Command::Build {
            input,
            output,
            options,
        }) => build(input, output, options),
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
