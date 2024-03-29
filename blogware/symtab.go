package main

type sym int

type ArgType int

const (
	ArgTypeSeq ArgType = iota
	ArgTypeSym
	ArgTypeNum
	ArgTypeURL
	ArgTypeAlignSpec
)

var (
	symTab           = make(map[string]sym, 1000)
	syms             = make([]string, 0, 1000)
	cmdArgTypes      = make(map[sym][]ArgType, 1000)
	replacements     = make(map[sym]string, 1000)
	nextSym      sym = 0

	// Builtin commands
	SymBegin           = BuiltinCmd("begin", ArgTypeSym)
	SymEnd             = BuiltinCmd("end", ArgTypeSym)
	SymLabel           = BuiltinCmd("label", ArgTypeSym)
	SymDingbat         = BuiltinCmd("dingbat", ArgTypeSym)
	SymVerbatim        = BuiltinEnv("verbatim")
	SymSection         = BuiltinCmd("section", ArgTypeSym, ArgTypeSeq)
	SymSectionS        = BuiltinCmd("section*")
	SymSubSection      = BuiltinCmd("subsection", ArgTypeSym, ArgTypeSeq)
	SymHref            = BuiltinCmd("href", ArgTypeURL, ArgTypeSeq)
	SymReddit          = BuiltinCmd("reddit", ArgTypeURL)
	SymDocumentClass   = BuiltinCmd("documentclass", ArgTypeSym)
	SymIncludeGraphics = BuiltinCmd("includegraphics", ArgTypeSeq)
	SymDate            = BuiltinCmd("date", ArgTypeSym)
	SymModified        = BuiltinCmd("modified", ArgTypeSym)
	SymKeyword         = BuiltinCmd("keyword", ArgTypeSym)
	SymTitle           = BuiltinCmd("title", ArgTypeSeq)
	SymSubtitle        = BuiltinCmd("subtitle", ArgTypeSeq)
	SymBold            = BuiltinCmd("b", ArgTypeSeq)
	SymUnderline       = BuiltinCmd("u", ArgTypeSeq)
	SymNormal          = BuiltinCmd("normal", ArgTypeSeq)
	SymEmphasis        = BuiltinCmd("em", ArgTypeSeq)
	SymSmallCaps       = BuiltinCmd("sc", ArgTypeSeq)
	SymCircled         = BuiltinCmd("circled", ArgTypeNum)
	SymCode            = BuiltinCmd("code", ArgTypeSeq)
	SymCenter          = BuiltinCmd("center", ArgTypeSeq)
	SymItem            = BuiltinCmd("item")
	SymMath            = BuiltinCmd("math", ArgTypeSeq)
	SymSub             = BuiltinCmd("sub", ArgTypeSeq)
	SymSup             = BuiltinCmd("sup", ArgTypeSeq)
	SymFun             = BuiltinCmd("fun", ArgTypeSeq)
	SymStrikethrough   = BuiltinCmd("strikethrough", ArgTypeSeq)
	SymQED             = BuiltinCmd("qed")
	SymAdvice          = BuiltinCmd("advice", ArgTypeSym, ArgTypeSeq)
	SymMarginNote      = BuiltinCmd("marginnote", ArgTypeSym, ArgTypeSeq)
	SymSideNote        = BuiltinCmd("sidenote", ArgTypeSym, ArgTypeSeq)
	SymNewline         = BuiltinCmd("newline")
	SymNumspace        = BuiltinCmd("numspace")
	SymHRule           = BuiltinCmd("hrule")
	SymEpigraph        = BuiltinCmd("epigraph", ArgTypeSeq, ArgTypeSeq)
	SymBlockquote      = BuiltinCmd("blockquote", ArgTypeSeq, ArgTypeSeq)
	SymMulticolumn     = BuiltinCmd("multicolumn", ArgTypeNum, ArgTypeAlignSpec, ArgTypeSeq)
	SymTerm            = BuiltinCmd("term", ArgTypeSeq, ArgTypeSeq)

	// Builtin replacement commands
	SymLdots        = BuiltinReplacement("ldots", "…")
	SymCdots        = BuiltinReplacement("cdots", "⋯")
	SymDelta        = BuiltinReplacement("delta", "δ")
	SymCapitalDelta = BuiltinReplacement("Delta", "Δ")
	SymFracSlash    = BuiltinReplacement("fracslash", "∕")
	SymTimes        = BuiltinReplacement("times", "×")

	// Builtin environments
	SymDocument    = BuiltinEnv("document")
	SymAbstract    = BuiltinEnv("abstract")
	SymEnumerate   = BuiltinEnv("enumerate")
	SymItemize     = BuiltinEnv("itemize")
	SymFigure      = BuiltinEnv("figure")
	SymTabular     = BuiltinEnv("tabular")
	SymTabularS    = BuiltinEnv("tabular*")
	SymDescription = BuiltinEnv("description")
)

func BuiltinEnv(name string) sym {
	return Symbol(name)
}

func BuiltinCmd(name string, argTypes ...ArgType) sym {
	s := Symbol(name)
	cmdArgTypes[s] = argTypes
	return s
}

func BuiltinReplacement(name, replacement string) sym {
	s := Symbol(name)
	replacements[s] = replacement
	return s
}

func Symbol(name string) sym {
	if n, found := symTab[name]; found {
		return n
	}
	n := nextSym
	nextSym += 1
	symTab[name] = n
	syms = append(syms, name)
	return n
}

func SymbolName(s sym) string {
	return syms[s]
}

func CmdArity(name sym) int {
	return len(cmdArgTypes[name])
}

func CmdArgType(name sym, pos int) ArgType {
	return cmdArgTypes[name][pos]
}

func FindReplacment(name sym) (replacement string, found bool) {
	replacement, found = replacements[name]
	return
}
