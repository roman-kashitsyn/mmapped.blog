//! End-to-end tests of `blogware serve`.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;

use blogware::build;
use blogware::pages::Options;
use blogware::serve::{self, Response};
use blogware::site;

const BLOG: &str = "../..";
const BROKEN: &str = "tests/data/broken";

fn preview() -> Options {
    Options {
        analytics: false,
        ..Options::default()
    }
}

fn get(input: &str, target: &str) -> Response {
    serve::get(Path::new(input), &preview(), target)
}

/// The gate: the server shows every page exactly as `build` writes it.
#[test]
fn every_page_is_served_as_built() {
    let options = preview();
    let site = site::load(Path::new(BLOG)).unwrap();
    for page in build::pages(&site, &options) {
        let response = get(BLOG, &format!("/{}", page.path));
        assert_eq!(response.status, 200, "{}", page.path);
        assert!(
            response.body == page.content.as_bytes(),
            "{} differs from the built page",
            page.path
        );
    }
    let index = get(BLOG, "/index.html").body;
    assert_eq!(get(BLOG, "/").body, index);
    assert_eq!(get(BLOG, "/?utm_source=feed").body, index);
    let notes = get(BLOG, "/notes/index.html").body;
    assert_eq!(get(BLOG, "/notes").body, notes);
    assert_eq!(get(BLOG, "/notes/").body, notes);
    assert!(!String::from_utf8(index).unwrap().contains("Cloudflare"));
}

#[test]
fn static_files() {
    let css = get(BLOG, "/css/mmapped.css");
    assert_eq!(
        (css.status, css.content_type),
        (200, "text/css; charset=utf-8")
    );
    assert_eq!(css.body, std::fs::read("../../css/mmapped.css").unwrap());
    assert_eq!(get(BLOG, "/robots.txt").status, 200);
    assert_eq!(
        get(BLOG, "/feed.xml").content_type,
        "application/atom+xml; charset=utf-8"
    );

    for target in [
        "/nowhere.html",
        "/posts/nowhere.html",
        "/notes/nowhere.html",
        "/posts/",
        "/css/nowhere.css",
        "/css",
        "/css/../Cargo.toml",
        "/css/%2e%2e/Cargo.toml",
        "/posts/../../Cargo.toml",
    ] {
        let response = get(BLOG, target);
        assert_eq!(
            (response.status, response.body.as_slice()),
            (404, &b"Not Found"[..]),
            "{target}"
        );
    }
}

/// A broken site shows the same errors as `blogware check`, on every page.
#[test]
fn every_error_is_shown_in_the_browser() {
    for target in ["/", "/posts/01-good.html", "/feed.xml", "/nowhere.html"] {
        let response = get(BROKEN, target);
        assert_eq!(
            (response.status, response.content_type),
            (500, "text/html; charset=utf-8"),
            "{target}"
        );
        let page = String::from_utf8(response.body).unwrap();
        assert!(
            page.contains("<title>25 errors in 8 files</title>"),
            "{page}"
        );
        let expected = std::fs::read_to_string("tests/data/broken.stderr").unwrap();
        for line in expected.lines() {
            assert!(page.contains(&blogware::html::escape(line)), "{line}");
        }
    }
}

/// Sends `request` to the server at `port` and returns the whole response.
fn exchange(port: u16, request: &str) -> String {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream.write_all(request.as_bytes()).unwrap();
    let mut response = String::new();
    stream.read_to_string(&mut response).unwrap();
    response
}

#[test]
fn http() {
    let listener = serve::bind(0).unwrap();
    let port = listener.local_addr().unwrap().port();
    thread::spawn(move || serve::run(listener, BLOG.into(), preview()));

    // A connection that sends nothing does not hold up the others.
    let _idle = TcpStream::connect(("127.0.0.1", port)).unwrap();

    let robots = std::fs::read_to_string("../../robots.txt").unwrap();
    let response = exchange(port, "GET /robots.txt HTTP/1.1\r\nHost: localhost\r\n\r\n");
    assert_eq!(
        response,
        format!(
            "HTTP/1.1 200 OK\r\n\
             Content-Type: text/plain; charset=utf-8\r\n\
             Content-Length: {}\r\n\
             Cache-Control: no-cache\r\n\
             Connection: close\r\n\
             \r\n\
             {robots}",
            robots.len()
        )
    );

    let response = exchange(port, "HEAD /robots.txt HTTP/1.1\r\n\r\n");
    assert!(response.starts_with("HTTP/1.1 200 OK\r\n"), "{response}");
    assert!(response.ends_with("\r\n\r\n"), "{response}");

    let response = exchange(port, "POST / HTTP/1.1\r\nContent-Length: 0\r\n\r\n");
    assert!(
        response.starts_with("HTTP/1.1 405 Method Not Allowed\r\n"),
        "{response}"
    );
    assert!(response.contains("\r\nAllow: GET, HEAD\r\n"), "{response}");

    let response = exchange(port, "GET /nowhere.html HTTP/1.1\r\n\r\n");
    assert!(
        response.starts_with("HTTP/1.1 404 Not Found\r\n"),
        "{response}"
    );
}

#[test]
fn command_line() {
    let mut server = Command::new(env!("CARGO_BIN_EXE_blogware"))
        .args(["serve", "--input", BLOG, "--port", "0"])
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stderr = BufReader::new(server.stderr.take().unwrap());
    let mut line = String::new();
    stderr.read_line(&mut line).unwrap();
    let port = line
        .trim_end()
        .strip_prefix("Listening on http://localhost:")
        .unwrap_or_else(|| panic!("{line}"))
        .parse()
        .unwrap();
    let response = exchange(port, "GET /posts.html HTTP/1.1\r\n\r\n");
    line.clear();
    stderr.read_line(&mut line).unwrap();
    server.kill().unwrap();
    server.wait().unwrap();
    assert!(response.starts_with("HTTP/1.1 200 OK\r\n"), "{response}");
    assert!(response.contains("<title>All Posts</title>"), "{response}");
    // Every request is logged.
    assert!(line.starts_with("GET /posts.html 200 ("), "{line}");

    for args in [
        &["serve", "--port"][..],
        &["serve", "--port", "http"],
        &["serve", "--port", "65536"],
        &["serve", "--output", "x"],
        &["build", "--output", "x", "--port", "8080"],
        &["check", "--port", "8080"],
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_blogware"))
            .args(args)
            .output()
            .unwrap();
        let stderr = String::from_utf8(output.stderr).unwrap();
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert!(stderr.contains("Usage: blogware"), "{stderr}");
    }
}
