//! End-to-end tests of `blogware serve`.

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Shutdown, TcpStream};
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
    serve::get(Path::new(input), &preview(), &target.parse().unwrap())
}

fn text(response: &Response) -> (u16, &str) {
    (
        response.status,
        std::str::from_utf8(&response.body).unwrap(),
    )
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
    assert_eq!(css.body, fs::read("../../css/mmapped.css").unwrap());
    assert_eq!(get(BLOG, "/robots.txt").status, 200);
    assert_eq!(
        get(BLOG, "/feed.xml").content_type,
        "application/atom+xml; charset=utf-8"
    );

    // What is missing, and why.
    for (target, message) in [
        ("/nowhere.html", "no page at /nowhere.html"),
        ("/posts/nowhere.html", "no page at /posts/nowhere.html"),
        ("/notes/nowhere.html", "no page at /notes/nowhere.html"),
        ("/posts/", "no page at /posts/"),
        ("/css/nowhere.css", "no file at /css/nowhere.css"),
        ("/robots.txt/x", "no file at /robots.txt/x"),
        ("/css", "/css is a directory"),
    ] {
        assert_eq!(
            text(&get(BLOG, target)),
            (404, format!("Not Found: {message}").as_str())
        );
    }
    for target in [
        "/css/../Cargo.toml",
        "/css/%2e%2e/Cargo.toml",
        "/posts/../../Cargo.toml",
    ] {
        assert_eq!(
            text(&get(BLOG, target)),
            (
                400,
                format!("{target} has a `.` or `..` segment, a backslash or a NUL").as_str()
            )
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
        let expected = fs::read_to_string("tests/data/broken.stderr").unwrap();
        for line in expected.lines() {
            assert!(page.contains(&blogware::html::escape(line)), "{line}");
        }
    }
}

/// Sends `request`, such as `GET /`, to the server at `port` and returns
/// the whole response, with the names of the headers in lower case.
fn exchange(port: u16, request: &str) -> String {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    let request = format!("{request} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n");
    stream.write_all(request.as_bytes()).unwrap();
    let mut response = String::new();
    stream.read_to_string(&mut response).unwrap();
    let (head, body) = response.split_once("\r\n\r\n").unwrap();
    let head: Vec<String> = head
        .lines()
        .map(|line| match line.split_once(": ") {
            Some((name, value)) => format!("{}: {value}", name.to_ascii_lowercase()),
            None => line.to_string(),
        })
        .collect();
    format!("{}\r\n\r\n{body}", head.join("\r\n"))
}

/// A symbolic link in a static directory is served only if it leads to a
/// file inside the site, and only regular files are served at all.
#[cfg(unix)]
#[test]
fn symbolic_links_stay_inside_the_site() {
    use std::os::unix::fs::symlink;

    let root = Path::new(env!("CARGO_TARGET_TMPDIR")).join("symbolic_links_stay_inside_the_site");
    let _ = fs::remove_dir_all(&root);
    let site = root.join("site");
    fs::create_dir_all(site.join("images")).unwrap();
    fs::write(root.join("secret.txt"), "outside\n").unwrap();
    fs::write(site.join("robots.txt"), "inside\n").unwrap();
    symlink(root.join("secret.txt"), site.join("images/secret.txt")).unwrap();
    symlink(&root, site.join("images/up")).unwrap();
    symlink(site.join("robots.txt"), site.join("images/robots.txt")).unwrap();
    symlink(&root, site.join("css")).unwrap();
    let pipe = site.join("images/pipe");
    let made = Command::new("mkfifo").arg(&pipe).status().unwrap();
    assert!(made.success());

    let get = |target: &str| serve::get(&site, &preview(), &target.parse().unwrap());
    let outside = root.canonicalize().unwrap();
    for (target, link, leads_to) in [
        (
            "/images/secret.txt",
            "images/secret.txt",
            outside.join("secret.txt"),
        ),
        (
            "/images/up/secret.txt",
            "images/up/secret.txt",
            outside.join("secret.txt"),
        ),
        (
            "/css/secret.txt",
            "css/secret.txt",
            outside.join("secret.txt"),
        ),
        ("/css", "css", outside.clone()),
    ] {
        let message = format!(
            "{} leads to {}, outside the site",
            site.join(link).display(),
            leads_to.display()
        );
        assert_eq!(text(&get(target)), (403, message.as_str()), "{target}");
    }
    let inside = get("/images/robots.txt");
    assert_eq!(text(&inside), (200, "inside\n"));

    // Reading a named pipe would wait for a writer that never comes.
    let message = format!("{} is not a regular file", pipe.display());
    assert_eq!(text(&get("/images/pipe")), (403, message.as_str()));
}

#[test]
fn http() {
    let listener = serve::bind(0).unwrap();
    let port = listener.local_addr().unwrap().port();
    thread::spawn(move || serve::run(listener, BLOG.into(), preview()));

    // A connection that sends nothing does not hold up the others.
    let _idle = TcpStream::connect(("127.0.0.1", port)).unwrap();

    let robots = fs::read_to_string("../../robots.txt").unwrap();
    let response = exchange(port, "GET /robots.txt");
    assert!(response.starts_with("HTTP/1.1 200 OK\r\n"), "{response}");
    for header in [
        "content-type: text/plain; charset=utf-8".to_string(),
        format!("content-length: {}", robots.len()),
        "cache-control: no-cache".to_string(),
    ] {
        assert!(
            response.contains(&format!("\r\n{header}\r\n")),
            "{response}"
        );
    }
    assert!(
        response.ends_with(&format!("\r\n\r\n{robots}")),
        "{response}"
    );

    let response = exchange(port, "HEAD /robots.txt");
    assert!(response.starts_with("HTTP/1.1 200 OK\r\n"), "{response}");
    assert!(response.ends_with("\r\n\r\n"), "{response}");

    let response = exchange(port, "POST /");
    assert!(
        response.starts_with("HTTP/1.1 405 Method Not Allowed\r\n"),
        "{response}"
    );
    assert!(response.contains("\r\nallow: GET,HEAD\r\n"), "{response}");

    let response = exchange(port, "GET /nowhere.html");
    assert!(
        response.starts_with("HTTP/1.1 404 Not Found\r\n"),
        "{response}"
    );

    // A request cut short is not answered as if it were whole.
    let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
    stream.write_all(b"GET /robots.txt HTTP/1.1\r\n").unwrap();
    stream.shutdown(Shutdown::Write).unwrap();
    let mut response = String::new();
    stream.read_to_string(&mut response).unwrap();
    assert!(!response.contains("200 OK"), "{response}");
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
    let response = exchange(port, "GET /posts.html");
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
