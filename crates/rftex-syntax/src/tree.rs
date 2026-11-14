//! The syntax tree: a lossless, homogeneous tree stored in one flat vector.
//!
//! Elements are laid out in pre-order, so a node is followed by all of its
//! descendants. The tree holds kinds and offsets only; text is read from the
//! source the tree was parsed from. Ids are indices into the vector and are
//! meaningful for one tree only.

use std::fmt;

use crate::kind::SyntaxKind;

/// A half-open range of byte offsets into the source.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct TextRange {
    pub start: u32,
    pub end: u32,
}

impl TextRange {
    pub fn new(start: u32, end: u32) -> TextRange {
        debug_assert!(start <= end);
        TextRange { start, end }
    }

    pub fn empty(offset: u32) -> TextRange {
        TextRange {
            start: offset,
            end: offset,
        }
    }

    pub fn len(self) -> u32 {
        self.end - self.start
    }

    pub fn is_empty(self) -> bool {
        self.start == self.end
    }

    pub fn contains(self, offset: u32) -> bool {
        self.start <= offset && offset < self.end
    }

    pub fn contains_range(self, other: TextRange) -> bool {
        self.start <= other.start && other.end <= self.end
    }

    /// The text this range covers in `src`.
    pub fn slice(self, src: &str) -> &str {
        &src[self.start as usize..self.end as usize]
    }
}

impl fmt::Display for TextRange {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}..{}", self.start, self.end)
    }
}

/// Identifies an element (a node or a token) of one [`Tree`].
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct NodeId(u32);

impl NodeId {
    fn index(self) -> usize {
        self.0 as usize
    }
}

#[derive(Clone, Copy, Debug)]
struct Element {
    kind: SyntaxKind,
    parent: u32,
    start: u32,
    end: u32,
    /// Index one past the last descendant.
    subtree_end: u32,
}

const NO_PARENT: u32 = u32::MAX;

/// A syntax tree. See the [module documentation](self).
#[derive(Clone, Debug)]
pub struct Tree {
    elements: Vec<Element>,
}

impl Tree {
    /// The root node. It covers the whole source.
    pub fn root(&self) -> NodeId {
        NodeId(0)
    }

    /// The number of elements, tokens included.
    pub fn len(&self) -> usize {
        self.elements.len()
    }

    pub fn is_empty(&self) -> bool {
        self.elements.is_empty()
    }

    pub fn kind(&self, id: NodeId) -> SyntaxKind {
        self.elements[id.index()].kind
    }

    pub fn is_token(&self, id: NodeId) -> bool {
        self.kind(id).is_token()
    }

    pub fn range(&self, id: NodeId) -> TextRange {
        let element = &self.elements[id.index()];
        TextRange {
            start: element.start,
            end: element.end,
        }
    }

    /// The text of an element in `src`, which must be the parsed source.
    pub fn text<'s>(&self, id: NodeId, src: &'s str) -> &'s str {
        self.range(id).slice(src)
    }

    pub fn parent(&self, id: NodeId) -> Option<NodeId> {
        match self.elements[id.index()].parent {
            NO_PARENT => None,
            parent => Some(NodeId(parent)),
        }
    }

    /// The element's parent, grandparent and so on up to the root.
    pub fn ancestors(&self, id: NodeId) -> impl Iterator<Item = NodeId> + '_ {
        std::iter::successors(self.parent(id), |&id| self.parent(id))
    }

    /// The direct children, tokens included, in source order.
    pub fn children(&self, id: NodeId) -> Children<'_> {
        Children {
            tree: self,
            next: id.0 + 1,
            end: self.elements[id.index()].subtree_end,
        }
    }

    /// The first direct child of the given kind.
    pub fn child(&self, id: NodeId, kind: SyntaxKind) -> Option<NodeId> {
        self.children(id).find(|&child| self.kind(child) == kind)
    }

    /// The element and everything below it, in source order.
    pub fn descendants(&self, id: NodeId) -> impl Iterator<Item = NodeId> {
        (id.0..self.elements[id.index()].subtree_end).map(NodeId)
    }

    /// The token that covers `offset`. Tokens are never empty, so there is
    /// exactly one unless `offset` is at or past the end of the source.
    pub fn token_at_offset(&self, offset: u32) -> Option<NodeId> {
        let mut id = self.root();
        if !self.range(id).contains(offset) {
            return None;
        }
        while !self.is_token(id) {
            id = self
                .children(id)
                .find(|&child| self.range(child).contains(offset))?;
        }
        Some(id)
    }

    /// The smallest element whose range includes all of `range`.
    pub fn covering_element(&self, range: TextRange) -> NodeId {
        let mut id = self.root();
        while let Some(child) = self
            .children(id)
            .find(|&child| self.range(child).contains_range(range))
        {
            // An empty range on a boundary fits two siblings; the first wins.
            id = child;
        }
        id
    }

    /// Renders the tree one element per line, for tests and debugging.
    pub fn dump(&self, src: &str) -> String {
        let mut out = String::new();
        self.dump_element(self.root(), src, 0, &mut out);
        out
    }

    fn dump_element(&self, id: NodeId, src: &str, depth: usize, out: &mut String) {
        use fmt::Write;
        let _ = write!(
            out,
            "{:depth$}{:?}@{}",
            "",
            self.kind(id),
            self.range(id),
            depth = depth * 2
        );
        if self.is_token(id) {
            let _ = write!(out, " {:?}", self.text(id, src));
        }
        out.push('\n');
        for child in self.children(id) {
            self.dump_element(child, src, depth + 1, out);
        }
    }
}

/// Iterator over the direct children of a node.
#[derive(Clone)]
pub struct Children<'t> {
    tree: &'t Tree,
    next: u32,
    end: u32,
}

impl Iterator for Children<'_> {
    type Item = NodeId;

    fn next(&mut self) -> Option<NodeId> {
        if self.next >= self.end {
            return None;
        }
        let id = NodeId(self.next);
        self.next = self.tree.elements[id.index()].subtree_end;
        Some(id)
    }
}

/// Builds a [`Tree`] from a pre-order stream of open, token and close calls.
pub(crate) struct TreeBuilder {
    elements: Vec<Element>,
    open: Vec<u32>,
    offset: u32,
}

impl TreeBuilder {
    pub(crate) fn new() -> TreeBuilder {
        TreeBuilder {
            elements: Vec::new(),
            open: Vec::new(),
            offset: 0,
        }
    }

    fn push(&mut self, kind: SyntaxKind, len: u32) -> u32 {
        let index = self.elements.len() as u32;
        self.elements.push(Element {
            kind,
            parent: self.open.last().copied().unwrap_or(NO_PARENT),
            start: self.offset,
            end: self.offset + len,
            subtree_end: index + 1,
        });
        index
    }

    pub(crate) fn open(&mut self, kind: SyntaxKind) {
        debug_assert!(!kind.is_token());
        let index = self.push(kind, 0);
        self.open.push(index);
    }

    pub(crate) fn token(&mut self, kind: SyntaxKind, len: u32) {
        debug_assert!(kind.is_token() && len > 0 && !self.open.is_empty());
        self.push(kind, len);
        self.offset += len;
    }

    pub(crate) fn close(&mut self) {
        let index = self.open.pop().expect("close without a matching open") as usize;
        self.elements[index].end = self.offset;
        self.elements[index].subtree_end = self.elements.len() as u32;
    }

    pub(crate) fn finish(self) -> Tree {
        assert!(
            self.open.is_empty() && !self.elements.is_empty(),
            "unbalanced tree"
        );
        Tree {
            elements: self.elements,
        }
    }
}

#[cfg(test)]
mod tests;
