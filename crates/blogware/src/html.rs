//! A minimal HTML writer.
//!
//! [`Html`] appends to a string. Text is escaped, attributes are written in
//! the order given, and nothing is reformatted: the output is exactly the
//! sequence of calls.

/// Appends `text` with `<`, `>`, `&` and `"` escaped. The apostrophe stays,
/// as attribute values are always double-quoted.
pub fn escape_into(out: &mut String, text: &str) {
    let mut rest = text;
    while let Some(index) = rest.find(['<', '>', '&', '"']) {
        out.push_str(&rest[..index]);
        out.push_str(match rest.as_bytes()[index] {
            b'<' => "&lt;",
            b'>' => "&gt;",
            b'&' => "&amp;",
            _ => "&quot;",
        });
        rest = &rest[index + 1..];
    }
    out.push_str(rest);
}

/// `text` with the HTML special characters escaped.
pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    escape_into(&mut out, text);
    out
}

/// An attribute: a name and its unescaped value.
pub type Attr<'a> = (&'a str, &'a str);

/// The class attribute, or nothing if there are no classes.
pub fn class_if_any(classes: &str) -> Option<Attr<'_>> {
    (!classes.is_empty()).then_some(("class", classes))
}

/// An HTML document or fragment under construction.
#[derive(Clone, Debug, Default)]
pub struct Html {
    out: String,
}

impl Html {
    pub fn new() -> Html {
        Html::default()
    }

    pub fn finish(self) -> String {
        self.out
    }

    pub fn as_str(&self) -> &str {
        &self.out
    }

    /// Escaped text.
    pub fn text(&mut self, text: &str) -> &mut Html {
        escape_into(&mut self.out, text);
        self
    }

    /// Markup, written as is.
    pub fn raw(&mut self, markup: &str) -> &mut Html {
        self.out.push_str(markup);
        self
    }

    pub fn nl(&mut self) -> &mut Html {
        self.raw("\n")
    }

    /// An opening tag. Also the whole of a void element such as `<br>`.
    pub fn open(&mut self, tag: &str, attrs: &[Attr]) -> &mut Html {
        self.open_with(tag, attrs.iter().copied())
    }

    /// An opening tag whose attributes may be left out.
    pub fn open_opt(&mut self, tag: &str, attrs: &[Option<Attr>]) -> &mut Html {
        self.open_with(tag, attrs.iter().flatten().copied())
    }

    fn open_with<'a>(&mut self, tag: &str, attrs: impl Iterator<Item = Attr<'a>>) -> &mut Html {
        self.out.push('<');
        self.out.push_str(tag);
        for (name, value) in attrs {
            self.out.push(' ');
            self.out.push_str(name);
            self.out.push_str("=\"");
            escape_into(&mut self.out, value);
            self.out.push('"');
        }
        self.out.push('>');
        self
    }

    pub fn close(&mut self, tag: &str) -> &mut Html {
        self.out.push_str("</");
        self.out.push_str(tag);
        self.out.push('>');
        self
    }

    /// An element whose content `body` writes.
    pub fn elem(&mut self, tag: &str, attrs: &[Attr], body: impl FnOnce(&mut Html)) -> &mut Html {
        self.open(tag, attrs);
        body(self);
        self.close(tag)
    }

    /// An element with attributes that may be left out.
    pub fn elem_opt(
        &mut self,
        tag: &str,
        attrs: &[Option<Attr>],
        body: impl FnOnce(&mut Html),
    ) -> &mut Html {
        self.open_opt(tag, attrs);
        body(self);
        self.close(tag)
    }

    /// An element holding escaped text.
    pub fn text_elem(&mut self, tag: &str, attrs: &[Attr], text: &str) -> &mut Html {
        self.elem(tag, attrs, |h| {
            h.text(text);
        })
    }
}

#[cfg(test)]
mod tests;
