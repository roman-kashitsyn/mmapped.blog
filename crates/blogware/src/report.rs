//! Showing diagnostics in a terminal, the way rustc does.

use annotate_snippets::{AnnotationKind, Level, Renderer, Snippet};

use crate::site::{Failure, FileErrors};

fn plural(count: usize, noun: &str) -> String {
    match count {
        1 => format!("1 {noun}"),
        _ => format!("{count} {noun}s"),
    }
}

fn render_file(file: &FileErrors, renderer: &Renderer, out: &mut String) {
    for diagnostic in &file.diagnostics {
        let span = |range: rftex_syntax::TextRange| range.start as usize..range.end as usize;
        let label = (!diagnostic.label.is_empty()).then_some(diagnostic.label.as_str());
        let mut snippet = Snippet::source(file.source.as_str())
            .path(file.path.as_str())
            .annotation(
                AnnotationKind::Primary
                    .span(span(diagnostic.range))
                    .label(label),
            );
        for related in &diagnostic.related {
            snippet = snippet.annotation(
                AnnotationKind::Context
                    .span(span(related.range))
                    .label(related.message.as_str()),
            );
        }
        let mut group = Level::ERROR
            .primary_title(diagnostic.message.as_str())
            .element(snippet);
        if let Some(help) = &diagnostic.help {
            group = group.element(Level::HELP.message(help.as_str()));
        }
        out.push_str(&renderer.render(&[group]));
        out.push_str("\n\n");
    }
}

/// Renders everything that is wrong with a site, ending with a summary line.
/// With `color` the text carries ANSI escape codes.
pub fn render(failure: &Failure, color: bool) -> String {
    let renderer = if color {
        Renderer::styled()
    } else {
        Renderer::plain()
    };
    let mut out = String::new();
    for error in &failure.errors {
        let group =
            annotate_snippets::Group::with_title(Level::ERROR.primary_title(error.as_str()));
        out.push_str(&renderer.render(&[group]));
        out.push_str("\n\n");
    }
    for file in &failure.files {
        render_file(file, &renderer, &mut out);
    }
    let errors = plural(failure.error_count(), "error");
    let summary = match failure.files.len() {
        0 => errors,
        files => format!("{errors} in {}", plural(files, "file")),
    };
    out.push_str(&summary);
    out.push('\n');
    out
}
