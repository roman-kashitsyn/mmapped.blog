# tree-sitter-rftex

A [tree-sitter](https://tree-sitter.github.io/) grammar for `.rftex`,
the LaTeX flavor used by every post on [mmapped.blog](https://mmapped.blog).

## Using it

From Rust:

```toml
[dependencies]
tree-sitter = "0.25"
tree-sitter-rftex = { path = "path/to/tree-sitter-rftex" }
```

```rust
let mut parser = tree_sitter::Parser::new();
parser.set_language(&tree_sitter_rftex::LANGUAGE.into())?;
let tree = parser.parse(source, None).unwrap();
```

The crate re-exports the shipped queries as `HIGHLIGHTS_QUERY`, `INJECTIONS_QUERY`
and `FOLDS_QUERY`, and the static node types as `NODE_TYPES`.

## Design

The grammar is built primarily for syntax highlighting.
Thus, it defines a single generic `command` node,
not one node type per known command.

The grammar defines special cases for commands that require custom lexing:

| construct | why it needs its own rule |
| --- | --- |
| `\href`, `\reddit`, `\hackernews`, `\lobsters` | These commands take a URL as an argument. URLs might contain '%' characters which would parse as comments under default rules. |
| `code` | only characters `\ $ %` are special inside it; braces and brackets are literal. |
| `verbatim` | raw text up to the literal `\end{verbatim}`; needs the external scanner. |
| `tabular`, `tabular*` | `&` and `\\` are separators, not text and not an escape. |
| `align*` | math cells split on `&` and `\\`. |

## Deviations from the precise parser

1. The tree-sitter parser doesn't know the command arity.
   It can parse '\qed{x}' as a command with one argument,
   whereas the precise parser treats it as a nullary '\qed' followed by a group '{x}'.
2. The tree-sitter parser doesn't fold the minus sign into a negative number literal.
   It parses '-1' as a minus operator followed by an integer.
   A precise parser identifies '-1' as a literal.
3. Tree-sitter parser doesn't check whether \begin/\end pairs match correctly.
4. Tree-sitter parser doesn't tokenize paragraph splits.
5. Tree-sitter parser doesn't remove the newline that immediately follows `\begin{code}`, `\begin{verbatim}` and `\begin{align*}`.
   It leaves that newline as part of the body.
6. Tree-sitter parser classifies optional bracket arguments and positional arguments
   (e.g., `\bibref[p. 5]{key}`) as a single generic `option` token.
7. `\operatorname{lcm}` and similar commands emit a `math_group` with individual symbols
   rather than a symbol token.
8. Quotation marks stay plain text.
9. Tree sitter doesn't accept a space after `\begin` (`\begin {code}`).
10. `\end{foo}` with no matching `\begin` is not a parse error.
11. A command followed by two spaces and an argument (`\emph  {x}`) is not a parse error.
12. Tree-sitter parser accepts whitespace-only option lists (`[ ]`) and empty URLs.
13. Tree-sitter parser accepts tabs (`\t`) in math.
14. `\<newline>` is one `escaped_char`.
15. Newlines inside `align*` stay in the tree as `math_operator` nodes.

## Development

```shell
make grammar        # npm install + regenerate src/parser.c from grammar.js
make grammar-test   # corpus fixtures, the full-blog parse gate, and cargo test
```
