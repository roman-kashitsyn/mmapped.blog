# Blogware

A specialized LaTeX-to-HTML compiler designed for my blog.
It supports only a tiny fraction of LaTeX that I use in my articles.

## Document structure

The document body consists of regular text, environments, and commands.

Environments have the following syntax:

```tex
\begin{envname}[options]{args}
  content
\end{envname}
```

Both `options` and `args` are optional.

Commands have the following syntax:

```tex
\commandname[options]{arg1}{arg2}
```

Notes:

- Options are comma-separated _symbols_ in square brackets.
- Arguments must be in curly braces.
- Number of arguments varies by command.

### Argument types

Commands arguments are typed.
The engine supports the following types:

- `Seq`: an arbitrary sequence of commands, environments, and text snippets.
- `Sym`: an arbitrary symbol (`[*-._a-Z0-9]+`)
- `Num`: an integer number.
- `URL`: a URL.
- `AlignSpec`: a table alignment specification (`[|rlc ]*`).

## Article metadata

- **`\documentclass{class : Sym}`** - The document class (must always be `article` for now).
- **`abstract`** - The article summary environment.
- **`\reddit{url : URL}`** - A link to a Reddit discussion.
- **`\hackernews{url : URL}`** - A link to a Hacker News discussion.
- **`\title{title : Seq}`** - The document title.
- **`\subtitle{subtitle : Seq}`** - The document subtitle.
- **`\date{date : Sym}`** - The first publication date.
- **`\modified{date : Sym}`** - The last modified date.
- **`\keyword{keyword : Sym}`** - Adds a keyword.
- **`document`** - The document body environment.

## Text formatting

### Sections

- **`\section{label : Sym}{title : Seq}`** - A top-level section (unnumbered).
- **`\subsection{label : Sym}{title : Seq}`** - A subsection (unnumbered).
- **`\section*{title : Seq}`** - An invisible section without a title.

Unlike in standard LaTeX, sections require both a label and title:

```tex
\section{my-section}{Section Title}
\subsection{my-subsec}{Subsection Title}
```

### Basic Formatting
- **`\b{text : Seq}`** - Bold text.
- **`\u{text : Seq}`** - Underlined text.
- **`\emph{text : Seq}`** - Emphasized text (italic).
- **`\textsc{text : Seq}`** - Small caps.
- **`\normal{text : Seq}`** - Normal weight text.
- **`\strikethrough{text : Seq}`** - Strikethrough text.
- **`\code{text : Seq}`** - Inline code.
- **`code`** - A preformatted code block.
- **`verbatim`** - A preformatted code block (literal text; its interior is not formatted).
- **`\fun{text : Seq}`** - A function name.
- **`\kbd{text : Seq}`** - Keyboard input.

### Special Elements
- **`\circled{num : Num}`** - Circled numbers
- **`\center{text : Seq}`** - Centered text
- **`\newline`** - Line break
- **`\numspace`** - Numeric space
- **`\hrule`** - Horizontal rule
- **`\dingbat{symbol : Sym}`** - 

## Lists

- **`enumerate`** - A numbered list environment.
- **`itemize`** - A bulleted list environment.
- **`checklist`** - A checkbox list environment.
- **`\item`** - The list item marker.
- **`description`** - A description list environment.
- **`\term{term : Seq}{definition : Seq}`** - A term definitions within the `description` environment.

## Tables
- **`tabular{alignspec : AlignSpec}`** - A table with a header row.
- **`tabular*{alignspec : AlignSpec}`** - A table without a header row.
- **`\multicolumn{cols : Num}{align : AlignSpec}{content : Seq}`** - Creates a multi-column cell.

## Links and References
- **`\href{url : URL}{text : Seq}`** - A hyperlink.
- **`\nameref{label : Sym}`** - A named reference to a section or another article.
- **`\label{name : Sym}`** - A label for referencing (`\href{#name}{example}`).

## Figures
- **`figure`** - A figure environment (supports `[grayscale]` option).
- **`\includegraphics{path : Seq}`** - Includes an image located at `path` (relative to the blog repo root).

## Special Content

- **`\details{summary : Seq}{text : Seq}`** - Expandable details (spoiler).
- **`\epigraph{quote : Seq}{attribution : Seq}`** - An epigraph.
- **`\blockquote{quote : Seq}{attribution : Seq}`** - A block quote.
- **`\advice{label : Sym}{text : Seq}`** - An advice box.
- **`\marginnote{label : Sym}{text : Seq}`** - A margin note.
- **`\sidenote{label : Sym}{text : Seq}`** - A side notes (like footnote, but on the side).

## Math Support

- **`\math{text : Seq}`** - Displays the text using a math font.
- **`\frac{numerator : Seq}{denominator : Seq}`** - A fraction.
- **`\sub{text : Seq}`** - A subscript.
- **`\sup{text : Seq}`** - A superscript.

### Math Symbols
- **`\qed`** - The QED symbol.
- **`\ldots`** → … (ellipsis)
- **`\cdots`** → ⋯ (centered dots)
- **`\delta`** → δ, **`\Delta`** → Δ
- **`\times`** → ×, **`\itimes`** → invisible times
- **`\circ`** → ∘ (composition)
- **`\in`** → ∈, **`\ni`** → ∋, **`\notin`** → ∉, **`\notni`** → ∌
- **`\inf`** → ∞
- **`\sum`** → ∑, **`\int`** → ∫
- **`\leq`** → ≤
- **`\iff`** → ⇔
- **`\rightarrow`** → →, **`\Rightarrow`** → ⇒
- **`\leftarrow`** → ←, **`\Leftarrow`** → ⇐
- **`\fracslash`** → ∕

### Raw MathML support

- **`\mathml{text : Seq}`** - A raw MathML block.
- **`\mi{id : Seq}`** - A math identifier.
- **`\mn{num : Seq}`** - A number.
- **`\mo{op}`** - A stretchy operator.
- **`\mo*{op : Seq}`** - A non-stretchy operator.
- **`\msup{base : Seq}{sup : Seq}`**, **`\msub{base : Seq}{sub : Seq}`** - Math super/subscripts.
- **`\msubsup{base : Seq}{sub : Seq}{sup : Seq}`** - Combined sub/superscripts.
- **`\munderover{base : Seq}{under : Seq}{over : Seq}`** - Under/over constructs.
- **`\mtext{text : Seq}`** - Displays text using normal (non-math) font within a MathML block.
- **`\mrow{text : Seq}`** - A group of math symbols.
- **`\mtable{align : AlignSpec}{rows : Seq}`** - A math table.
- **`\mtr{row : Seq}`** - A row in a math table.
- **`\mtd{cell : Seq}`** - A cell in a math table.

## Comments

- **`%`** - Line comments (everything after `%` to end of line)
