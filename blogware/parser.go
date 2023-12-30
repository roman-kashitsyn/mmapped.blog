package main

import (
	"fmt"
	"strings"
	"unicode"
)

func Push[T any](stack *[]T, item T) {
	*stack = append(*stack, item)
}

func IsValidSymbol(s string) bool {
	return !strings.ContainsFunc(s, func(c rune) bool { return !IsSymbolic(c) })
}

func IsSymbolic(c rune) bool {
	switch c {
	case '*', '-', '.', '_':
		return true
	default:
		return unicode.IsLetter(c) || unicode.IsDigit(c)
	}
}

func parseEnvName(s *stream) (result sym, err error) {
	if err = s.Expect(TokLBrace); err != nil {
		return
	}
	var t token
	if err = s.NextToken(&t); err != nil {
		return
	}
	if t.kind != TokText {
		err = s.Errorf("expected env name, got token %s", &t)
		return
	}
	if !IsValidSymbol(t.body) {
		err = s.Errorf("invalid symbol name %s", t.body)
		return
	}
	if err = s.Expect(TokRBrace); err != nil {
		return
	}
	result = Symbol(t.body)
	return
}

func parseOptions(s *stream) (opts []sym, err error) {
	p := s.pos
	var t token
	if err = s.NextToken(&t); err != nil {
		return
	}
	if t.kind != TokLBracket {
		s.pos = p
		return
	}
	if err = s.NextToken(&t); err != nil {
		return
	}
	switch t.kind {
	case TokRBracket:
		return
	case TokText:
		sopts := strings.Split(t.body, ",")
		opts = make([]sym, len(sopts))
		for i, sopt := range sopts {
			if !IsValidSymbol(sopt) {
				err = s.Errorf("invalid symbol name in options: %s", sopt)
				return
			}
			opts[i] = Symbol(sopt)
		}
		err = s.Expect(TokRBracket)
	default:
		err = s.Errorf("unexpected token %s while parsing options", &t)
	}
	return
}

func parseArg(s *stream, typ ArgType) (body []Node, err error) {
	var t token
	if err = s.NextToken(&t); err != nil {
		return
	}
	if t.kind != TokLBrace {
		err = s.Errorf("Expected a {, got %v", t)
	}
	switch typ {
	case ArgTypeSeq:
	loop:
		for !s.IsEmpty() {
			t, err = ParseTextBlocks(s, &body)
			if err != nil {
				return
			}
			if s.IsEmpty() {
				err = s.Error("unexpected end of input, expected a closing brace")
				return
			}
			switch t.kind {
			case TokRBrace:
				break loop
			case TokControl:
				node, parseErr := parseEnvOrCommand(s, t.name)
				if parseErr != nil {
					err = parseErr
					return
				}
				Push(&body, node)
			default:
				err = s.Errorf("unexpected token %v while parsing arguments", t)
				break loop
			}
		}
	case ArgTypeSym:
		text, scanErr := s.ScanSymbol()
		if scanErr != nil {
			err = scanErr
			return
		}
		body = []Node{text}
		err = s.Expect(TokRBrace)
		return
	case ArgTypeURL:
		text, scanErr := s.ScanURL()
		if scanErr != nil {
			err = scanErr
			return
		}
		body = []Node{text}
		err = s.Expect(TokRBrace)
		return
	case ArgTypeNum:
		text, scanErr := s.ScanNumber()
		if scanErr != nil {
			err = scanErr
			return
		}
		body = []Node{text}
		err = s.Expect(TokRBrace)
		return
	default:
		err = s.Errorf("unexpected arg type: %v", typ)
		return
	}
	return
}

func ParseCmd(s *stream, name sym, pos int) (cmd Cmd, err error) {
	opts, optsErr := parseOptions(s)
	if optsErr != nil {
		err = optsErr
		return
	}
	arity := CmdArity(name)
	args := make([][]Node, 0, arity)
	for i := 0; i < arity; i++ {
		arg, argErr := parseArg(s, CmdArgType(name, i))
		if argErr != nil {
			err = fmt.Errorf("%s:%d: failed to parse arg %d of command %s: %v", s.source, pos, i, SymbolName(name), argErr)
			return
		}
		Push(&args, arg)
	}
	cmd = Cmd{
		name: name,
		pos:  pos,
		opts: opts,
		args: args,
	}
	return
}

func parseEnvEnd(s *stream, beginSym sym, beginPos int) error {
	endPos := s.pos
	endSym, err := parseEnvName(s)
	if err != nil {
		return err
	}
	if endSym != beginSym {
		return s.Errorf("\\end{%s} at %d doesn't match the \\begin{%s} at %d", SymbolName(beginSym), beginPos, SymbolName(endSym), endPos)
	}
	return nil
}

func ParseVerbatim(s *stream, pos int) (env Env, err error) {
	textPos := s.pos
	body, verbErr := s.FindVerbatimEnd()
	if verbErr != nil {
		err = verbErr
		return
	}
	env = Env{
		beginPos: pos,
		endPos:   s.pos,
		body:     []Node{Text{pos: textPos, body: body}},
	}
	return
}

func ParseEnv(s *stream, name sym, pos int) (env Env, err error) {
	var body []Node
	var t token
	opts, err := parseOptions(s)
	if err != nil {
		return
	}
	if name == SymVerbatim {
		// The verbatim env is special
		return ParseVerbatim(s, pos)
	}
	if name == SymCode {
		// We don't want unnecessary empty newlines creaping into the rendered code.
		s.SkipNewline()
	}
loop:
	for !s.IsEmpty() {
		t, err = ParseTextBlocks(s, &body)
		if err != nil {
			return
		}
		if s.IsEmpty() {
			err = s.Error("unexpected end of input, expected \\end{" + SymbolName(name) + "}")
			return
		}
		switch t.kind {
		case TokControl:
			if t.name == SymEnd {
				// Found the closing marker, let's validate it.
				endPos := s.pos
				if endErr := parseEnvEnd(s, name, pos); endErr != nil {
					err = endErr
				}
				env = Env{
					name:     name,
					beginPos: pos,
					endPos:   endPos,
					opts:     opts,
					body:     body,
				}
				break loop
			}
			node, parseErr := parseEnvOrCommand(s, t.name)
			if parseErr != nil {
				err = parseErr
				return
			}
			Push(&body, node)
		case TokLBrace, TokRBrace, TokLBracket, TokRBracket:
			if name == SymCode {
				Push(&body, Node(Text{pos: s.pos - 1, body: t.body}))
			} else {
				err = s.Errorf("unexpected token %s while parsing %s", &t, SymbolName(name))
				break loop
			}
		default:
			err = s.Errorf("unexpected token %s while parsing %s", &t, SymbolName(name))
			break loop
		}
	}
	return
}

func ParseTextBlocks(s *stream, body *[]Node) (t token, err error) {
	for !s.IsEmpty() {
		p := s.pos
		if err = s.NextToken(&t); err != nil {
			return
		}
		if t.kind == TokText {
			Push(body, Node(Text{body: t.body, pos: p}))
		} else {
			return
		}
	}
	return
}

func parseEnvOrCommand(s *stream, cmd sym) (node Node, err error) {
	p := s.pos
	// Found the beginning of an environment.
	switch cmd {
	case SymBegin:
		beginSym, envNameErr := parseEnvName(s)
		if envNameErr != nil {
			err = envNameErr
			return
		}
		env, envErr := ParseEnv(s, beginSym, p)
		if envErr != nil {
			err = envErr
			return
		}
		return env, nil
	case SymEnd:
		err = s.Error("unbalanced \\end command")
		return
	default:
		cmd, cmdErr := ParseCmd(s, cmd, p)
		if cmdErr != nil {
			err = cmdErr
			return
		}
		return cmd, nil
	}
}

func ParseSequence(s *stream) (body []Node, err error) {
	var t token
	for !s.IsEmpty() {
		t, err = ParseTextBlocks(s, &body)
		if err != nil {
			return
		}
		if s.IsEmpty() {
			break
		}
		if t.kind == TokControl {
			node, parseErr := parseEnvOrCommand(s, t.name)
			if parseErr != nil {
				err = parseErr
				return
			}
			Push(&body, node)
		} else {
			err = s.Errorf("unexpected token: %s while parsing top-level document", &t)
			return
		}
	}
	return
}
