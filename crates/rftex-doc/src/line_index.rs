//! Translation of byte offsets into lines and columns.

use rftex_syntax::TextRange;

/// A position as people count it: both numbers start at one, and the column
/// counts characters, not bytes.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub struct LineCol {
    pub line: u32,
    pub column: u32,
}

/// The offsets at which the lines of one source start.
#[derive(Clone, Debug)]
pub struct LineIndex {
    /// The offset of the first byte of every line. Never empty.
    starts: Vec<u32>,
    len: u32,
}

impl LineIndex {
    pub fn new(src: &str) -> LineIndex {
        let starts = std::iter::once(0)
            .chain(src.match_indices('\n').map(|(offset, _)| offset as u32 + 1))
            .collect();
        LineIndex {
            starts,
            len: src.len() as u32,
        }
    }

    /// The number of lines. A source that ends with a newline has an empty
    /// last line.
    pub fn line_count(&self) -> u32 {
        self.starts.len() as u32
    }

    /// The position of `offset` in `src`, which must be the indexed source.
    /// An offset past the end counts as the end; an offset inside a character
    /// counts as the start of that character.
    pub fn line_col(&self, src: &str, offset: u32) -> LineCol {
        let mut offset = offset.min(self.len) as usize;
        while !src.is_char_boundary(offset) {
            offset -= 1;
        }
        let line = self
            .starts
            .partition_point(|&start| start as usize <= offset)
            - 1;
        let start = self.starts[line] as usize;
        let chars = src[start..offset].chars().count();
        LineCol {
            line: line as u32 + 1,
            column: chars as u32 + 1,
        }
    }

    /// The range of a line given by its one-based number, without the
    /// newline that ends it. `None` if there is no such line.
    pub fn line_range(&self, line: u32) -> Option<TextRange> {
        let index = (line as usize).checked_sub(1)?;
        let start = *self.starts.get(index)?;
        let end = match self.starts.get(index + 1) {
            Some(&next) => next - 1,
            None => self.len,
        };
        Some(TextRange::new(start, end))
    }
}

#[cfg(test)]
mod tests;
