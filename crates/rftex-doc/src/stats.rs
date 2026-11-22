//! Word count.
//!
//! Only prose counts: code, math and images do not. A word is a run of ASCII
//! letters and digits and of non-ASCII bytes. An apostrophe or a hyphen
//! inside a word does not end it, so `isn't` and `memory-mapped` are one
//! word each. A word may span inlines: the `s` in `\textsc{llm}s` belongs to
//! the word before it.

use crate::document::{Block, Inline, Table, TableRow};

fn is_word_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte >= 0x80
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Idle,
    InWord,
    /// After an apostrophe or a hyphen that follows a word.
    AfterConnector,
}

struct Counter {
    words: usize,
    /// Whether the text seen so far ends inside a word.
    in_word: bool,
}

impl Counter {
    fn text(&mut self, text: &str) {
        let mut mode = if self.in_word {
            Mode::InWord
        } else {
            Mode::Idle
        };
        for byte in text.bytes() {
            mode = match (mode, is_word_byte(byte)) {
                (Mode::Idle, true) => {
                    self.words += 1;
                    Mode::InWord
                }
                (Mode::InWord | Mode::AfterConnector, true) => Mode::InWord,
                (Mode::InWord, false) if byte == b'\'' || byte == b'-' => Mode::AfterConnector,
                (_, false) => Mode::Idle,
            };
        }
        self.in_word = mode == Mode::InWord;
    }

    fn inlines(&mut self, inlines: &[Inline]) {
        for inline in inlines {
            self.inline(inline);
        }
    }

    fn inline(&mut self, inline: &Inline) {
        match inline {
            Inline::Str(text) => self.text(text),
            Inline::Strong(body)
            | Inline::Emph(body)
            | Inline::Italic(body)
            | Inline::Underline(body)
            | Inline::SmallCaps(body)
            | Inline::Strikethrough(body)
            | Inline::Kbd(body)
            | Inline::Sub(body)
            | Inline::Sup(body)
            | Inline::Quotation(body)
            | Inline::Fun(body)
            | Inline::MathSpan(body)
            | Inline::Normal(body)
            | Inline::Cite(body)
            | Inline::Highlighted(_, body)
            | Inline::Link { body, .. }
            | Inline::MarginNote { body, .. }
            | Inline::SideNote { body, .. }
            | Inline::Ref { body, .. } => self.inlines(body),
            Inline::Code { .. }
            | Inline::Math(..)
            | Inline::HorizontalRule
            | Inline::CircledRef(_)
            | Inline::LineBreak
            | Inline::NumericSpace
            | Inline::Nameref(_)
            | Inline::Bibref { .. }
            | Inline::Image { .. } => self.in_word = false,
            // An anchor is invisible: a word continues through it.
            Inline::Anchor(_) => {}
        }
    }
}

/// Counts the words of a run of inlines. A word that is still open at the
/// end is counted; it does not continue into the next run.
fn count_inlines(inlines: &[Inline]) -> usize {
    let mut counter = Counter {
        words: 0,
        in_word: false,
    };
    counter.inlines(inlines);
    counter.words
}

fn count_row(row: &TableRow) -> usize {
    row.cells
        .iter()
        .map(|cell| count_inlines(&cell.content))
        .sum()
}

fn count_table(table: &Table) -> usize {
    table.header.iter().map(count_row).sum::<usize>()
        + table.rows.iter().map(count_row).sum::<usize>()
}

fn count_block(block: &Block) -> usize {
    match block {
        Block::Para(inlines)
        | Block::Plain(inlines)
        | Block::Figcaption(inlines)
        | Block::Advice { body: inlines, .. } => count_inlines(inlines),
        Block::Section { heading, body } => {
            let title = heading
                .as_ref()
                .map_or(0, |heading| count_inlines(&heading.title));
            title + word_count(body)
        }
        Block::Subsection { heading, body } => count_inlines(&heading.title) + word_count(body),
        Block::CodeBlock { .. }
        | Block::VerbatimBlock { .. }
        | Block::Image { .. }
        | Block::HRule => 0,
        Block::BulletList(_, items) | Block::OrderedList(items) => {
            items.iter().map(|item| word_count(item)).sum()
        }
        Block::DescriptionList(items) => items
            .iter()
            .map(|(term, description)| count_inlines(term) + word_count(description))
            .sum(),
        Block::Blockquote { body, attribution } | Block::Epigraph { body, attribution } => {
            word_count(body) + count_inlines(attribution)
        }
        Block::Table(table) => count_table(table),
        Block::Figure { body, .. } | Block::Abstract(body) | Block::Center(body) => {
            word_count(body)
        }
        Block::Details { summary, body } => count_inlines(summary) + word_count(body),
    }
}

/// The number of words in the prose of `blocks`.
pub fn word_count(blocks: &[Block]) -> usize {
    blocks.iter().map(count_block).sum()
}

#[cfg(test)]
mod tests;
