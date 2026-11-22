use super::*;

fn path_of(target: &str) -> Result<String, u16> {
    let uri: Uri = target.parse().unwrap();
    site_path(&uri).map_err(|response| response.status)
}

#[test]
fn site_paths() {
    for (target, path) in [
        ("/", "index.html"),
        ("/index.html", "index.html"),
        ("/notes", "notes/index.html"),
        ("/notes/", "notes/index.html"),
        ("/posts/01-a.html?utm_source=x", "posts/01-a.html"),
        ("/images/a%20b.png", "images/a b.png"),
        ("/images/caf%C3%A9.png", "images/café.png"),
        // Not an escape: left as it is, and not found later.
        ("/images/%zz.png", "images/%zz.png"),
    ] {
        assert_eq!(path_of(target).as_deref(), Ok(path), "{target}");
    }
    for target in [
        "/css/../Cargo.toml",
        "/../Cargo.toml",
        "/%2e%2e/Cargo.toml",
        "/css/%2E%2E/%2E%2E/Cargo.toml",
        "/css/./a.css",
        "/css/..%5CCargo.toml",
        "/css/a%00.css",
        "/images/%ff.png",
    ] {
        assert_eq!(path_of(target), Err(400), "{target}");
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
