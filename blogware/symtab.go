package main

type sym int

type ArgType int

const (
	ArgTypeSeq ArgType = iota
	ArgTypeSym
	ArgTypeNum
	ArgTypeURL
)

var (
	symTab          = make(map[string]sym, 1000)
	syms            = make([]string, 0, 1000)
	cmdArgTypes     = make(map[sym][]ArgType, 1000)
	nextSym     sym = 0

	// Builtin commands
	SymBegin           = BuiltinCmd("begin", ArgTypeSym)
	SymEnd             = BuiltinCmd("end", ArgTypeSym)
	SymVerbatim        = BuiltinEnv("verbatim")
	SymSection         = BuiltinCmd("section", ArgTypeSym, ArgTypeSeq)
	SymSubSection      = BuiltinCmd("subsection", ArgTypeSym, ArgTypeSeq)
	SymHref            = BuiltinCmd("href", ArgTypeURL, ArgTypeSeq)
	SymDocumentClass   = BuiltinCmd("documentclass", ArgTypeSym)
	SymIncludeGraphics = BuiltinCmd("includegraphics", ArgTypeSeq)
	SymDate            = BuiltinCmd("date", ArgTypeSym)
	SymModified        = BuiltinCmd("modified", ArgTypeSym)
	SymKeyword         = BuiltinCmd("keyword", ArgTypeSym)
	SymTitle           = BuiltinCmd("title", ArgTypeSeq)
	SymSubtitle        = BuiltinCmd("subtitle", ArgTypeSeq)
	SymBold            = BuiltinCmd("b", ArgTypeSeq)
	SymEmphasis        = BuiltinCmd("em", ArgTypeSeq)
	SymSmallCaps       = BuiltinCmd("sc", ArgTypeSeq)
	SymCircled         = BuiltinCmd("circled", ArgTypeNum)
	SymCode            = BuiltinCmd("code", ArgTypeSeq)
	SymItem            = BuiltinCmd("item")
	SymMath            = BuiltinCmd("math", ArgTypeSeq)
	SymSub             = BuiltinCmd("sub", ArgTypeSeq)
	SymSup             = BuiltinCmd("sup", ArgTypeSeq)
	SymQED             = BuiltinCmd("qed")
	SymAdvice          = BuiltinCmd("advice", ArgTypeSym, ArgTypeSeq)
	SymMarginNote      = BuiltinCmd("marginnote", ArgTypeSym, ArgTypeSeq)
	SymSideNote        = BuiltinCmd("sidenote", ArgTypeSym, ArgTypeSeq)
	SymLdots           = BuiltinCmd("ldots")
	SymNewline         = BuiltinCmd("newline")
	SymHRule           = BuiltinCmd("hrule")
	SymEpigraph        = BuiltinCmd("epigraph", ArgTypeSeq, ArgTypeSeq)
	SymBlockquote      = BuiltinCmd("blockquote", ArgTypeSeq, ArgTypeSeq)

	// Builtin environments
	SymDocument  = BuiltinEnv("document")
	SymAbstract  = BuiltinEnv("abstract")
	SymEnumerate = BuiltinEnv("enumerate")
	SymItemize   = BuiltinEnv("itemize")
	SymFigure    = BuiltinEnv("figure")
)

func BuiltinEnv(name string) sym {
	return Symbol(name)
}

func BuiltinCmd(name string, argTypes ...ArgType) sym {
	s := Symbol(name)
	cmdArgTypes[s] = argTypes
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
