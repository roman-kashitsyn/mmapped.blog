use rftex_doc::document::Inline;
use rftex_doc::Date;

use super::*;

fn article(slug: &str, created_at: &str, modified_at: &str) -> Article {
    Article {
        slug: slug.to_string(),
        title: vec![Inline::Str("Hello".to_string())],
        subtitle: vec![Inline::Str("World".to_string())],
        featured: false,
        created_at: Date::parse(created_at).unwrap(),
        modified_at: Date::parse(modified_at).unwrap(),
        word_count: 2,
        keywords: vec!["ocaml".to_string(), "port".to_string()],
        body: vec![],
        url: format!("/posts/{slug}.html"),
        reddit: None,
        hackernews: None,
        lobsters: None,
    }
}

#[test]
fn a_feed_of_one_article() {
    assert_eq!(
        atom(
            "https://example.test",
            &[article("hello", "2024-01-02", "2024-01-03")]
        ),
        r#"<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en"><title>MMapped blog</title>
<id>https://example.test/</id>
<updated>2024-01-03T00:00:00Z</updated>
<link rel="self" href="https://example.test/feed.xml"/>
<author><name>Roman Kashitsyn</name>
</author>
<entry><id>https://example.test/posts/hello.html</id>
<title>Hello</title>
<summary>World</summary>
<published>2024-01-02T00:00:00Z</published>
<updated>2024-01-03T00:00:00Z</updated>
<link rel="alternate" href="https://example.test/posts/hello.html"/>
<author><name>Roman Kashitsyn</name>
</author>
<category term="ocaml"/>
<category term="port"/>
</entry>
</feed>
"#
    );
}

#[test]
fn the_feed_is_as_fresh_as_its_latest_change() {
    let feed = atom(
        "https://example.test",
        &[
            article("b", "2024-03-01", "2024-03-01"),
            article("a", "2024-01-01", "2024-05-01"),
        ],
    );
    assert!(
        feed.contains("<id>https://example.test/</id>\n<updated>2024-05-01T00:00:00Z</updated>")
    );
    assert!(!atom("https://example.test", &[]).contains("<updated>"));
}

#[test]
fn text_is_escaped() {
    let mut article = article("hello", "2024-01-02", "2024-01-02");
    article.title = vec![Inline::Str("Rock & \"roll\" isn't <dead>".to_string())];
    let feed = atom("https://example.test", &[article]);
    assert!(feed.contains("<title>Rock &amp; &quot;roll&quot; isn&apos;t &lt;dead&gt;</title>"));
}
