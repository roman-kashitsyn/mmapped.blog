#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <string.h>

// External tokens for constructs the internal lexer cannot express.
//
//  - VERBATIM_BODY: raw text up to, but not including, the literal `\end{verbatim}`
//    (`many_till_chars`, blogware/lib/tex_parser.ml:564). A regex cannot express
//    "any run of characters not containing this string".
//  - CMD_SPACE: the single space blogware swallows after a command name
//    (`skip_char ' '`, tex_parser.ml:455). It has to be external because the `text`
//    token would otherwise win on match length and absorb it, which would silently
//    reintroduce the space that `\code{1355\ldots 48de}` relies on being dropped.

enum TokenType {
  VERBATIM_BODY,
  CMD_SPACE,
  ERROR_SENTINEL,
};

static const char END_VERBATIM[] = "\\end{verbatim}";
static const unsigned END_VERBATIM_LEN = sizeof(END_VERBATIM) - 1;

void *tree_sitter_rftex_external_scanner_create(void) { return NULL; }

void tree_sitter_rftex_external_scanner_destroy(void *payload) { (void)payload; }

unsigned tree_sitter_rftex_external_scanner_serialize(void *payload, char *buffer) {
  (void)payload;
  (void)buffer;
  return 0;
}

void tree_sitter_rftex_external_scanner_deserialize(void *payload, const char *buffer,
                                                    unsigned length) {
  (void)payload;
  (void)buffer;
  (void)length;
}

static bool scan_verbatim_body(TSLexer *lexer) {
  bool has_content = false;
  unsigned matched = 0;

  // The token ends where the terminator begins, so keep the end marker trailing
  // behind every character that turns out to be body content.
  lexer->mark_end(lexer);

  while (lexer->lookahead != 0) {
    if (lexer->lookahead == (unsigned char)END_VERBATIM[matched]) {
      matched++;
      lexer->advance(lexer, false);
      if (matched == END_VERBATIM_LEN) {
        lexer->result_symbol = VERBATIM_BODY;
        return has_content;
      }
      continue;
    }

    if (matched > 0) {
      // A partial terminator match that fizzled out: those characters were body
      // content after all. Re-test the current character from the start.
      matched = 0;
      has_content = true;
      lexer->mark_end(lexer);
      continue;
    }

    lexer->advance(lexer, false);
    has_content = true;
    lexer->mark_end(lexer);
  }

  // Unterminated verbatim block: leave the error to the parser.
  return false;
}

bool tree_sitter_rftex_external_scanner_scan(void *payload, TSLexer *lexer,
                                             const bool *valid_symbols) {
  (void)payload;

  // Do not invent tokens while the parser is recovering from an error.
  if (valid_symbols[ERROR_SENTINEL]) {
    return false;
  }

  if (valid_symbols[CMD_SPACE] && lexer->lookahead == ' ') {
    lexer->advance(lexer, false);
    lexer->result_symbol = CMD_SPACE;
    return true;
  }

  if (valid_symbols[VERBATIM_BODY]) {
    // `\begin{verbatim}[opts]` — the option list is still ahead of the body, and the
    // external scanner runs before the internal lexer, so decline the `[` explicitly.
    // A real body always starts with the newline that follows `\begin{verbatim}`.
    if (lexer->lookahead == '[') {
      return false;
    }
    return scan_verbatim_body(lexer);
  }

  return false;
}
