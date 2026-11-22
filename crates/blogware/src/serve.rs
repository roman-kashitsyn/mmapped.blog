//! The development server, `blogware serve`.
//!
//! Every request reads the site from disk again and renders only the page
//! it asks for, so the browser always shows the sources as they are now.
//! While the site has errors, every page lists all of them instead.
//!
//! [`get`] decides what to answer; axum speaks HTTP for it.

use std::fs;
use std::io::{self, ErrorKind};
use std::net::{Ipv4Addr, TcpListener};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use axum::extract::{Request, State};
use axum::http::{header, StatusCode, Uri};
use axum::middleware::{self, Next};
use axum::response::IntoResponse;
use axum::{routing, Router};
use percent_encoding::percent_decode_str;

use crate::build::{self, STATIC};
use crate::html::escape;
use crate::pages::Options;
use crate::report;
use crate::site::{self, display, Failure};

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

    fn not_found(what: &str) -> Response {
        Response::text(404, &format!("Not Found: {what}"))
    }

    /// A failure the author should see in the terminal as well as in the
    /// browser.
    fn failed(status: u16, message: &str) -> Response {
        eprintln!("error: {message}");
        Response::text(status, message)
    }
}

/// The answer to `GET uri` for the site in `input`.
pub fn get(input: &Path, options: &Options, uri: &Uri) -> Response {
    let path = match site_path(uri) {
        Ok(path) => path,
        Err(response) => return response,
    };
    let first = path.split('/').next().unwrap_or_default();
    if STATIC.contains(&first) {
        return match static_file(input, &path) {
            Ok(body) => Response {
                status: 200,
                content_type: content_type(&path),
                body,
            },
            Err(response) => response,
        };
    }
    match site::load(input) {
        Ok(site) => match build::render(&site, options, &path) {
            Some(content) => Response {
                status: 200,
                content_type: content_type(&path),
                body: content.into_bytes(),
            },
            None => Response::not_found(&format!("no page at /{path}")),
        },
        Err(failure) => error_page(&failure),
    }
}

/// The contents of the file at `path` in `input`, if it is a file and,
/// with symbolic links followed, still inside `input`.
fn static_file(input: &Path, path: &str) -> Result<Vec<u8>, Response> {
    let root = input.canonicalize().map_err(|err| {
        Response::failed(
            500,
            &format!("cannot open the site {}: {err}", display(input)),
        )
    })?;
    let requested = input.join(path);
    let file = match requested.canonicalize() {
        Ok(file) => file,
        Err(err) if matches!(err.kind(), ErrorKind::NotFound | ErrorKind::NotADirectory) => {
            return Err(Response::not_found(&format!("no file at /{path}")));
        }
        Err(err) => {
            let message = format!("cannot open {}: {err}", display(&requested));
            return Err(Response::failed(500, &message));
        }
    };
    if !file.starts_with(&root) {
        let message = format!(
            "{} leads to {}, outside the site",
            display(&requested),
            file.display()
        );
        return Err(Response::failed(403, &message));
    }
    if file.is_dir() {
        return Err(Response::not_found(&format!("/{path} is a directory")));
    }
    fs::read(&file).map_err(|err| {
        Response::failed(500, &format!("cannot read {}: {err}", display(&requested)))
    })
}

/// The file `uri` names, relative to the site: percent-decoded, and with
/// the directory indexes filled in. Paths that could step outside the site
/// are refused.
fn site_path(uri: &Uri) -> Result<String, Response> {
    let raw = uri.path();
    let decoded = percent_decode_str(raw)
        .decode_utf8()
        .map_err(|_| Response::failed(400, &format!("{raw} is not UTF-8 once percent-decoded")))?;
    let path = decoded.strip_prefix('/').unwrap_or(&decoded);
    if path.contains(['\\', '\0']) || path.split('/').any(|part| part == "." || part == "..") {
        let message = format!("{raw} has a `.` or `..` segment, a backslash or a NUL");
        return Err(Response::failed(400, &message));
    }
    Ok(match path {
        "" => "index.html".to_string(),
        "notes" | "notes/" => format!("notes/{}.html", site::NOTE_LIST),
        _ => path.to_string(),
    })
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
    // Reading and rendering the site blocks, and a panic in it must cost
    // only this request.
    let response = tokio::task::spawn_blocking(move || get(&config.input, &config.options, &uri))
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
