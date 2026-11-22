use super::*;

fn render(build: impl FnOnce(&mut Html)) -> String {
    let mut h = Html::new();
    build(&mut h);
    h.finish()
}

#[test]
fn text_is_escaped() {
    assert_eq!(escape("a<b"), "a&lt;b");
    assert_eq!(escape("<>&\""), "&lt;&gt;&amp;&quot;");
    assert_eq!(escape("it's"), "it's");
    assert_eq!(escape("naïve & café"), "naïve &amp; café");
    assert_eq!(escape(""), "");
}

#[test]
fn raw_passes_through() {
    assert_eq!(
        render(|h| {
            h.raw("a<b");
        }),
        "a<b"
    );
}

#[test]
fn elements_and_attributes() {
    assert_eq!(
        render(|h| {
            h.elem("div", &[], |_| {});
        }),
        "<div></div>"
    );
    assert_eq!(
        render(|h| {
            h.text_elem("div", &[("class", "foo")], "hi");
        }),
        "<div class=\"foo\">hi</div>"
    );
    assert_eq!(
        render(|h| {
            h.text_elem("a", &[("href", "u"), ("class", "x")], "link");
        }),
        "<a href=\"u\" class=\"x\">link</a>"
    );
    assert_eq!(
        render(|h| {
            h.text_elem("a", &[("href", "a&b")], "x");
        }),
        "<a href=\"a&amp;b\">x</a>"
    );
    assert_eq!(
        render(|h| {
            h.open("br", &[]);
        }),
        "<br>"
    );
    assert_eq!(
        render(|h| {
            h.open("img", &[("src", "p.png"), ("alt", "x")]);
        }),
        "<img src=\"p.png\" alt=\"x\">"
    );
    assert_eq!(
        render(|h| {
            h.elem("ul", &[], |h| {
                h.text_elem("li", &[], "a").text_elem("li", &[], "b");
            });
        }),
        "<ul><li>a</li><li>b</li></ul>"
    );
}

#[test]
fn optional_attributes_are_left_out() {
    assert_eq!(
        render(|h| {
            h.open_opt("img", &[class_if_any(""), Some(("src", "p.png"))]);
        }),
        "<img src=\"p.png\">"
    );
    assert_eq!(
        render(|h| {
            h.open_opt("img", &[class_if_any("wide"), Some(("src", "p.png"))]);
        }),
        "<img class=\"wide\" src=\"p.png\">"
    );
}
