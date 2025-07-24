package main

import (
	"strings"
	"unicode"
)

func Push[T any](stack *[]T, item T) {
	*stack = append(*stack, item)
}

func IsValidSymbol(s string) bool {
	return len(s) > 0 && !strings.ContainsFunc(s, func(c rune) bool { return !IsSymbolic(c) })
}

func IsSymbolic(c rune) bool {
	switch c {
	case '*', '-', '.':
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
	return parseArgWithBrace(s, typ, false)
}

func parseArgWithBrace(s *stream, typ ArgType, braceConsumed bool) (body []Node, err error) {
	var t token
	pos := s.pos
	if !braceConsumed {
		if err = s.NextToken(&t); err != nil {
			return
		}
		if t.kind != TokLBrace {
			err = s.ErrorfAt(pos, "Expected a {, got %v", t)
			return
		}
	}
	switch typ {
	case ArgTypeSeq:
	loop:
		for !s.IsEmpty() {
			t, err = ParseTextBlocks(s, &body)
			if err != nil {
				return
			}
			switch t.kind {
			case TokRBrace:
				break loop
			case TokControl:
				node, parseErr := parseEnvOrCommand(t.pos, s, t.name)
				if parseErr != nil {
					err = parseErr
					return
				}
				Push(&body, node)
			case TokLBrace:
				groupNodes, groupErr := parseArgWithBrace(s, ArgTypeSeq, true)
				if groupErr != nil {
					err = groupErr
					return
				}
				group := Group{pos: t.pos, nodes: groupNodes}
				Push(&body, Node(group))
			case TokInlineMath, TokDisplayMath:
				mathNode, mathErr := ParseMath(t, s)
				if mathErr != nil {
					err = mathErr
					return
				}
				Push(&body, Node(mathNode))
			case TokLBracket, TokRBracket:
				// Brackets are just brackets unless we're parsing options.
				Push(&body, Node(Text{body: t.body}))
			default:
				err = s.ErrorfAt(t.pos, "unexpected token %s while parsing arguments", &t)
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
	case ArgTypeAlignSpec:
		text, scanErr := s.ScanAlignSpec()
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
			err = s.ErrorfAt(pos, "failed to parse arg %d of command %s: %v", i, SymbolName(name), argErr)
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
		err := s.ErrorfAt(
			endPos,
			"\\end{%s} doesn't match \\begin{%s}",
			SymbolName(endSym),
			SymbolName(beginSym),
		)
		TryAddLocation(err, "Environment begin", s.locate(beginPos))
		return err
	}
	return nil
}

func ParseVerbatim(s *stream, name sym, opts []sym, pos int) (env Env, err error) {
	s.SkipNewline()
	textPos := s.pos
	body, verbErr := s.FindVerbatimEnd()
	if verbErr != nil {
		err = verbErr
		return
	}
	env = Env{
		name:     name,
		beginPos: pos,
		endPos:   s.pos,
		opts:     opts,
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
		return ParseVerbatim(s, name, opts, pos)
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
			node, parseErr := parseEnvOrCommand(t.pos, s, t.name)
			if parseErr != nil {
				err = parseErr
				return
			}
			Push(&body, node)
		case TokLBrace:
			if name == SymCode {
				Push(&body, Node(Text{pos: t.pos, body: t.body}))
			} else {
				// Parse the group content (brace already consumed)
				groupNodes, groupErr := parseArgWithBrace(s, ArgTypeSeq, true)
				if groupErr != nil {
					err = groupErr
					return
				}
				group := Group{pos: t.pos, nodes: groupNodes}
				Push(&body, Node(group))
			}
		case TokRBrace, TokLBracket, TokRBracket, TokAmp:
			if name == SymCode {
				Push(&body, Node(Text{pos: t.pos, body: t.body}))
			} else {
				err = s.ErrorfAt(t.pos, "unexpected token %s while parsing %s", &t, SymbolName(name))
				break loop
			}
		case TokInlineMath, TokDisplayMath:
			mnode, parseErr := ParseMath(t, s)
			if parseErr != nil {
				err = parseErr
				return
			}
			Push(&body, Node(mnode))
		default:
			err = s.ErrorfAt(t.pos, "unexpected token %s while parsing %s", &t, SymbolName(name))
			break loop
		}
	}
	return
}

func parseAlignSpec(s *stream) (spec []ColSpec, err error) {
	if err = s.Expect(TokLBrace); err != nil {
		return
	}
	var t token
	pos := s.pos
	if err = s.NextToken(&t); err != nil {
		return
	}
	if t.kind != TokText {
		err = s.ErrorfAt(pos, "expected a text token, got %v", &t)
		return
	}
	spec, err = parseColSpecs(t.body)
	if err != nil {
		err = s.ErrorfAt(pos, "failed to parse column alignment spec: %v", err)
		return
	}
	if err = s.Expect(TokRBrace); err != nil {
		return
	}
	return
}

func ParseTable(s *stream, name sym, pos int) (tab Table, err error) {
	var rows []Row
	var row Row
	var cell Cell
	cellCount := 1

	var t token
	opts, err := parseOptions(s)
	if err != nil {
		return
	}

	spec, err := parseAlignSpec(s)
	if err != nil {
		return
	}

	if len(spec) == 0 {
		err = s.ErrorfAt(pos, "empty cell alignment spec")
	}

	cell.alignSpec = spec[0]
	cell.colspan = 1

loop:
	for !s.IsEmpty() {
		tokPos := s.pos
		if err = s.NextToken(&t); err != nil {
			return
		}
		switch t.kind {
		case TokText:
			if t.body == "\\" {
				if cellCount != len(spec) {
					err = s.Errorf("row %d has %d cells (expected %d)", len(rows)+1, cellCount, len(spec))
					return
				}
				if len(cell.body) > 0 {
					Push(&row.cells, cell)
				}
				Push(&rows, row)
				cellCount = 1
				cell = Cell{pos: s.pos, alignSpec: spec[0], colspan: 1}
				row = Row{}
			} else {
				Push(&cell.body, Node(Text{pos: tokPos, body: t.body}))
			}
		case TokControl:
			switch t.name {
			case SymEnd:
				// Found the closing marker, let's validate it.
				endPos := s.pos
				if endErr := parseEnvEnd(s, name, pos); endErr != nil {
					err = endErr
				}
				// Check whether there is a pending \hrule that needs to become the bottom border.
				if row.borders != BorderNone && len(row.cells) == 0 && len(rows) > 0 {
					rows[len(rows)-1].borders |= BorderBottom
				}
				// Check whether the last row was properly closed.
				if len(row.cells) != 0 {
					err = s.ErrorfAt(endPos, "incomplete table row %d", len(rows)+1)
				}
				tab = Table{
					name:     name,
					spec:     spec,
					beginPos: pos,
					endPos:   endPos,
					opts:     opts,
					rows:     rows,
				}
				break loop
			case SymHRule:
				_, parseErr := parseEnvOrCommand(t.pos, s, t.name)
				if parseErr != nil {
					err = parseErr
					return
				}
				row.borders = BorderTop
			case SymMulticolumn:
				c, parseErr := parseEnvOrCommand(t.pos, s, t.name)
				if parseErr != nil {
					err = parseErr
					return
				}
				var numColumns int
				var alignSpec []ColSpec
				var body []Node
				cmd := c.(Cmd)
				if err = cmd.ArgNum(0, &numColumns); err != nil {
					return
				}
				if err = cmd.ArgAlignSpec(1, &alignSpec); err != nil {
					return
				}
				if len(alignSpec) != 1 {
					err = s.ErrorfAt(cmd.pos, "command %s align spec at position %d should have length 1", SymbolName(t.name), 1)
					return
				}
				if err = cmd.ArgSeq(2, &body); err != nil {
					return
				}

				cellCount += numColumns - 1
				Push(&row.cells, Cell{colspan: numColumns, pos: cmd.pos, alignSpec: alignSpec[0], body: body})
			default:
				node, parseErr := parseEnvOrCommand(t.pos, s, t.name)
				if parseErr != nil {
					err = parseErr
					return
				}
				Push(&cell.body, node)
			}
		case TokLBrace:
			// Parse the group content (brace already consumed)
			groupNodes, groupErr := parseArgWithBrace(s, ArgTypeSeq, true)
			if groupErr != nil {
				err = groupErr
				return
			}
			group := Group{pos: tokPos, nodes: groupNodes}
			Push(&cell.body, Node(group))
		case TokRBrace, TokLBracket, TokRBracket:
			err = s.ErrorfAt(tokPos, "unexpected token %s while parsing %s", &t, SymbolName(name))
			break loop
		case TokAmp:
			Push(&row.cells, cell)
			if cellCount >= len(spec) {
				err = s.ErrorfAt(tokPos, "too many cells in row %d: expected %d, got %d", len(rows)+1, len(spec), cellCount+1)
				return
			}
			cell = Cell{pos: s.pos, colspan: 1, alignSpec: spec[cellCount]}
			cellCount += 1
		default:
			err = s.ErrorfAt(tokPos, "unexpected token %s while parsing %s", &t, SymbolName(name))
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

func parseEnvOrCommand(pos int, s *stream, cmd sym) (node Node, err error) {
	// Found the beginning of an environment.
	switch cmd {
	case SymBegin:
		beginSym, envNameErr := parseEnvName(s)
		if envNameErr != nil {
			err = envNameErr
			return
		}
		if beginSym == SymTabular || beginSym == SymTabularS {
			tab, tabErr := ParseTable(s, beginSym, pos)
			if tabErr != nil {
				err = tabErr
				return
			}
			node = tab
			return
		}
		env, envErr := ParseEnv(s, beginSym, pos)
		if envErr != nil {
			err = envErr
			return
		}
		return env, nil
	case SymEnd:
		err = s.Error("unbalanced \\end command")
		return
	default:
		cmd, cmdErr := ParseCmd(s, cmd, pos)
		if cmdErr != nil {
			err = cmdErr
			return
		}
		return cmd, nil
	}
}

func simplifyTerm(term MathTerm) MathSubnode {
	if term.subscript == nil && term.supscript == nil {
		return term.nucleus
	}
	return term
}

func appendTerm(nodes []MathSubnode, term MathTerm) []MathSubnode {
	if term.nucleus != nil {
		return append(nodes, simplifyTerm(term))
	}
	return nodes
}

// parseMathTerm parses a math term starting with the specified math token.
// It leaves the first untouched math token in the tok argument.
func parseMathTerm(tok *mathToken, s *stream, subsup bool, end MathTokenKind) (term MathTerm, err error) {
	term.pos = tok.pos
	switch tok.kind {
	case MathTokNum:
		term.nucleus = MathNum{num: tok.body}
	case MathTokSym:
		term.nucleus = MathText{contents: tok.body}
	case MathTokOp:
		term.nucleus = MathOp{op: tok.body}
	case MathTokGroupStart:
		tokPos := tok.pos
		err = s.NextMathToken(tok)
		if err != nil {
			return
		}
		mterm, merr := parseMList(tok, s, MathTokGroupEnd)
		if merr != nil {
			err = merr
			return
		}
		mterm.pos = tokPos
		term.nucleus = mterm
	case MathTokControl:
		term.nucleus = MathCmd{
			pos: tok.pos,
			cmd: tok.name,
		}
	default:
		if tok.kind == end {
			return
		}
		err = s.ErrorfAt(tok.pos, "unexpected math token: %+v", tok)
		return
	}
	if !subsup {
		return
	}
	for tok.kind != end {
		err = s.NextMathToken(tok)
		if err != nil {
			return
		}
		if tok.kind == end {
			break
		}
		var subterm MathTerm
		switch tok.kind {
		case MathTokSub:
			if term.subscript != nil {
				err = s.ErrorfAt(tok.pos, "unexpected second subscript")
				return
			}
			err = s.NextMathToken(tok)
			if err != nil {
				return
			}
			subterm, err = parseMathTerm(tok, s, false, end)
			if err != nil {
				return
			}
			term.subscript = simplifyTerm(subterm)
		case MathTokSup:
			if term.supscript != nil {
				err = s.ErrorfAt(tok.pos, "unexpected second superscript")
				return
			}
			err = s.NextMathToken(tok)
			if err != nil {
				return
			}
			subterm, err = parseMathTerm(tok, s, false, end)
			if err != nil {
				return
			}
			term.supscript = simplifyTerm(subterm)
		default:
			return
		}
	}
	return
}

func parseMList(tok *mathToken, s *stream, end MathTokenKind) (node MathNode, err error) {
	node.pos = tok.pos
	for tok.kind != end {
		var mterm MathTerm
		switch tok.kind {
		case MathEndInlineMath:
			return
		case MathTokGroupStart:
			mterm, err = parseMathTerm(tok, s, true, MathTokGroupEnd)
			if err != nil {
				return
			}
		case MathTokGroupEnd:
			if end == MathTokGroupEnd {
				return
			}
			err = s.ErrorfAt(tok.pos, "unbalanced group")
			return
		default:
			mterm, err = parseMathTerm(tok, s, true, end)
			if err != nil {
				return
			}
		}
		node.mlist = appendTerm(node.mlist, mterm)
	}
	return
}

func ParseMath(t token, s *stream) (node MathNode, err error) {
	// TODO: handle negative numbers, e.g., f(-1), should render as mi{f}\mo{(}\mn{-1}\mo{)}
	//     ^ IDEA: write \num{-1} explicitly (as in https://ctan.org/pkg/siunitx package).
	// TODO: detect stretchy operators somehow.
	//     ^ IDEA: use '\left(' and '\right)' for stretchy operators.
	var endTokKind MathTokenKind
	display := false
	switch t.kind {
	case TokDisplayMath:
		endTokKind = MathEndDisplayMath
		display = true
	case TokInlineMath:
		endTokKind = MathEndInlineMath
	default:
		err = s.ErrorfAt(t.pos, "internal error: unexpected token in parse math: %s", &t)
		return
	}
	var mtok mathToken
	err = s.NextMathToken(&mtok)
	if err != nil {
		return
	}
	node, err = parseMList(&mtok, s, endTokKind)
	node.pos = t.pos
	node.display = display
	return
}

func ParseSequence(s *stream) (body []Node, err error) {
	var t token
	for !s.IsEmpty() {
		tokPos := s.pos
		t, err = ParseTextBlocks(s, &body)
		if err != nil {
			return
		}
		switch t.kind {
		case TokControl:
			node, parseErr := parseEnvOrCommand(t.pos, s, t.name)
			if parseErr != nil {
				err = parseErr
				return
			}
			Push(&body, node)
		case TokLBrace:
			// Parse the group content (brace already consumed)
			groupNodes, groupErr := parseArgWithBrace(s, ArgTypeSeq, true)
			if groupErr != nil {
				err = groupErr
				return
			}
			group := Group{pos: tokPos, nodes: groupNodes}
			Push(&body, Node(group))
		case TokInlineMath, TokDisplayMath:
			node, mathErr := ParseMath(t, s)
			if mathErr != nil {
				err = mathErr
				return
			}
			Push(&body, Node(node))
		case TokLBracket, TokRBracket:
			Push(&body, Node(Text{body: t.body}))
		case TokText:
			if s.IsEmpty() {
				// The last token parsed was a text token,
				// and there are no more tokens to parse.
				return
			}
			fallthrough
		default:
			err = s.ErrorfAt(tokPos, "unexpected token: %s while parsing top-level document", &t)
			return
		}
	}
	return
}
