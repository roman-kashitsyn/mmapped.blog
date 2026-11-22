//! Whole pages: the front page, the post and note pages, and the lists of
//! posts and of notes.

use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};

use rftex_doc::document::{plain_text, Article, Block, Inline, Note};
use rftex_doc::Date;

use crate::html::Html;
use crate::render::{self, Ctx, RefTable, RefTarget};
use crate::site::Site;

/// How pages are rendered.
#[derive(Clone, Debug)]
pub struct Options {
    /// The URL the site is served from, without a trailing slash.
    pub root_url: String,
    /// Whether pages load the Cloudflare analytics script.
    pub analytics: bool,
}

impl Default for Options {
    fn default() -> Options {
        Options {
            root_url: "https://mmapped.blog".to_string(),
            analytics: true,
        }
    }
}

/// HTML of inlines outside the body of a document: titles and subtitles.
fn title_html(inlines: &[Inline]) -> String {
    render::inlines_to_string(Ctx::EMPTY, inlines)
}

// -------------------------------------------------------------------- toc

struct TocEntry {
    id: String,
    /// HTML.
    title: String,
}

struct TocSection {
    entry: TocEntry,
    subsections: Vec<TocEntry>,
}

fn extract_toc(body: &[Block]) -> Vec<TocSection> {
    body.iter()
        .filter_map(|block| {
            let Block::Section {
                heading: Some(heading),
                body,
            } = block
            else {
                return None;
            };
            let subsections = body
                .iter()
                .filter_map(|block| match block {
                    Block::Subsection { heading, .. } => Some(TocEntry {
                        id: heading.anchor.clone(),
                        title: title_html(&heading.title),
                    }),
                    _ => None,
                })
                .collect();
            Some(TocSection {
                entry: TocEntry {
                    id: heading.anchor.clone(),
                    title: title_html(&heading.title),
                },
                subsections,
            })
        })
        .collect()
}

fn render_toc(h: &mut Html, toc: &[TocSection]) {
    if toc.is_empty() {
        return;
    }
    // Quirk: the titles are HTML and get escaped once more.
    let entry = |h: &mut Html, level: &str, entry: &TocEntry| {
        let href = format!("#{}", entry.id);
        h.open("li", &[("class", level)]);
        h.text_elem("a", &[("href", &href)], &entry.title);
    };
    h.open("hr", &[]).nl();
    h.elem("ul", &[("class", "toc toc-level-1")], |h| {
        for section in toc {
            entry(h, "toc toc-level-1", &section.entry);
            if !section.subsections.is_empty() {
                h.elem("ul", &[("class", "toc toc-level-2")], |h| {
                    for sub in &section.subsections {
                        entry(h, "toc toc-level-2", sub);
                        h.close("li");
                    }
                });
            }
            h.close("li");
        }
    });
    h.open("hr", &[]).nl();
}

// ------------------------------------------------------------- references

fn add_document_refs<'a>(
    refs: &mut RefTable,
    documents: impl Iterator<Item = (&'a str, &'a [Inline], &'a str)>,
) {
    for (slug, title, url) in documents {
        refs.insert(
            slug.to_string(),
            RefTarget {
                title: title_html(title),
                url: url.to_string(),
            },
        );
    }
}

/// The labels of the site: every article and note by its slug.
fn global_refs(site: &Site) -> RefTable {
    let mut refs = RefTable::new();
    add_document_refs(
        &mut refs,
        site.articles
            .iter()
            .map(|a| (a.slug.as_str(), a.title.as_slice(), a.url.as_str())),
    );
    add_document_refs(
        &mut refs,
        site.notes
            .iter()
            .map(|n| (n.slug.as_str(), n.title.as_slice(), n.url.as_str())),
    );
    refs
}

/// The labels a document can refer to: the site and its own sections.
fn document_refs(site: &Site, body: &[Block]) -> RefTable {
    let mut refs = global_refs(site);
    for section in extract_toc(body) {
        for entry in std::iter::once(section.entry).chain(section.subsections) {
            let url = format!("#{}", entry.id);
            refs.insert(
                entry.id,
                RefTarget {
                    title: entry.title,
                    url,
                },
            );
        }
    }
    refs
}

// --------------------------------------------------------------- similar

/// OCaml's `Array.sort`, a ternary heap sort, ported line by line. It is not
/// stable: ties among similar articles come out in the order it leaves them,
/// so the port must be exact for the pages to match their snapshots.
fn ocaml_array_sort<T: Copy>(a: &mut [T], cmp: &dyn Fn(&T, &T) -> Ordering) {
    /// The largest child of `i` in a heap of `l` elements; `Err(i)` (OCaml's
    /// `Bottom i`) if `i` has no children.
    fn maxson<T>(
        a: &[T],
        cmp: &dyn Fn(&T, &T) -> Ordering,
        l: usize,
        i: usize,
    ) -> Result<usize, usize> {
        let i31 = i + i + i + 1;
        if i31 + 2 < l {
            let mut x = i31;
            if cmp(&a[i31], &a[i31 + 1]) == Ordering::Less {
                x = i31 + 1;
            }
            if cmp(&a[x], &a[i31 + 2]) == Ordering::Less {
                x = i31 + 2;
            }
            Ok(x)
        } else if i31 + 1 < l && cmp(&a[i31], &a[i31 + 1]) == Ordering::Less {
            Ok(i31 + 1)
        } else if i31 < l {
            Ok(i31)
        } else {
            Err(i)
        }
    }

    fn trickledown<T: Copy>(
        a: &mut [T],
        cmp: &dyn Fn(&T, &T) -> Ordering,
        l: usize,
        mut i: usize,
        e: T,
    ) -> Result<(), usize> {
        loop {
            let j = maxson(a, cmp, l, i)?;
            if cmp(&a[j], &e) == Ordering::Greater {
                a[i] = a[j];
                i = j;
            } else {
                a[i] = e;
                return Ok(());
            }
        }
    }

    fn trickle<T: Copy>(a: &mut [T], cmp: &dyn Fn(&T, &T) -> Ordering, l: usize, i: usize, e: T) {
        if let Err(i) = trickledown(a, cmp, l, i, e) {
            a[i] = e;
        }
    }

    /// Moves the hole at `i` down along the larger children; returns where it
    /// ends.
    fn bubble<T: Copy>(
        a: &mut [T],
        cmp: &dyn Fn(&T, &T) -> Ordering,
        l: usize,
        mut i: usize,
    ) -> usize {
        loop {
            match maxson(a, cmp, l, i) {
                Ok(j) => {
                    a[i] = a[j];
                    i = j;
                }
                Err(i) => return i,
            }
        }
    }

    fn trickleup<T: Copy>(a: &mut [T], cmp: &dyn Fn(&T, &T) -> Ordering, mut i: usize, e: T) {
        loop {
            let father = (i - 1) / 3;
            if cmp(&a[father], &e) == Ordering::Less {
                a[i] = a[father];
                if father > 0 {
                    i = father;
                } else {
                    a[0] = e;
                    return;
                }
            } else {
                a[i] = e;
                return;
            }
        }
    }

    let l = a.len();
    for i in (0..(l + 1) / 3).rev() {
        let e = a[i];
        trickle(a, cmp, l, i, e);
    }
    for i in (2..l).rev() {
        let e = a[i];
        a[i] = a[0];
        let hole = bubble(a, cmp, i, 0);
        trickleup(a, cmp, hole, e);
    }
    if l > 1 {
        a.swap(0, 1);
    }
}

/// Up to five articles that share keywords with the one at `index`, most
/// similar first. Similarity is the Jaccard index of the keywords, slightly
/// lowered with the distance between the posts.
fn similar_articles(articles: &[Article], index: usize) -> Vec<&Article> {
    let target = &articles[index];
    let target_keywords: BTreeSet<&String> = target.keywords.iter().collect();
    let mut candidates: Vec<(f64, &Article)> = Vec::new();
    for (i, article) in articles.iter().enumerate() {
        if i == index {
            continue;
        }
        let common = article
            .keywords
            .iter()
            .filter(|keyword| target_keywords.contains(keyword))
            .count();
        let total = article.keywords.len() + target_keywords.len() - common;
        if total == 0 {
            continue;
        }
        let similarity = common as f64 / total as f64 - 0.00001 * (i.abs_diff(index) as f64);
        if similarity >= 0.4 {
            candidates.push((similarity, article));
        }
    }
    // The OCaml engine collected the candidates in reverse.
    candidates.reverse();
    ocaml_array_sort(&mut candidates, &|(a, _), (b, _)| {
        b.partial_cmp(a).unwrap_or(Ordering::Equal)
    });
    candidates.into_iter().take(5).map(|(_, a)| a).collect()
}

/// The articles tagged with each keyword, newest first.
fn articles_by_keyword(articles: &[Article]) -> BTreeMap<&str, Vec<&Article>> {
    let mut map: BTreeMap<&str, Vec<&Article>> = BTreeMap::new();
    // Oldest first, then a stable sort: ties keep that order.
    for article in articles.iter().rev() {
        for keyword in &article.keywords {
            map.entry(keyword.as_str()).or_default().push(article);
        }
    }
    for list in map.values_mut() {
        list.sort_by_key(|article| std::cmp::Reverse(article.created_at));
    }
    map
}

// ------------------------------------------------------------------- head

fn json_string(out: &mut String, text: &str) {
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

/// The structured data of a post, for search engines.
fn json_ld(options: &Options, article: &Article) -> String {
    let url = format!("{}{}", options.root_url, article.url);
    let author = r#"{"@type":"Person","givenName":"Roman","familyName":"Kashitsyn"}"#;
    let mut out = String::from("{");
    let field = |out: &mut String, name: &str, write: &dyn Fn(&mut String)| {
        if out.len() > 1 {
            out.push(',');
        }
        json_string(out, name);
        out.push(':');
        write(out);
    };
    let string = |value: String| move |out: &mut String| json_string(out, &value);
    field(&mut out, "@context", &string("https://schema.org".into()));
    field(&mut out, "@type", &string("BlogPosting".into()));
    field(&mut out, "headline", &string(plain_text(&article.title)));
    field(&mut out, "url", &string(url.clone()));
    field(&mut out, "mainEntityOfPage", &|out: &mut String| {
        out.push_str(r#"{"@type":"WebPage","@id":"#);
        json_string(out, &url);
        out.push('}');
    });
    field(
        &mut out,
        "datePublished",
        &string(article.created_at.to_string()),
    );
    field(
        &mut out,
        "dateModified",
        &string(article.modified_at.to_string()),
    );
    field(&mut out, "wordCount", &|out: &mut String| {
        out.push_str(&article.word_count.to_string())
    });
    field(
        &mut out,
        "license",
        &string("http://creativecommons.org/licenses/by/4.0/".into()),
    );
    field(&mut out, "author", &|out: &mut String| out.push_str(author));
    field(&mut out, "publisher", &|out: &mut String| {
        out.push_str(author)
    });
    if !article.subtitle.is_empty() {
        field(
            &mut out,
            "description",
            &string(plain_text(&article.subtitle)),
        );
    }
    if !article.keywords.is_empty() {
        field(&mut out, "keywords", &|out: &mut String| {
            out.push('[');
            for (i, keyword) in article.keywords.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                json_string(out, keyword);
            }
            out.push(']');
        });
    }
    out.push('}');
    out
}

const ANALYTICS: &str = r#"
<!-- Cloudflare Web Analytics -->
<script defer src='https://static.cloudflareinsights.com/beacon.min.js' data-cf-beacon='{"token": "c85a31fe0cfd47deb15201fabe2fd285"}'></script>
<!-- End Cloudflare Web Analytics -->
"#;

fn common_meta(h: &mut Html, options: &Options) {
    h.open("meta", &[("charset", "UTF-8")]);
    if options.analytics {
        h.raw(ANALYTICS);
    }
    h.open(
        "meta",
        &[
            ("content", "width=device-width, initial-scale=1"),
            ("name", "viewport"),
        ],
    );
    h.open(
        "meta",
        &[("name", "author"), ("content", "Roman Kashitsyn")],
    );
    h.open("meta", &[("name", "tdm-reservation"), ("content", "0")]);
}

fn asset_links(h: &mut Html) {
    for font in [
        "/fonts/LibertinusSans-Regular.woff2",
        "/fonts/LibertinusSans-Bold.woff2",
        "/fonts/LibertinusSerif-Regular.woff2",
        "/fonts/LibertinusSerif-Bold.woff2",
    ] {
        h.open(
            "link",
            &[
                ("rel", "preload"),
                ("href", font),
                ("as", "font"),
                ("type", "font/woff2"),
                ("crossorigin", ""),
            ],
        );
    }
    h.open(
        "link",
        &[("rel", "stylesheet"), ("href", "/css/mmapped.css")],
    );
    h.open("link", &[("rel", "icon"), ("href", "/images/favicon.svg")]);
    h.open(
        "link",
        &[
            ("rel", "mask-icon"),
            ("href", "/images/mask-icon.svg"),
            ("color", "#000000"),
        ],
    );
}

fn feed_link(h: &mut Html) {
    h.open(
        "link",
        &[
            ("rel", "alternate"),
            ("type", "application/atom+xml"),
            ("href", "/feed.xml"),
        ],
    );
}

fn post_head(h: &mut Html, options: &Options, article: &Article) {
    h.elem("head", &[], |h| {
        common_meta(h, options);
        h.open(
            "meta",
            &[
                ("name", "keywords"),
                ("content", &article.keywords.join(",")),
            ],
        );
        if !article.subtitle.is_empty() {
            let description = title_html(&article.subtitle);
            h.open(
                "meta",
                &[("name", "description"), ("content", &description)],
            );
        }
        h.elem("title", &[], |h| {
            h.raw(&title_html(&article.title));
        });
        asset_links(h);
        feed_link(h);
        let canonical = format!("{}{}", options.root_url, article.url);
        h.open("link", &[("rel", "canonical"), ("href", &canonical)]);
        h.elem("script", &[("type", "application/ld+json")], |h| {
            h.nl().raw(&json_ld(options, article)).nl();
        });
    });
}

/// The head of the index of notes and of the other lists.
fn list_head(h: &mut Html, options: &Options, title: &str) {
    h.elem("head", &[], |h| {
        common_meta(h, options);
        h.text_elem("title", &[], title);
        asset_links(h);
        feed_link(h);
    });
}

// ------------------------------------------------------------ page chrome

const SITE_HEADER: &str = "<header><nav><ul><li><a class=\"blog-title\" href=\"/index.html\">\
<img class=\"logo grayscale\" src=\"/images/logo.svg\" alt=\"logo: circled capital letter M\">\
mmap(blog)</a></li><li><a href=\"/posts.html\">Posts</a></li><li><a \
href=\"/notes/index.html\">Notes</a></li><li><a href=\"/feed.xml\">Feed</a></li></ul></nav>\
</header><hr>";

const SITE_FOOTER: &str = "\n<hr><footer role=\"contentinfo\"><span>©Roman Kashitsyn</span>\
&nbsp;<a rel=\"license\" href=\"http://creativecommons.org/licenses/by/4.0/\" title=\"This \
work is licensed under a Creative Commons Attribution 4.0 International License\"><img \
alt=\"Creative Commons License\" \
style=\"border-width:0;width:80px;height:15px;text-decoration:none;\" \
src=\"https://i.creativecommons.org/l/by/4.0/80x15.png\"></a><br>\n<a class=\"github-link\" \
href=\"https://github.com/roman-kashitsyn/mmapped.blog\">Source Code</a> · <a \
href=\"https://github.com/roman-kashitsyn/mmapped.blog/issues/new\">Report Issue</a></footer>";

fn date(h: &mut Html, date: Date) {
    let text = date.to_string();
    h.text_elem("time", &[("datetime", &text)], &text);
}

/// The dates of a post or a note. The modification date shows only if it
/// differs.
fn dates(h: &mut Html, created_at: Date, modified_at: Date) {
    h.elem(
        "span",
        &[("class", "attr-date"), ("title", "First published")],
        |h| {
            h.text_elem("span", &[("class", "icon")], "✑");
            date(h, created_at);
        },
    );
    if modified_at != created_at {
        h.elem(
            "span",
            &[("class", "attr-date"), ("title", "Last modified")],
            |h| {
                h.text_elem("span", &[("class", "icon")], "✂");
                date(h, modified_at);
            },
        );
    }
}

fn social_link(h: &mut Html, url: Option<&str>, icon: &str, title: &str, alt: &str, extra: &str) {
    let Some(url) = url else {
        return;
    };
    let class = if extra.is_empty() {
        "social-icon".to_string()
    } else {
        format!("social-icon {extra}")
    };
    h.elem(
        "a",
        &[
            ("class", "icon-link"),
            ("href", url),
            ("title", title),
            ("rel", "nofollow noopener noreferrer"),
            ("target", "_blank"),
        ],
        |h| {
            h.open("img", &[("class", &class), ("src", icon), ("alt", alt)]);
        },
    );
}

fn post_attributes(h: &mut Html, article: &Article) {
    h.elem("span", &[("class", "post-attrs")], |h| {
        dates(h, article.created_at, article.modified_at);
        if !article.keywords.is_empty() {
            h.elem("span", &[("class", "post-keywords")], |h| {
                for keyword in &article.keywords {
                    let href = format!("/notes/{keyword}.html");
                    h.text_elem("a", &[("class", "keyword-link"), ("href", &href)], keyword);
                }
            });
        }
        h.elem("span", &[("class", "post-icons")], |h| {
            social_link(
                h,
                article.hackernews.as_deref(),
                "/images/y18.svg",
                "Discuss on Hacker News",
                "Hacker News",
                "",
            );
            social_link(
                h,
                article.reddit.as_deref(),
                "/images/Reddit-Icon.svg",
                "Discuss on Reddit",
                "Reddit",
                "",
            );
            social_link(
                h,
                article.lobsters.as_deref(),
                "/images/Lobsters-Icon.svg",
                "Discuss on Lobste.rs",
                "Lobsters",
                "lobsters-icon",
            );
        });
    });
}

/// A list of articles with their dates, under a heading. Nothing if there
/// are no articles.
fn compact_list(h: &mut Html, heading: &str, articles: &[&Article]) {
    if articles.is_empty() {
        return;
    }
    h.text_elem("h2", &[], heading);
    h.elem("ul", &[("class", "article-list")], |h| {
        for article in articles {
            let subtitle = plain_text(&article.subtitle);
            let mut attrs = vec![("class", "compact-title"), ("href", article.url.as_str())];
            if !subtitle.is_empty() {
                attrs.push(("title", &subtitle));
            }
            h.elem("li", &[], |h| {
                h.elem("a", &attrs, |h| {
                    h.raw(&title_html(&article.title));
                });
                h.elem("span", &[("class", "compact-date")], |h| {
                    date(h, article.created_at)
                });
            });
        }
    });
}

fn page(h: &mut Html, head: impl FnOnce(&mut Html), body: impl FnOnce(&mut Html)) {
    h.raw("<!DOCTYPE html>").nl();
    h.elem("html", &[("lang", "en")], |h| {
        head(h);
        h.elem("body", &[], body);
    });
    h.nl();
}

// ------------------------------------------------------------------ pages

/// The page of the article at `index` in [`Site::articles`].
pub fn post_page(site: &Site, index: usize, options: &Options) -> String {
    let article = &site.articles[index];
    let toc = extract_toc(&article.body);
    let similar = similar_articles(&site.articles, index);
    let refs = document_refs(site, &article.body);
    let ctx = Ctx {
        refs: &refs,
        bib: &site.bib,
    };
    let mut h = Html::new();
    page(
        &mut h,
        |h| post_head(h, options, article),
        |h| {
            h.raw(SITE_HEADER);
            h.elem("article", &[], |h| {
                h.elem("h1", &[("class", "article-title")], |h| {
                    h.elem("a", &[("href", &article.url)], |h| {
                        h.raw(&title_html(&article.title));
                    });
                });
                post_attributes(h, article);
                h.nl();
                render_toc(h, &toc);
                h.nl();
                render::render_blocks(h, ctx, &article.body);
                h.nl();
            });
            if !similar.is_empty() {
                h.elem("section", &[], |h| {
                    compact_list(h, "Similar articles", &similar)
                });
            }
            h.nl();
            h.raw(SITE_FOOTER);
        },
    );
    h.finish()
}

/// The page of the note at `index` in [`Site::notes`]. A note whose slug is
/// a keyword lists the articles tagged with it.
pub fn note_page(site: &Site, index: usize, options: &Options) -> String {
    let note = &site.notes[index];
    let refs = document_refs(site, &note.body);
    let ctx = Ctx {
        refs: &refs,
        bib: &site.bib,
    };
    let by_keyword = articles_by_keyword(&site.articles);
    let tagged = by_keyword
        .get(note.slug.as_str())
        .cloned()
        .unwrap_or_default();
    let mut h = Html::new();
    page(
        &mut h,
        |h| {
            h.elem("head", &[], |h| {
                common_meta(h, options);
                h.elem("title", &[], |h| {
                    h.raw(&title_html(&note.title));
                });
                asset_links(h);
            });
        },
        |h| {
            h.raw(SITE_HEADER);
            h.elem("article", &[], |h| {
                h.elem("h1", &[("class", "note-title")], |h| {
                    h.elem("a", &[("href", &note.url)], |h| {
                        h.raw(&title_html(&note.title));
                    });
                });
                h.elem("span", &[("class", "post-attrs")], |h| {
                    dates(h, note.created_at, note.modified_at)
                });
                h.nl();
                render::render_blocks(h, ctx, &note.body);
                h.nl();
            });
            h.elem("section", &[], |h| {
                compact_list(h, "Tagged articles", &tagged)
            });
            h.raw(SITE_FOOTER);
        },
    );
    h.finish()
}

/// The front page: the text of `index.rftex`, then the five newest featured
/// articles and the five newest articles.
pub fn index_page(site: &Site, options: &Options) -> String {
    let refs = global_refs(site);
    let ctx = Ctx {
        refs: &refs,
        bib: &site.bib,
    };
    let featured: Vec<&Article> = site
        .articles
        .iter()
        .filter(|article| article.featured)
        .take(5)
        .collect();
    let latest: Vec<&Article> = site.articles.iter().take(5).collect();
    let mut h = Html::new();
    page(
        &mut h,
        |h| list_head(h, options, "mmap(blog)"),
        |h| {
            h.raw(SITE_HEADER);
            h.elem("article", &[], |h| {
                render::render_blocks(h, ctx, &site.index.body);
                h.elem("section", &[], |h| compact_list(h, "Featured", &featured));
                h.elem("section", &[], |h| compact_list(h, "Latest", &latest));
            });
            h.raw(SITE_FOOTER);
        },
    );
    h.finish()
}

fn post_entry(h: &mut Html, article: &Article) {
    let (item_class, title_class) = if article.featured {
        (
            Some(("class", "featured")),
            "article-title left-gutter-anchor featured-marker",
        )
    } else {
        (None, "article-title")
    };
    h.elem_opt("li", &[item_class], |h| {
        h.elem("h2", &[("class", title_class)], |h| {
            h.elem("a", &[("href", &article.url)], |h| {
                h.elem("span", &[], |h| {
                    h.raw(&title_html(&article.title));
                });
            });
        });
        h.elem("div", &[("class", "article-subtitle")], |h| {
            h.raw(&title_html(&article.subtitle));
        });
        post_attributes(h, article);
    });
}

/// The list of all articles, newest first.
pub fn post_list_page(site: &Site, options: &Options) -> String {
    let mut h = Html::new();
    h.raw("<!DOCTYPE html>").nl();
    // Quirk: the final newline is inside the `html` element.
    h.elem("html", &[("lang", "en")], |h| {
        list_head(h, options, "All Posts");
        h.elem("body", &[], |h| {
            h.raw(SITE_HEADER);
            h.elem("section", &[("class", "post-list")], |h| {
                if !site.articles.is_empty() {
                    h.elem("ul", &[("class", "posts")], |h| {
                        for article in &site.articles {
                            post_entry(h, article);
                        }
                    });
                }
            });
            h.raw(SITE_FOOTER);
        });
        h.nl();
    });
    h.finish()
}

/// The index of notes, ordered by title.
pub fn note_list_page(site: &Site, options: &Options) -> String {
    let mut notes: Vec<&Note> = site.notes.iter().collect();
    notes.sort_by_key(|note| plain_text(&note.title));
    let mut h = Html::new();
    h.raw("<!DOCTYPE html>").nl();
    // Quirk: the final newline is inside the `html` element.
    h.elem("html", &[("lang", "en")], |h| {
        list_head(h, options, "Notes");
        h.elem("body", &[], |h| {
            h.raw(SITE_HEADER);
            h.elem("section", &[("class", "note-index")], |h| {
                h.text_elem("h1", &[("class", "note-title")], "Notes");
                if !notes.is_empty() {
                    h.elem("ul", &[("class", "note-list")], |h| {
                        for note in &notes {
                            h.elem("li", &[], |h| {
                                h.elem(
                                    "a",
                                    &[("class", "note-list-title"), ("href", &note.url)],
                                    |h| {
                                        h.raw(&title_html(&note.title));
                                    },
                                );
                            });
                        }
                    });
                }
            });
            h.raw(SITE_FOOTER);
        });
        h.nl();
    });
    h.finish()
}

#[cfg(test)]
mod tests;
