/**
 * @file Tree-sitter grammar for .rftex, the LaTeX flavor parsed by blogware.
 *
 * Reference implementation: blogware/lib/tex_parser.ml. Line references in the
 * comments below point at it. The grammar deliberately does NOT model per-command
 * arity (blogware/lib/syntax.ml `cmd_args`): a single generic `command` node keeps
 * highlights.scm small and lets new blogware commands highlight without a grammar
 * change. See README.md for the full list of accepted deviations.
 *
 * @license CC-BY-4.0
 */

/// <reference types="tree-sitter-cli/dsl" />

// Text mode: `% { } \ [ ] & $` are special (tex_parser.ml:9-12). Everything else,
// newlines and UTF-8 included, is literal.
const TEXT = /[^%{}\\\[\]&$]+/;

// Command names: `[A-Za-z0-9*.-]+` (`is_symbolic`, tex_parser.ml:14). Note the `*`,
// which is what makes `\section*` and `align*` single names.
const CMD_NAME = /\\[A-Za-z0-9*.\-]+/;

// Escapes producing one literal character. Text mode allows `% \ & # _ { } $` and a
// newline (tex_parser.ml:441-446); math mode allows `% { } \ ^ _` (tex_parser.ml:134-137).
// One token covers the union; the small over-acceptance is harmless.
const ESCAPED = /\\[%\\&#_{}$^\n]/;

// `is_url_char` (tex_parser.ml:16-21). This is the one argument charset that is not a
// subset of TEXT: it adds `% & $ [ ]`, so URL arguments need their own lexer or a URL
// like .../Read%E2%80%93eval%E2%80%93print_loop would start a comment at `%`.
const URL = /[A-Za-z0-9\-._~:\/?#\[\]@!$&()*+,;%=']+/;

// `is_math_op` (tex_parser.ml:29-34), `&` included: blogware accepts it as a Math_op
// in plain math. In align* and tabular the `cell_separator` string token wins the
// equal-length tie against this regex, so `&` stays a separator there — the same
// split blogware makes between parse_m_list and the align cell_end lookahead.
const MATH_OP = /[+\-&=,;\[\]|()<>:\n]/;

// `\begin{<name>}` / `\end{<name>}` for an environment whose body is lexed
// differently from a plain node sequence. The name is a plain string token, so it
// beats the generic `environment_name` regex on the equal-length tie-break and picks
// the specialised rule, while `\begin{codegen}` still takes the generic rule because
// the regex matches longer. Aliasing keeps every environment the same shape in the
// tree, which is what lets one query pattern highlight them all.
const envDelims = ($, name) => ({
  begin: (n = name) =>
    seq('\\begin', '{', field('name', alias(n, $.environment_name)), '}'),
  end: (n = name) =>
    seq('\\end', '{', field('end_name', alias(n, $.environment_name)), '}'),
});

module.exports = grammar({
  name: 'rftex',

  // No whitespace extra: in a markup language whitespace is content, and letting the
  // lexer skip it would drop spaces out of `text` runs. Comments are an extra because
  // blogware skips them in every context except verbatim (tex_parser.ml:509-518).
  extras: ($) => [$.comment],

  externals: ($) => [
    $.verbatim_body,
    $._cmd_space,
    $._error_sentinel,
    $._verbatim_before_options,
  ],

  rules: {
    source_file: ($) => repeat($._content),

    // ---------------------------------------------------------------- content

    _content: ($) =>
      choice(
        $.escaped_char,
        $._environment,
        $.url_command,
        $.command,
        $.group,
        $.display_math,
        $.inline_math,
        $.text,
        $._bracket_text,
      ),

    group: ($) => seq('{', repeat($._content), '}'),

    text: ($) => token(TEXT),

    escaped_char: ($) => token(ESCAPED),

    // `[` and `]` outside an option position are one-character text nodes
    // (`parse_bracket_text`, tex_parser.ml:212-215). Negative precedence so the `[`
    // that opens an option list always wins the tie.
    _bracket_text: ($) => token(prec(-1, /[\[\]]/)),

    // `%` to end of line, newline included (tex_parser.ml:191-193).
    comment: ($) => token(/%[^\n]*\n?/),

    // --------------------------------------------------------------- commands

    // `\name[opts]{arg}...`. Arguments are attached greedily rather than by arity.
    // Verified safe on the corpus: a command is followed by `{` exactly when it takes
    // an argument.
    command: ($) =>
      prec.right(
        seq(
        field('name', $.command_name),
        optional($._cmd_space),
        optional($.options),
        repeat(field('argument', $.group)),
      )),

    // The four commands taking an `At_url` argument (syntax.ml:421-424).
    url_command: ($) =>
      prec.right(
        seq(
        field('name', $.url_command_name),
        optional($._cmd_space),
        optional($.options),
        field('url', $.url_group),
        repeat(field('argument', $.group)),
      )),

    command_name: ($) => token(CMD_NAME),

    // Plain strings, so they beat CMD_NAME on the equal-length tie-break.
    url_command_name: ($) =>
      choice('\\href', '\\reddit', '\\hackernews', '\\lobsters'),

    // `url` is optional so a half-typed `\href{` parses instead of stranding the
    // whole line in an ERROR node. blogware rejects an empty URL (take_while1).
    url_group: ($) => seq('{', optional($.url), '}'),
    // Higher precedence so a leading `%` (a valid first URL character, e.g.
    // `\href{%2Fdocs}{...}`) is lexed as the URL rather than as the `comment`
    // extra, which would otherwise win on match length and swallow the rest of
    // the line.
    url: ($) => token(prec(1, URL)),

    // `[sym,sym,...]` (tex_parser.ml:358-372). The option token is deliberately looser
    // than `is_symbolic` so that `\bibref[p. 5]{key}` (`Opt_arg At_seq`, syntax.ml:469)
    // parses under the same rule instead of needing a second bracket form. Whitespace
    // trims around each option like blogware's `ws *> symbol <* ws`, so `[a ,b]` parses.
    options: ($) =>
      seq(
        '[',
        optional(seq($.option, repeat(seq(',', $.option)))),
        optional($._ws),
        ']',
      ),
    // prec.right resolves the shift/reduce conflict on the trailing `_ws`: the
    // whitespace joins the preceding option (the token is hidden either way).
    option: ($) =>
      prec.right(seq(optional($._ws), $._option_text, optional($._ws))),
    _option_text: ($) => token(/[^\[\],\s]+([ \t]+[^\[\],\s]+)*/),
    _ws: ($) => token(/\s+/),

    // ----------------------------------------------------------- environments

    _environment: ($) =>
      choice(
        $.code_block,
        $.verbatim_block,
        $.tabular,
        $.align_block,
        $.environment,
      ),

    // Generic `\begin{name} ... \end{name}`. Tree-sitter cannot check that the two
    // names match; a mismatch parses here and is caught by blogware instead.
    environment: ($) =>
      seq(
        '\\begin',
        '{',
        field('name', $.environment_name),
        '}',
        optional($.options),
        repeat($._content),
        '\\end',
        '{',
        field('end_name', $.environment_name),
        '}',
      ),

    environment_name: ($) => token(/[A-Za-z0-9*.\-]+/),

    // Inside `code`, only `\ $ %` are special (`parse_code_text`, tex_parser.ml:543):
    // braces, brackets and `&` are literal, but commands and math stay live.
    code_block: ($) =>
      seq(
        envDelims($, 'code').begin(),
        optional($.options),
        optional($.code_body),
        envDelims($, 'code').end(),
      ),

    // One contiguous node so an injection query can hand the whole body, literal
    // braces included, to the embedded language's parser.
    code_body: ($) => repeat1($._code_content),

    _code_content: ($) =>
      choice(
        $.escaped_char,
        $.url_command,
        $.command,
        $.display_math,
        $.inline_math,
        $.code_text,
        $._code_brace,
      ),

    code_text: ($) => token(/[^\\$%{}\[\]]+/),

    // Braces and brackets in code are literal, except where the grammar expects a
    // real one: the `{` opening a command argument and the `[` opening the option
    // list right after `\begin{code}` both win on precedence.
    _code_brace: ($) => token(prec(-1, /[{}\[\]]/)),

    // Raw until the literal `\end{verbatim}` (`many_till_chars`, tex_parser.ml:564).
    verbatim_block: ($) =>
      seq(
        envDelims($, 'verbatim').begin(),
        // Never lexed; marks the state where the option list may still follow.
        // Its presence in valid_symbols lets the scanner decline `[` only before
        // the options are consumed (see src/scanner.c).
        optional($._verbatim_before_options),
        optional($.options),
        optional($.verbatim_body),
        envDelims($, 'verbatim').end(),
      ),

    // `\begin{tabular}[opts]{colspec}` — options come before the column spec
    // (tex_parser.ml:473-474). Rows and cells are left flat: the grammar marks the
    // separators, the consumer groups them (tex_parser.ml:636-685).
    tabular: ($) =>
      seq(
        envDelims($).begin(choice('tabular', 'tabular*')),
        optional($.options),
        field('columns', $.column_spec),
        repeat($._table_content),
        envDelims($).end(choice('tabular', 'tabular*')),
      ),

    column_spec: ($) => seq('{', $.column_alignment, '}'),
    column_alignment: ($) => token(/[clr| ]+/),

    _table_content: ($) =>
      choice(
        $.row_separator,
        $.cell_separator,
        $.escaped_char,
        $.url_command,
        $.command,
        $.group,
        $.display_math,
        $.inline_math,
        $.text,
      ),

    // `\\` is a literal backslash in text but a row separator here; the string token
    // beats ESCAPED on the equal-length tie-break (tex_parser.ml:607-619).
    row_separator: ($) => '\\\\',
    cell_separator: ($) => '&',

    // Math cells split on `&` and `\\`; alignment is synthesized by the consumer
    // (tex_parser.ml:712-721), not by the grammar.
    align_block: ($) =>
      seq(
        envDelims($, 'align*').begin(),
        repeat(choice($.row_separator, $.cell_separator, $._math_content)),
        envDelims($, 'align*').end(),
      ),

    // ------------------------------------------------------------------- math

    inline_math: ($) => seq('$', repeat($._math_content), '$'),

    display_math: ($) => seq('\\[', repeat($._math_content), '\\]'),

    // Spaces are standalone items rather than a prefix of each atom. Attaching them
    // to the atom makes a trailing space ambiguous wherever math abuts a non-atom
    // (`\mathrm{s} \times`, or the space before `&` in align*), and blogware skips
    // them independently anyway (`skip_math_spaces`, tex_parser.ml:36).
    _math_content: ($) => choice($._math_space, $._math_atom, $.math_term),

    // Nucleus with optional sub/superscript in either order, at most one of each
    // (`collect_sub_sup`, tex_parser.ml:94-109).
    math_term: ($) =>
      seq(
        field('nucleus', $._math_atom),
        choice(
          seq($._math_sub, optional($._math_sup)),
          seq($._math_sup, optional($._math_sub)),
        ),
      ),

    _math_sub: ($) => seq('_', field('sub', $._math_atom)),
    _math_sup: ($) => seq('^', field('sup', $._math_atom)),

    _math_atom: ($) =>
      choice(
        $.math_group,
        $.math_command,
        $.escaped_char,
        $.math_number,
        $.math_operator,
        $.math_symbol,
      ),

    math_group: ($) => seq('{', repeat($._math_content), '}'),

    // `\frac`/`\binom` take two groups, `\operatorname`/`\mathrm`/`\mathcal` one
    // (syntax.ml:471-481); `\left`/`\right` take a bare delimiter character
    // (tex_parser.ml:145-152), which lands here as a following math_operator.
    math_command: ($) =>
      prec.right(seq(field('name', $.command_name), repeat($.math_group))),

    math_number: ($) => token(/[0-9]+/),
    math_operator: ($) => token(MATH_OP),
    // Letters are one node each, matching `parse_math_symbol` (tex_parser.ml:68-70).
    math_symbol: ($) => token(/[A-Za-z]/),
    // `skip_math_spaces` skips only spaces (tex_parser.ml:36).
    _math_space: ($) => token(/[ \t]+/),
  },
});
