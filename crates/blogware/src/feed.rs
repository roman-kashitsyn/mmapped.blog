//! The Atom feed of the articles.

use rftex_doc::document::{plain_text, Article};

/// Appends `text` with the five XML special characters escaped.
fn escape_into(out: &mut String, text: &str) {
    for c in text.chars() {
        match c {
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            c => out.push(c),
        }
    }
}

/// An element holding escaped text, on a line of its own.
fn text_elem(out: &mut String, tag: &str, text: &str) {
    out.push('<');
    out.push_str(tag);
    out.push('>');
    escape_into(out, text);
    out.push_str("</");
    out.push_str(tag);
    out.push_str(">\n");
}

/// An empty element, on a line of its own.
fn leaf(out: &mut String, tag: &str, attrs: &[(&str, &str)]) {
    out.push('<');
    out.push_str(tag);
    for (name, value) in attrs {
        out.push(' ');
        out.push_str(name);
        out.push_str("=\"");
        escape_into(out, value);
        out.push('"');
    }
    out.push_str("/>\n");
}

fn author(out: &mut String) {
    out.push_str("<author>");
    text_elem(out, "name", "Roman Kashitsyn");
    out.push_str("</author>\n");
}

fn entry(out: &mut String, root_url: &str, article: &Article) {
    let url = format!("{root_url}{}", article.url);
    out.push_str("<entry>");
    text_elem(out, "id", &url);
    text_elem(out, "title", &plain_text(&article.title));
    text_elem(out, "summary", &plain_text(&article.subtitle));
    text_elem(out, "published", &article.created_at.to_rfc3339_midnight());
    text_elem(out, "updated", &article.modified_at.to_rfc3339_midnight());
    leaf(out, "link", &[("rel", "alternate"), ("href", &url)]);
    author(out);
    for keyword in &article.keywords {
        leaf(out, "category", &[("term", keyword)]);
    }
    out.push_str("</entry>\n");
}

/// The feed of `articles`, in their order. `root_url` has no trailing slash.
/// The feed is as fresh as the most recently modified article; a feed
/// without articles has no date.
pub fn atom(root_url: &str, articles: &[Article]) -> String {
    let mut out = String::from("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    out.push_str("<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"en\">");
    text_elem(&mut out, "title", "MMapped blog");
    text_elem(&mut out, "id", &format!("{root_url}/"));
    if let Some(updated) = articles.iter().map(|article| article.modified_at).max() {
        text_elem(&mut out, "updated", &updated.to_rfc3339_midnight());
    }
    leaf(
        &mut out,
        "link",
        &[("rel", "self"), ("href", &format!("{root_url}/feed.xml"))],
    );
    author(&mut out);
    for article in articles {
        entry(&mut out, root_url, article);
    }
    out.push_str("</feed>\n");
    out
}

#[cfg(test)]
mod tests;
