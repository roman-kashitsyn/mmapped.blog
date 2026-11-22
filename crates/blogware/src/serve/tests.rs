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
