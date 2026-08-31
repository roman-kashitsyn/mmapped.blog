; Highlights for .rftex (blogware markup).
;
; Capture names follow the nvim-treesitter convention. The grammar has a single
; generic `command` node, so commands are discriminated here by name rather than by
; node type: a command blogware gains later still highlights via the fallback on the
; first pattern, and giving it a role is a one-line edit to a list below.
;
; Patterns are ordered general first, specific last.

; ------------------------------------------------------------------- commands

(command name: (command_name) @function.macro)
(url_command name: (url_command_name) @function.macro)
(math_command name: (command_name) @function.macro)

; Metadata and document structure (blogware/lib/syntax.ml `sym_table`).
((command_name) @keyword
  (#any-of? @keyword
    "\\documentclass" "\\title" "\\subtitle" "\\date" "\\modified" "\\keyword"
    "\\featured" "\\section" "\\section*" "\\subsection" "\\label" "\\item"
    "\\hrule" "\\newline" "\\numspace" "\\qed" "\\multicolumn"))

; Inline markup styles the argument, not just the command name.
((command name: (command_name) @function.macro argument: (group) @markup.strong)
  (#eq? @function.macro "\\b"))

((command name: (command_name) @function.macro argument: (group) @markup.italic)
  (#any-of? @function.macro "\\emph" "\\textit"))

((command name: (command_name) @function.macro argument: (group) @markup.underline)
  (#eq? @function.macro "\\u"))

((command name: (command_name) @function.macro argument: (group) @markup.strikethrough)
  (#eq? @function.macro "\\strikethrough"))

((command name: (command_name) @function.macro argument: (group) @markup.raw)
  (#any-of? @function.macro "\\code" "\\kbd" "\\fun"))

((command name: (command_name) @function.macro argument: (group) @markup.quote)
  (#any-of? @function.macro "\\epigraph" "\\blockquote"))

; \section{anchor}{Title}, \subsection{anchor}{Title}
((command
   name: (command_name) @keyword
   argument: (group) @label
   argument: (group) @markup.heading)
  (#any-of? @keyword "\\section" "\\subsection"))

((command name: (command_name) @keyword argument: (group) @markup.heading)
  (#any-of? @keyword "\\title" "\\subtitle"))

; --------------------------------------------------------------------- links

(url_command url: (url_group (url) @markup.link.url))

((url_command name: (url_command_name) @function.macro argument: (group) @markup.link.label)
  (#eq? @function.macro "\\href"))

; Cross-references: the first argument is an identifier, not prose.
((command name: (command_name) @function.macro argument: (group) @label)
  (#any-of? @function.macro
    "\\label" "\\nameref" "\\bibref" "\\cite" "\\ref" "\\dingbat"
    "\\marginnote" "\\sidenote" "\\advice"))

((command
   name: (command_name) @function.macro
   argument: (group) @label
   argument: (group) @markup.link.label)
  (#eq? @function.macro "\\ref"))

; -------------------------------------------------------------- environments

["\\begin" "\\end"] @keyword

; Covers generic environments and the four with a specialised body alike: they all
; carry an `environment_name` node.
(environment_name) @type

(code_body (code_text) @markup.raw)
(verbatim_block (verbatim_body) @markup.raw)

(column_alignment) @type.qualifier

(row_separator) @punctuation.delimiter
(cell_separator) @punctuation.delimiter

; ---------------------------------------------------------------------- math

(math_number) @number
(math_operator) @operator
(math_symbol) @variable

(inline_math "$" @punctuation.special)
(display_math ["\\[" "\\]"] @punctuation.special)

["_" "^"] @operator

; Note: no `@spell` captures. Editors that use the tree-sitter-highlight crate treat
; an unrecognized capture name as "no highlight" and let it override a wider one, so a
; `(text) @spell` pattern silently blanks out every inline markup style. Add it back
; only if your editor is known to special-case `@spell` (Neovim does).

; ------------------------------------------------------------------- literals

(escaped_char) @string.escape

(comment) @comment

(options (option) @attribute)
(options ["[" "]" ","] @punctuation.bracket)

(group ["{" "}"] @punctuation.bracket)
(math_group ["{" "}"] @punctuation.bracket)
(url_group ["{" "}"] @punctuation.bracket)
(column_spec ["{" "}"] @punctuation.bracket)
