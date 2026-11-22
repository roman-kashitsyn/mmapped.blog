//! The development server, `blogware serve`.
//!
//! Every request reads the site from disk again and renders only the page
//! it asks for, so the browser always shows the sources as they are now.
//! While the site has errors, every page lists all of them instead.
//!
//! The server speaks just enough HTTP/1.1 for a browser on the same
//! machine: `GET` and `HEAD`, one request per connection.

use std::fs;
use std::io::{self, Read, Write};
use std::net::{Ipv4Addr, TcpListener, TcpStream};
use std::panic::{self, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

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
        return match fs::read(input.join(&path)) {
            Ok(body) => Response {
                status: 200,
                content_type: content_type(&path),
                body,
            },
            Err(_) => Response::not_found(),
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
    TcpListener::bind((Ipv4Addr::LOCALHOST, port))
}

/// Answers the requests to `listener` until the process stops. Each
/// connection has a thread of its own, so a browser that opens a connection
/// and sends nothing does not hold up the others.
pub fn run(listener: TcpListener, input: PathBuf, options: Options) -> ! {
    let config = Arc::new((input, options));
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                let config = Arc::clone(&config);
                thread::spawn(move || handle(stream, &config.0, &config.1));
            }
            Err(err) => {
                eprintln!("error: cannot accept a connection: {err}");
                thread::sleep(Duration::from_millis(100));
            }
        }
    }
}

fn handle(mut stream: TcpStream, input: &Path, options: &Options) {
    let start = Instant::now();
    let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
    let Some(head) = read_head(&mut stream) else {
        return;
    };
    let mut request_line = head.lines().next().unwrap_or_default().split_whitespace();
    let method = request_line.next().unwrap_or_default();
    let target = request_line.next().unwrap_or("/");
    let response = match method {
        "GET" | "HEAD" => panic::catch_unwind(AssertUnwindSafe(|| get(input, options, target)))
            .unwrap_or_else(|_| Response::text(500, "Internal Server Error")),
        _ => Response::text(405, "Method Not Allowed"),
    };
    if let Err(err) = write_response(&mut stream, &response, method != "HEAD") {
        eprintln!("error: cannot answer {method} {target}: {err}");
    }
    eprintln!(
        "{method} {target} {} ({:.3}s)",
        response.status,
        start.elapsed().as_secs_f64()
    );
}

/// The request line and the headers, or `None` if the client sent nothing.
fn read_head(stream: &mut TcpStream) -> Option<String> {
    const LIMIT: usize = 64 * 1024;
    let mut head = Vec::new();
    let mut buf = [0; 4096];
    while head.len() < LIMIT && !head.windows(4).any(|w| w == b"\r\n\r\n") {
        match stream.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => head.extend_from_slice(&buf[..n]),
        }
    }
    (!head.is_empty()).then(|| String::from_utf8_lossy(&head).into_owned())
}

fn write_response(stream: &mut TcpStream, response: &Response, body: bool) -> io::Result<()> {
    let reason = match response.status {
        200 => "OK",
        404 => "Not Found",
        405 => "Method Not Allowed",
        _ => "Internal Server Error",
    };
    let allow = if response.status == 405 {
        "Allow: GET, HEAD\r\n"
    } else {
        ""
    };
    let head = format!(
        "HTTP/1.1 {} {reason}\r\n\
         Content-Type: {}\r\n\
         Content-Length: {}\r\n\
         Cache-Control: no-cache\r\n\
         Connection: close\r\n\
         {allow}\r\n",
        response.status,
        response.content_type,
        response.body.len(),
    );
    stream.write_all(head.as_bytes())?;
    if body {
        stream.write_all(&response.body)?;
    }
    stream.flush()
}

#[cfg(test)]
mod tests;
