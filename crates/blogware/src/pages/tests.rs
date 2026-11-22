use rftex_doc::document::Heading;

use super::*;

fn s(text: &str) -> Inline {
    Inline::Str(text.to_string())
}

fn article(slug: &str, keywords: &[&str]) -> Article {
    let date = Date::parse("2024-01-01").unwrap();
    Article {
        slug: slug.to_string(),
        title: vec![s(slug)],
        subtitle: vec![s("subtitle")],
        featured: false,
        created_at: date,
        modified_at: date,
        word_count: 42,
        keywords: keywords.iter().map(|k| k.to_string()).collect(),
        body: vec![],
        url: format!("/posts/{slug}.html"),
        reddit: None,
        hackernews: None,
        lobsters: None,
    }
}

fn head(article: &Article) -> String {
    let options = Options {
        root_url: "https://example.test".to_string(),
        analytics: false,
    };
    let mut h = Html::new();
    post_head(&mut h, &options, article);
    h.finish()
}

#[test]
fn page_head_includes_blog_posting_json_ld() {
    let head = head(&article("hello", &["ocaml", "testing"]));
    for expected in [
        "<script type=\"application/ld+json\">\n{\"@context\":\"https://schema.org\",\
         \"@type\":\"BlogPosting\",\"headline\":\"hello\",\
         \"url\":\"https://example.test/posts/hello.html\",\"mainEntityOfPage\":{\"@type\":\
         \"WebPage\",\"@id\":\"https://example.test/posts/hello.html\"},\
         \"datePublished\":\"2024-01-01\",\"dateModified\":\"2024-01-01\",\"wordCount\":42,\
         \"license\":\"http://creativecommons.org/licenses/by/4.0/\",\
         \"author\":{\"@type\":\"Person\",\"givenName\":\"Roman\",\"familyName\":\"Kashitsyn\"},\
         \"publisher\":{\"@type\":\"Person\",\"givenName\":\"Roman\",\"familyName\":\"Kashitsyn\"},\
         \"description\":\"subtitle\",\"keywords\":[\"ocaml\",\"testing\"]}\n</script>",
        "<link rel=\"canonical\" href=\"https://example.test/posts/hello.html\">",
        "<meta name=\"keywords\" content=\"ocaml,testing\">",
    ] {
        assert!(head.contains(expected), "{expected}\nnot in\n{head}");
    }
    assert!(!head.contains("Cloudflare"));
}

#[test]
fn json_ld_escapes_script_breaking_text() {
    let mut article = article("quotes", &[]);
    article.title = vec![s("A \"quoted\" <title>")];
    article.subtitle = vec![s("Fish & Chips")];
    let head = head(&article);
    assert!(head.contains("\"headline\":\"A \\\"quoted\\\" \\u003ctitle\\u003e\""));
    assert!(head.contains("\"description\":\"Fish \\u0026 Chips\""));
    assert!(!head.contains("\"keywords\":"));
}

#[test]
fn post_attributes_render_dates_and_keywords() {
    let mut article = article("hello", &["ocaml"]);
    article.modified_at = Date::parse("2024-02-03").unwrap();
    article.reddit = Some("https://reddit.com/x".to_string());
    let mut h = Html::new();
    post_attributes(&mut h, &article);
    assert_eq!(
        h.finish(),
        "<span class=\"post-attrs\"><span class=\"attr-date\" title=\"First published\"><span \
         class=\"icon\">✑</span><time datetime=\"2024-01-01\">2024-01-01</time></span><span \
         class=\"attr-date\" title=\"Last modified\"><span class=\"icon\">✂</span><time \
         datetime=\"2024-02-03\">2024-02-03</time></span><span class=\"post-keywords\"><a \
         class=\"keyword-link\" href=\"/notes/ocaml.html\">ocaml</a></span><span \
         class=\"post-icons\"><a class=\"icon-link\" href=\"https://reddit.com/x\" \
         title=\"Discuss on Reddit\" rel=\"nofollow noopener noreferrer\" target=\"_blank\"><img \
         class=\"social-icon\" src=\"/images/Reddit-Icon.svg\" alt=\"Reddit\"></a></span></span>"
    );
}

#[test]
fn toc_lists_named_sections_and_subsections() {
    let heading = |anchor: &str, title: &str| Heading {
        anchor: anchor.to_string(),
        title: vec![s(title)],
    };
    let body = [
        Block::Section {
            heading: Some(heading("intro", "A & B")),
            body: vec![],
        },
        Block::Section {
            heading: Some(heading("body", "Body")),
            body: vec![Block::Subsection {
                heading: heading("sub", "Sub"),
                body: vec![],
            }],
        },
        Block::Section {
            heading: None,
            body: vec![],
        },
    ];
    let mut h = Html::new();
    render_toc(&mut h, &extract_toc(&body));
    assert_eq!(
        h.finish(),
        "<hr>\n<ul class=\"toc toc-level-1\"><li class=\"toc toc-level-1\"><a \
         href=\"#intro\">A &amp;amp; B</a></li><li class=\"toc toc-level-1\"><a \
         href=\"#body\">Body</a><ul class=\"toc toc-level-2\"><li class=\"toc toc-level-2\"><a \
         href=\"#sub\">Sub</a></li></ul></li></ul><hr>\n"
    );
    let mut h = Html::new();
    render_toc(&mut h, &extract_toc(&[]));
    assert_eq!(h.finish(), "");
}

#[test]
fn similar_articles_by_keyword() {
    let articles = [
        article("a", &["x", "y"]),
        article("b", &["x", "y", "z"]), // Jaccard 2/3
        article("c", &["q"]),           // 0
        article("d", &["x"]),           // 1/2
        article("e", &["z"]),           // 0
    ];
    let slugs: Vec<&str> = similar_articles(&articles, 0)
        .iter()
        .map(|a| a.slug.as_str())
        .collect();
    assert_eq!(slugs, ["b", "d"]);
}

#[test]
fn heap_sort_sorts() {
    for len in 0..40 {
        let mut values: Vec<u32> = (0..len).map(|i| (i * 7919 + 13) % 23).collect();
        let mut expected = values.clone();
        expected.sort();
        ocaml_array_sort(&mut values, &|a, b| a.cmp(b));
        assert_eq!(values, expected, "{len}");
    }
}

#[test]
fn articles_by_keyword_are_newest_first() {
    let mut old = article("old", &["k"]);
    old.created_at = Date::parse("2020-01-01").unwrap();
    let new = article("new", &["k", "j"]);
    let tie = article("tie", &["k"]);
    // The site lists articles newest first by file name.
    let articles = [tie, new, old];
    let map = articles_by_keyword(&articles);
    let slugs =
        |keyword: &str| -> Vec<&str> { map[keyword].iter().map(|a| a.slug.as_str()).collect() };
    assert_eq!(slugs("k"), ["new", "tie", "old"]);
    assert_eq!(slugs("j"), ["new"]);
}
