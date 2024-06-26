package main

import (
	"fmt"
	"io"
	"net/url"
	"os"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

type TokenKind int

const (
	TokText TokenKind = iota
	TokLBrace
	TokRBrace
	TokLBracket
	TokRBracket
	TokAmp
	TokControl
	TokInlineMath
)

type token struct {
	kind TokenKind
	// name is the command symbol if kind == TokControl
	name sym
	// body is the textual content if kind == TokText
	body string
}

type MathTokenKind int

const (
	// MathTokSym is a single-letter symbol.
	MathTokSym MathTokenKind = iota
	// MathTokNum is a number.
	MathTokNum
	// MathTokControl is a start of a control sequence (either command or an environment).
	MathTokControl
	// MathTokOp is a math operator operator (+, -, braces, etc.).
	MathTokOp
	MathTokSup
	MathTokSub
	// MathTokGroupStart is the start of a group ({).
	MathTokGroupStart
	// MathTokGroupEnd is the end of a group (}).
	MathTokGroupEnd
	// MathEndInlineMath is the end of an inline math environment ($).
	MathEndInlineMath
)

type mathToken struct {
	kind MathTokenKind
	// name is the command symbol if kind == MathTokControl
	name sym
	// body is the textual token representation.
	// * MathTokSym: the character
	// * MathTokNum: the number
	// * MathTokOp: the operator
	body string
}

func (t *token) String() string {
	switch t.kind {
	case TokLBrace:
		return "{"
	case TokRBrace:
		return "}"
	case TokLBracket:
		return "["
	case TokRBracket:
		return "]"
	case TokAmp:
		return "&"
	case TokText:
		return fmt.Sprintf("Text(%s)", t.body)
	case TokControl:
		return fmt.Sprintf("Control(\\%s)", SymbolName(t.name))
	case TokInlineMath:
		return "$"
	}
	return "Unknown"
}

type stream struct {
	source string
	input  string
	pos    int
}

func StreamFromFile(path string) (*stream, error) {
	s := &stream{pos: 0, source: path}
	inputBytes, err := os.ReadFile(path)
	if err != nil {
		return s, err
	}
	s.input = string(inputBytes)
	return s, nil
}

func (s *stream) IsEmpty() bool {
	return s.pos == len(s.input)
}

func (s *stream) Error(msg string) error {
	return fmt.Errorf("%s:%d %s", s.source, s.pos, msg)
}

func (s *stream) Errorf(msg string, a ...any) error {
	return s.ErrorfAt(s.pos, msg, a...)
}

func (s *stream) ErrorfAt(pos int, msg string, a ...any) error {
	return fmt.Errorf("%s:%d %s", s.source, pos, fmt.Sprintf(msg, a...))
}

// Rest returns the rest of the input as a string.
func (s *stream) Rest() string {
	return s.input[s.pos:]
}

func (s *stream) Expect(exp TokenKind) error {
	var t token
	if err := s.NextToken(&t); err != nil {
		return err
	}
	if t.kind != exp {
		return s.Errorf("expected token kind %v, got %v", exp, t.kind)
	}
	return nil
}

func (s *stream) Consume(t TokenKind) {
	if err := s.Expect(t); err != nil {
		panic(err)
	}
}

func (s *stream) TakeUntil(c rune) string {
	str := s.Rest()
	i := strings.IndexRune(str, c)
	if i == -1 {
		s.pos += len(str)
		return str
	} else {
		s.pos += i
		return str[0:i]
	}
}

func (s *stream) TakeUntilAny(chars string) string {
	str := s.Rest()
	i := strings.IndexAny(str, chars)
	if i == -1 {
		s.pos += len(str)
		return str
	} else {
		s.pos += i
		return str[0:i]
	}
}

func (s *stream) SkipNewline() {
	str := s.Rest()
	if len(str) > 0 && str[0] == '\n' {
		s.Skip(1)
	}
}

func (s *stream) Skip(n int) {
	s.pos += n
}

func (s *stream) HasPrefix(p string) bool {
	return strings.HasPrefix(s.Rest(), p)
}

func (s *stream) LookAhead() TokenKind {
	pos := s.pos
	var t token
	s.NextToken(&t)
	s.pos = pos
	return t.kind
}

func isSpecial(c rune) bool {
	switch c {
	case '%', '{', '}', '\\', '[', ']', '&', '$':
		return true
	default:
		return false
	}
}

func (s *stream) scanFunc(shape string, acceptFunc func(rune) bool, validateFunc func(string) error) (text Text, err error) {
	pos := s.pos
	str := s.Rest()
	i := strings.IndexFunc(str, func(c rune) bool { return !acceptFunc(c) })
	if i == -1 {
		i = len(str)
	}
	if i < 1 {
		err = s.Errorf("expected a token of shape %s", shape)
		return
	}
	if err = validateFunc(str[:i]); err != nil {
		err = s.Errorf("token is not a valid %s: %v", shape, err)
	}
	text = Text{pos: pos, body: str[:i]}
	s.Skip(i)
	return
}

func (s *stream) ScanSymbol() (text Text, err error) {
	return s.scanFunc("symbol", IsSymbolic, func(s string) error { return nil })
}

func isURLChar(c rune) bool {
	switch c {
	case '-', '.', '_', '~', ':', '/', '?', '#', '[', ']', '@', '!', '$', '&', '(', ')', '*', '+', ',', ';', '%', '=', '\'':
		return true
	default:
		return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9'
	}
}

func (s *stream) ScanURL() (text Text, err error) {
	return s.scanFunc("URL", isURLChar, func(urlText string) error {
		_, err := url.Parse(urlText)
		return err
	})
}

func (s *stream) ScanNumber() (text Text, err error) {
	return s.scanFunc("number", func(c rune) bool { return c == '-' || c >= '0' && c <= '9' }, func(numText string) error {
		_, err := strconv.Atoi(numText)
		return err
	})
}

func (s *stream) ScanAlignSpec() (text Text, err error) {
	return s.scanFunc("number", func(c rune) bool {
		switch c {
		case 'c', 'r', 'l', '|', ' ':
			return true
		default:
			return false
		}
	}, func(text string) error {
		_, err := parseColSpecs(text)
		return err
	})
}

func (s *stream) FindVerbatimEnd() (body string, err error) {
	const VerbatimMarker = "\\end{verbatim}"
	str := s.Rest()
	i := strings.Index(str, VerbatimMarker)
	if i == -1 {
		err = s.Error("no verbatim end marker")
		return
	}
	body = str[:i]
	s.Skip(i + len(VerbatimMarker))
	return
}

func (s *stream) NextToken(tok *token) error {
	for !s.IsEmpty() {
		str := s.Rest()
		i := strings.IndexFunc(str, isSpecial)
		if i == -1 || i > 0 {
			tok.kind = TokText
			if i == -1 {
				tok.body = str
				s.Skip(len(str))
			} else {
				tok.body = str[:i]
				s.Skip(i)
			}
			return nil
		}
		// Looking at a special character
		c1, size1 := utf8.DecodeRuneInString(str)
		s.Skip(size1)
		switch c1 {
		case '{':
			tok.kind = TokLBrace
			tok.body = "{"
			return nil
		case '}':
			tok.kind = TokRBrace
			tok.body = "}"
			return nil
		case '[':
			tok.kind = TokLBracket
			tok.body = "["
			return nil
		case ']':
			tok.kind = TokRBracket
			tok.body = "]"
			return nil
		case '&':
			tok.kind = TokAmp
			tok.body = "&"
			return nil
		case '\\':
			str = str[size1:]
			c2, size2 := utf8.DecodeRuneInString(str)
			switch c2 {
			case '%', '\\', '&', '#', '_', '{', '}', '[', ']', '$':
				tok.kind = TokText
				tok.body = string(c2)
				s.Skip(size2)
				return nil
			default:
				// consume the command sequence
				var nameBuilder strings.Builder
				// BUG: this code does not handle the last character proerly
				for pos, c := range str {
					// TODO: handle comments
					if IsSymbolic(c) {
						nameBuilder.WriteRune(c)
						continue
					}
					tok.kind = TokControl
					tok.name = Symbol(nameBuilder.String())
					if c == ' ' {
						s.Skip(pos + 1)
					} else {
						s.Skip(pos)
					}
					return nil
				}
			}
		case '%':
			// Comment start: skip until the end of the line
			n := len(str)
			str = skipLine(str)
			s.Skip(n - len(str) - 1)
			continue
		default:
			return fmt.Errorf("%s:%d: NextToken(): unexpected rune %v (%s)", s.source, s.pos, c1, string(c1))
		}
	}
	return io.EOF
}

func (s *stream) NextMathToken(tok *mathToken) error {
	for !s.IsEmpty() {
		str := s.Rest()
		c1, size1 := utf8.DecodeRuneInString(str)
		s.Skip(size1)
		switch c1 {
		case ' ':
			// Math mode ignores spaces
			continue
		case '{':
			tok.kind = MathTokGroupStart
			tok.body = "{"
			return nil
		case '}':
			tok.kind = MathTokGroupEnd
			tok.body = "}"
			return nil
		case '^':
			tok.kind = MathTokSup
			tok.body = "^"
			return nil
		case '_':
			tok.kind = MathTokSub
			tok.body = "_"
			return nil
		case '$':
			tok.kind = MathEndInlineMath
			tok.body = "$"
			return nil
		case '-', '+', '&', '=', ',', '[', ']', '|':
			tok.kind = MathTokOp
			tok.body = string(c1)
			return nil
		case '\\':
			str = str[size1:]
			c2, size2 := utf8.DecodeRuneInString(str)
			switch c2 {
			case '%', '{', '}', '\\', '^', '_':
				tok.kind = MathTokOp
				tok.body = string(c2)
				s.Skip(size2)
				return nil
			default:
				// consume the command sequence
				var nameBuilder strings.Builder
				n := 0
				for {
					c, s := utf8.DecodeRuneInString(str)
					// TODO: handle comments
					if IsSymbolic(c) {
						nameBuilder.WriteRune(c)
						str = str[s:]
						n += s
						continue
					}
					break
				}
				tok.kind = MathTokControl
				tok.name = Symbol(nameBuilder.String())
				s.Skip(n)
				return nil
			}
		case '%':
			// Comment start: skip until the end of the line
			n := len(str)
			str = skipLine(str)
			s.Skip(n - len(str) - 1)
			continue
		default:
			if unicode.IsLetter(c1) {
				tok.kind = MathTokSym
				tok.body = string(c1)
				return nil
			}
			if unicode.IsDigit(c1) {
				n := 0
				suffix := str[size1:]
				for {
					c, cs := utf8.DecodeRuneInString(suffix)
					if unicode.IsDigit(c) {
						n += cs
						suffix = suffix[cs:]
						continue
					}
					break
				}
				tok.kind = MathTokNum
				tok.body = str[:n+size1]
				s.Skip(n)
				return nil
			}
			return fmt.Errorf("NextMathToken(): unexpected rune %v (%s)", c1, string(c1))
		}
	}
	return io.EOF
}

func skipLine(s string) string {
	i := strings.IndexRune(s, '\n')
	if i == -1 {
		return ""
	} else {
		return s[i+1:]
	}
}
