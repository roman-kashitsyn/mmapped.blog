use std::io::{self, Read};

use super::*;

#[test]
fn request_paths() {
    for (target, path) in [
        ("/", "index.html"),
        ("/index.html", "index.html"),
        ("/notes", "notes/index.html"),
        ("/notes/", "notes/index.html"),
        ("/posts/01-a.html?utm_source=x", "posts/01-a.html"),
        ("/posts/01-a.html#intro", "posts/01-a.html"),
        ("/images/a%20b.png", "images/a b.png"),
    ] {
        assert_eq!(request_path(target).as_deref(), Some(path), "{target}");
    }
    for target in [
        "",
        "posts.html",
        "/css/../Cargo.toml",
        "/../Cargo.toml",
        "/%2e%2e/Cargo.toml",
        "/css/%2E%2E/%2E%2E/Cargo.toml",
        "/css/./a.css",
        "/css/..\\Cargo.toml",
        "/images/%zz.png",
        "/images/%f",
        "/images/%ff.png",
    ] {
        assert_eq!(request_path(target), None, "{target}");
    }
}

#[test]
fn content_types() {
    assert_eq!(content_type("index.html"), "text/html; charset=utf-8");
    assert_eq!(
        content_type("feed.xml"),
        "application/atom+xml; charset=utf-8"
    );
    assert_eq!(content_type("images/a.WEBP"), "image/webp");
    assert_eq!(
        content_type("images/a.afdesign"),
        "application/octet-stream"
    );
    assert_eq!(content_type("robots"), "application/octet-stream");
}

/// Sends `chunks` one per read, then fails as a socket does when it times
/// out.
struct TimesOut<'a> {
    chunks: Vec<&'a [u8]>,
}

impl Read for TimesOut<'_> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        if self.chunks.is_empty() {
            return Err(io::ErrorKind::WouldBlock.into());
        }
        let chunk = self.chunks.remove(0);
        buf[..chunk.len()].copy_from_slice(chunk);
        Ok(chunk.len())
    }
}

#[test]
fn request_heads() {
    let complete = |head: &str| Head::Complete(head.to_string());
    assert_eq!(
        read_head(&mut &b"GET / HTTP/1.1\r\nHost: x\r\n\r\nbody"[..]),
        complete("GET / HTTP/1.1\r\nHost: x")
    );
    assert_eq!(
        read_head(&mut TimesOut {
            chunks: vec![b"GET / HTTP/1.1\r", b"\n\r", b"\n"]
        }),
        complete("GET / HTTP/1.1")
    );
    assert_eq!(read_head(&mut &b""[..]), Head::Empty);

    // Cut short by the end of the connection or by a timeout.
    assert_eq!(read_head(&mut &b"GET / HTTP/1.1\r\n"[..]), Head::Incomplete);
    assert_eq!(
        read_head(&mut TimesOut {
            chunks: vec![b"GET / HTTP/1.1\r\n"]
        }),
        Head::Incomplete
    );

    // The blank line must end within the limit.
    let header = |len: usize| {
        let mut head = b"GET / HTTP/1.1\r\nX: ".to_vec();
        head.resize(len - 4, b'x');
        head.extend_from_slice(b"\r\n\r\n");
        head
    };
    assert!(matches!(
        read_head(&mut header(HEAD_LIMIT).as_slice()),
        Head::Complete(_)
    ));
    assert_eq!(
        read_head(&mut header(HEAD_LIMIT + 1).as_slice()),
        Head::Incomplete
    );
    assert_eq!(
        read_head(&mut vec![b'x'; 2 * HEAD_LIMIT].as_slice()),
        Head::Incomplete
    );
}
