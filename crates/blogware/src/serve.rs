//! The development server, `blogware serve`.
//!
//! Every request reads the site from disk again and renders only the page
//! it asks for, so the browser always shows the sources as they are now.
//! While the site has errors, every page lists all of them instead.
//!
//! [`get`] decides what to answer; axum speaks HTTP for it.

use std::fs;
use std::io;
use std::net::{Ipv4Addr, TcpListener};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use axum::extract::{Request, State};
use axum::http::{header, StatusCode, Uri};
use axum::middleware::{self, Next};
use axum::response::IntoResponse;
use axum::{routing, Router};

use crate::build::{self, STATIC};
use crate::html::escape;
use crate::pages::Options;
use crate::report;
use crate::site::{self, Failure};

/// The answer to a request.
#[derive(Clone, Debug)]
pub struct Response {
    pub status: u16,
    pub content_type: &'static str,
    pub body: Vec<u8>,
}

impl Response {
    fn text(status: u16, body: &str) -> Response {
        Response {
            status,
            content_type: "text/plain; charset=utf-8",
            body: body.as_bytes().to_vec(),
        }
    }

    fn not_found() -> Response {
        Response::text(404, "Not Found")
    }
}

/// The answer to `GET target` for the site in `input`.
pub fn get(input: &Path, options: &Options, target: &str) -> Response {
    let Some(path) = request_path(target) else {
        return Response::not_found();
    };
    let first = path.split('/').next().unwrap_or_default();
    if STATIC.contains(&first) {
        return match static_file(input, &path) {
            Some(body) => Response {
                status: 200,
                content_type: content_type(&path),
                body,
            },
            None => Response::not_found(),
        };
    }
    match site::load(input) {
        Ok(site) => match build::render(&site, options, &path) {
            Some(content) => Response {
                status: 200,
                content_type: content_type(&path),
                body: content.into_bytes(),
            },
            None => Response::not_found(),
        },
        Err(failure) => error_page(&failure),
    }
}

/// The contents of the file at `path` in `input`, if it is a file and,
/// with symbolic links followed, still inside `input`.
fn static_file(input: &Path, path: &str) -> Option<Vec<u8>> {
    let root = input.canonicalize().ok()?;
    let file = input.join(path).canonicalize().ok()?;
    if !file.starts_with(&root) || !file.is_file() {
        return None;
    }
    fs::read(file).ok()
}

/// The file a request target names, relative to the site: without the
/// query, percent-decoded, and with the directory indexes filled in.
/// `None` for anything that could step outside the site.
fn request_path(target: &str) -> Option<String> {
    let path = target.split(['?', '#']).next()?.strip_prefix('/')?;
    let path = percent_decode(path)?;
    if path.contains(['\\', '\0']) || path.split('/').any(|part| part == "." || part == "..") {
        return None;
    }
    Some(match path.as_str() {
        "" => "index.html".to_string(),
        "notes" | "notes/" => format!("notes/{}.html", site::NOTE_LIST),
        _ => path,
    })
}

fn percent_decode(text: &str) -> Option<String> {
    let mut bytes = Vec::with_capacity(text.len());
    let mut rest = text.as_bytes();
    while let Some((&byte, tail)) = rest.split_first() {
        if byte == b'%' {
            let hex = std::str::from_utf8(tail.get(..2)?).ok()?;
            bytes.push(u8::from_str_radix(hex, 16).ok()?);
            rest = &tail[2..];
        } else {
            bytes.push(byte);
            rest = tail;
        }
    }
    String::from_utf8(bytes).ok()
}

fn content_type(path: &str) -> &'static str {
    if path == "feed.xml" {
        return "application/atom+xml; charset=utf-8";
    }
    let extension = path.rsplit_once('.').map_or("", |(_, ext)| ext);
    match extension.to_ascii_lowercase().as_str() {
        "html" => "text/html; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "txt" => "text/plain; charset=utf-8",
        "xml" => "application/xml; charset=utf-8",
        "woff2" => "font/woff2",
        "woff" => "font/woff",
        "ttf" => "font/ttf",
        "otf" => "font/otf",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "webp" => "image/webp",
        "ico" => "image/x-icon",
        _ => "application/octet-stream",
    }
}

/// A page listing every error of the site, as `blogware check` reports them.
fn error_page(failure: &Failure) -> Response {
    let report = report::render(failure, false);
    let summary = report.lines().last().unwrap_or("errors");
    let mut body = String::new();
    for line in report.lines() {
        if line.starts_with("error") {
            body.push_str("<b>");
            body.push_str(&escape(line));
            body.push_str("</b>");
        } else {
            body.push_str(&escape(line));
        }
        body.push('\n');
    }
    let page = format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{summary}</title>
<style>
:root {{ color-scheme: light dark; --error: #c62828; }}
@media (prefers-color-scheme: dark) {{ :root {{ --error: #ef7b7b; }} }}
body {{ margin: 2rem; font-family: ui-monospace, Menlo, Consolas, monospace; }}
h1 {{ font-size: 1.25rem; color: var(--error); }}
pre {{ font: inherit; line-height: 1.4; white-space: pre-wrap; }}
b {{ color: var(--error); }}
</style>
</head>
<body>
<h1>{summary}</h1>
<p>Fix them and reload the page.</p>
<pre>{body}</pre>
</body>
</html>
"#,
        summary = escape(summary),
    );
    Response {
        status: 500,
        content_type: "text/html; charset=utf-8",
        body: page.into_bytes(),
    }
}

/// Listens on `port` of this machine only; port 0 picks a free one.
pub fn bind(port: u16) -> io::Result<TcpListener> {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port))?;
    listener.set_nonblocking(true)?;
    Ok(listener)
}

struct Config {
    input: PathBuf,
    options: Options,
}

/// Answers the requests to `listener` until the process stops.
pub fn run(listener: TcpListener, input: PathBuf, options: Options) -> io::Result<()> {
    let config = Arc::new(Config { input, options });
    // A `get` route answers `HEAD` as well, and other methods with 405.
    let app = Router::new()
        .fallback(routing::get(answer))
        .layer(middleware::from_fn(log))
        .with_state(config);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let listener = tokio::net::TcpListener::from_std(listener)?;
        axum::serve(listener, app).await
    })
}

async fn answer(State(config): State<Arc<Config>>, uri: Uri) -> axum::response::Response {
    let target = uri.path().to_string();
    // Reading and rendering the site blocks, and a panic in it must cost
    // only this request.
    let response =
        tokio::task::spawn_blocking(move || get(&config.input, &config.options, &target))
            .await
            .unwrap_or_else(|_| Response::text(500, "Internal Server Error"));
    let status = StatusCode::from_u16(response.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let headers = [
        (header::CONTENT_TYPE, response.content_type),
        (header::CACHE_CONTROL, "no-cache"),
    ];
    (status, headers, response.body).into_response()
}

/// Logs every request with its status and how long the answer took.
async fn log(request: Request, next: Next) -> axum::response::Response {
    let start = Instant::now();
    let line = format!("{} {}", request.method(), request.uri());
    let response = next.run(request).await;
    eprintln!(
        "{line} {} ({:.3}s)",
        response.status().as_u16(),
        start.elapsed().as_secs_f64()
    );
    response
}

#[cfg(test)]
mod tests;
