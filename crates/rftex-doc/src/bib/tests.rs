use super::*;

/// Parses a bibliography that must have no errors.
fn entries(src: &str) -> Vec<Entry> {
    let bibliography = parse(src);
    assert_eq!(bibliography.diagnostics, [], "{src}");
    bibliography.entries
}

/// The messages of the errors in a bibliography.
fn errors(src: &str) -> Vec<String> {
    parse(src)
        .diagnostics
        .into_iter()
        .map(|diagnostic| diagnostic.message)
        .collect()
}

fn some(text: &str) -> Option<String> {
    Some(text.to_string())
}

fn misc(key: &str, title: &str) -> Entry {
    Entry::Misc(Misc {
        key: key.to_string(),
        title: title.to_string(),
        author: None,
        year: None,
        url: None,
    })
}

#[test]
fn book_with_all_fields() {
    let src = r"
@book{knuth-taocp,
  author = {Donald Knuth},
  title = {The Art of Computer Programming},
  year = {1968},
  url = {https://www-cs-faculty.stanford.edu/~knuth/taocp.html},
  isbn = {978-0201896831},
}
";
    assert_eq!(
        entries(src),
        [Entry::Book(Book {
            key: "knuth-taocp".to_string(),
            author: "Donald Knuth".to_string(),
            title: "The Art of Computer Programming".to_string(),
            year: some("1968"),
            url: some("https://www-cs-faculty.stanford.edu/~knuth/taocp.html"),
            isbn: some("978-0201896831"),
        })]
    );
}

#[test]
fn book_with_bare_numeric_year() {
    let src = r"
@book{foo,
  author = {Bar},
  title = {Baz},
  year = 2009,
}
";
    assert_eq!(
        entries(src),
        [Entry::Book(Book {
            key: "foo".to_string(),
            author: "Bar".to_string(),
            title: "Baz".to_string(),
            year: some("2009"),
            url: None,
            isbn: None,
        })]
    );
}

#[test]
fn article() {
    let src = r"
@article{dijkstra-goto,
  author = {Edsger Dijkstra},
  title = {Go To Statement Considered Harmful},
  journal = {Communications of the ACM},
  year = {1968},
}
";
    assert_eq!(
        entries(src),
        [Entry::Article(Article {
            key: "dijkstra-goto".to_string(),
            author: "Edsger Dijkstra".to_string(),
            title: "Go To Statement Considered Harmful".to_string(),
            journal: some("Communications of the ACM"),
            year: some("1968"),
            url: None,
        })]
    );
}

#[test]
fn blog() {
    let src = r"
@blog{danluu-p95,
  author = {Dan Luu},
  title = {95%-ile isn't that good},
  url = {https://danluu.com/p95-skill/},
}
";
    assert_eq!(
        entries(src),
        [Entry::Blog(Blog {
            key: "danluu-p95".to_string(),
            title: "95%-ile isn't that good".to_string(),
            author: some("Dan Luu"),
            url: "https://danluu.com/p95-skill/".to_string(),
        })]
    );
}

#[test]
fn talk() {
    let src = r"
@talk{parent-cpp-seasoning,
  author = {Sean Parent},
  title = {C++ Seasoning},
  year = {2013},
  url = {https://youtu.be/W2tWOdzgXHA},
}
";
    assert_eq!(
        entries(src),
        [Entry::Talk(Talk {
            key: "parent-cpp-seasoning".to_string(),
            author: "Sean Parent".to_string(),
            title: "C++ Seasoning".to_string(),
            year: some("2013"),
            url: some("https://youtu.be/W2tWOdzgXHA"),
        })]
    );
}

#[test]
fn podcast() {
    let src = r"
@podcast{wizardology,
  title = {Wizardology podcast},
  url = {https://example.com/wiz},
}
";
    assert_eq!(
        entries(src),
        [Entry::Podcast(Podcast {
            key: "wizardology".to_string(),
            title: "Wizardology podcast".to_string(),
            author: None,
            url: "https://example.com/wiz".to_string(),
        })]
    );
}

#[test]
fn phdthesis() {
    let src = r"
@phdthesis{dolstra-nix,
  author = {Eelco Dolstra},
  title = {The Purely Functional Software Deployment Model},
  school = {Utrecht University},
  year = {2006},
  url = {https://edolstra.github.io/pubs/phd-thesis.pdf},
}
";
    assert_eq!(
        entries(src),
        [Entry::Phdthesis(Phdthesis {
            key: "dolstra-nix".to_string(),
            author: "Eelco Dolstra".to_string(),
            title: "The Purely Functional Software Deployment Model".to_string(),
            school: some("Utrecht University"),
            year: some("2006"),
            url: some("https://edolstra.github.io/pubs/phd-thesis.pdf"),
        })]
    );
}

#[test]
fn misc_entry() {
    let src = r"
@misc{feynman-trinity,
  author = {Richard Feynman},
  title = {My Observations During the Explosion at Trinity on July 16, 1945},
}
";
    assert_eq!(
        entries(src),
        [Entry::Misc(Misc {
            key: "feynman-trinity".to_string(),
            title: "My Observations During the Explosion at Trinity on July 16, 1945".to_string(),
            author: some("Richard Feynman"),
            year: None,
            url: None,
        })]
    );
}

#[test]
fn no_trailing_comma() {
    let src = r"
@article{bar,
  author = {Baz},
  title = {Quux}
}
";
    assert_eq!(
        entries(src),
        [Entry::Article(Article {
            key: "bar".to_string(),
            author: "Baz".to_string(),
            title: "Quux".to_string(),
            journal: None,
            year: None,
            url: None,
        })]
    );
}

#[test]
fn nested_braces_in_value() {
    assert_eq!(
        entries("@misc{x, title = {A {Nested} Title}}"),
        [misc("x", "A {Nested} Title")]
    );
}

#[test]
fn multiple_entries() {
    let src = "\n@misc{a, title = {First}}\n@misc{b, title = {Second}}\n";
    assert_eq!(entries(src), [misc("a", "First"), misc("b", "Second")]);
}

#[test]
fn comment_entries_are_skipped() {
    let src = r"
@comment{this is ignored}
@misc{real, title = {Real}}
@preamble{also {ignored}}
@String{acm = {ACM}}
";
    assert_eq!(entries(src), [misc("real", "Real")]);
}

#[test]
fn junk_between_entries() {
    let src = r"
% This is a BibTeX comment line
Some random text here

@misc{x, title = {Hello}}
";
    assert_eq!(entries(src), [misc("x", "Hello")]);
}

#[test]
fn empty_file() {
    assert_eq!(entries(""), []);
}

#[test]
fn key_with_dots_and_colons() {
    assert_eq!(
        entries("@misc{rfc:2119.v2, title = {RFC}}"),
        [misc("rfc:2119.v2", "RFC")]
    );
}

#[test]
fn kinds_and_field_names_ignore_case() {
    assert_eq!(
        entries("@MISC{x, Title = {T}, title = {ignored}}"),
        [misc("x", "T")]
    );
}

#[test]
fn accessors() {
    let src = r"
@misc{my-key, title = {T}}
@blog{b, title = {B}, url = {https://example.com}}
@book{k, title = {K}, author = {A}}
";
    let entries = entries(src);
    let view = |entry: &Entry| {
        (
            entry.key().to_string(),
            entry.title().to_string(),
            entry.author().map(str::to_string),
            entry.url().map(str::to_string),
        )
    };
    assert_eq!(
        entries.iter().map(view).collect::<Vec<_>>(),
        [
            ("my-key".to_string(), "T".to_string(), None, None),
            (
                "b".to_string(),
                "B".to_string(),
                None,
                some("https://example.com")
            ),
            ("k".to_string(), "K".to_string(), some("A"), None),
        ]
    );
}

#[test]
fn unterminated_value() {
    let bibliography = parse("@misc{x, title = {unclosed");
    assert_eq!(bibliography.entries, []);
    let [diagnostic] = bibliography.diagnostics.as_slice() else {
        panic!("{:?}", bibliography.diagnostics);
    };
    assert_eq!(diagnostic.message, "missing closing `}`");
    // The error points at the brace that opens the value.
    assert_eq!(diagnostic.range, TextRange::new(17, 18));
}

#[test]
fn missing_closing_brace() {
    assert_eq!(errors("@misc{x, title = {ok}"), ["expected `}`"]);
}

#[test]
fn unknown_entry_type() {
    let bibliography = parse("@thesis{x, title = {Foo}}");
    assert_eq!(bibliography.entries, []);
    let [diagnostic] = bibliography.diagnostics.as_slice() else {
        panic!("{:?}", bibliography.diagnostics);
    };
    assert_eq!(diagnostic.message, "unknown entry type `@thesis`");
    assert_eq!(diagnostic.range, TextRange::new(0, 7));
}

#[test]
fn missing_required_fields() {
    assert_eq!(
        errors("@book{my-key, title = {Foo}}"),
        ["@book{my-key}: missing required field `author`"]
    );
    assert_eq!(
        errors("@blog{x, title = {Foo}}"),
        ["@blog{x}: missing required field `url`"]
    );
    // Every missing field is reported.
    assert_eq!(
        errors("@talk{x, year = 2013}"),
        [
            "@talk{x}: missing required field `author`",
            "@talk{x}: missing required field `title`"
        ]
    );
}

#[test]
fn malformed_entries() {
    assert_eq!(errors("@"), ["expected an entry type after `@`"]);
    assert_eq!(errors("@misc x"), ["expected `{`"]);
    assert_eq!(errors("@misc{, title = {T}}"), ["expected an entry key"]);
    assert_eq!(errors("@misc{x}"), ["expected `,`"]);
    assert_eq!(errors("@misc{x, title {T}}"), ["expected `=`"]);
    assert_eq!(
        errors("@misc{x, title = \"T\"}"),
        ["expected a field value"]
    );
    assert_eq!(errors("@comment{never closed"), ["missing closing `}`"]);
}

#[test]
fn an_error_costs_one_entry() {
    let src = r"
@misc{a, title = {First}}
@misc{b, title = oops}
@thesis{c, title = {Third}}
@misc{d, title = {Fourth}}
";
    let bibliography = parse(src);
    assert_eq!(
        bibliography.entries,
        [misc("a", "First"), misc("d", "Fourth")]
    );
    let messages: Vec<&str> = bibliography
        .diagnostics
        .iter()
        .map(|diagnostic| diagnostic.message.as_str())
        .collect();
    assert_eq!(
        messages,
        ["expected a field value", "unknown entry type `@thesis`"]
    );
}

#[test]
fn a_broken_entry_does_not_hide_the_next_one() {
    // The parser stops at the `@` of the next entry.
    assert_eq!(
        errors("@misc{a, title = {A}\n@book{b, title = {B}}\n"),
        ["expected `}`", "@book{b}: missing required field `author`"]
    );
    // The unclosed value runs on to the end of the file.
    assert_eq!(
        errors("@misc{a, title = {A\n@book{b, title = {B}}\n"),
        [
            "missing closing `}`",
            "@book{b}: missing required field `author`"
        ]
    );
}

#[test]
fn errors_point_inside_the_source() {
    for src in ["@misc{x, title = é", "@misc{é", "@é", "@misc{x, title = {é"] {
        let bibliography = parse(src);
        assert_eq!(bibliography.diagnostics.len(), 1, "{src}");
        let range = bibliography.diagnostics[0].range;
        assert!(src.is_char_boundary(range.start as usize), "{src}");
        assert!(src.is_char_boundary(range.end as usize), "{src}");
    }
}

#[test]
fn the_library_of_the_blog_parses() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../library.bib");
    let src = std::fs::read_to_string(path).unwrap();
    let bibliography = parse(&src);
    assert_eq!(bibliography.diagnostics, []);
    assert!(bibliography.entries.len() > 10);
}
