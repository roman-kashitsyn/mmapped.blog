; Language injection for code blocks.
;
; `\begin{code}[rust]` names the language in an option, but the language is not always
; the first option (`[good,cpp]`, `[ocaml,linenumbers]`), so this matches once per
; option and relies on the editor ignoring option names that are not languages
; (`good`, `bad`, `linenumbers`, `center`).

((code_block
   (options (option) @injection.language)
   (code_body) @injection.content))

; \begin{verbatim}[j] is deliberately not injected: verbatim is raw output, not source.
