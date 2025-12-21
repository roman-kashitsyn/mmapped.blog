package main

type sym int

type ArgType int

type MathArgType int

const (
	ArgTypeSeq ArgType = iota
	ArgTypeSym
	ArgTypeNum
	ArgTypeURL
	ArgTypeAlignSpec
)

const (
	MathArgExpr MathArgType = iota
	MathArgSym
)

var (
	symTab           = make(map[string]sym, 1000)
	syms             = make([]string, 0, 1000)
	cmdArgTypes      = make(map[sym][]ArgType, 1000)
	replacements     = make(map[sym]string, 1000)
	mathCmds         = make(map[sym][]MathArgType, 1000)
	mathOps          = make(map[sym]struct{}, 1000)
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
	SymHackernews      = BuiltinCmd("hackernews", ArgTypeURL)
	SymLobsters        = BuiltinCmd("lobsters", ArgTypeURL)
	SymDocumentClass   = BuiltinCmd("documentclass", ArgTypeSym)
	SymIncludeGraphics = BuiltinCmd("includegraphics", ArgTypeSeq)
	SymDate            = BuiltinCmd("date", ArgTypeSym)
	SymDetails         = BuiltinCmd("details", ArgTypeSeq, ArgTypeSeq)
	SymModified        = BuiltinCmd("modified", ArgTypeSym)
	SymKeyword         = BuiltinCmd("keyword", ArgTypeSym)
	SymTitle           = BuiltinCmd("title", ArgTypeSeq)
	SymSubtitle        = BuiltinCmd("subtitle", ArgTypeSeq)
	SymBold            = BuiltinCmd("b", ArgTypeSeq)
	SymUnderline       = BuiltinCmd("u", ArgTypeSeq)
	SymNormal          = BuiltinCmd("normal", ArgTypeSeq)
	SymEmphasis        = BuiltinCmd("emph", ArgTypeSeq)
	SymSmallCaps       = BuiltinCmd("textsc", ArgTypeSeq)
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
	SymKbd             = BuiltinCmd("kbd", ArgTypeSeq)
	SymNameref         = BuiltinCmd("nameref", ArgTypeSym)

	// Raw MathML support
	SymMathML        = BuiltinCmd("mathml", ArgTypeSeq)
	SymMathId        = BuiltinCmd("mi", ArgTypeSym)
	SymMathNum       = BuiltinCmd("mn", ArgTypeSeq)
	SymMathOp        = BuiltinCmd("mo", ArgTypeSeq)
	SymMathOpStar    = BuiltinCmd("mo*", ArgTypeSeq)
	SymMathSup       = BuiltinCmd("msup", ArgTypeSeq, ArgTypeSeq)
	SymMathSub       = BuiltinCmd("msub", ArgTypeSeq, ArgTypeSeq)
	SymMathText      = BuiltinCmd("mtext", ArgTypeSeq)
	SymMathRow       = BuiltinCmd("mrow", ArgTypeSeq)
	SymMathTable     = BuiltinCmd("mtable", ArgTypeAlignSpec, ArgTypeSeq)
	SymMathTableRow  = BuiltinCmd("mtr", ArgTypeSeq)
	SymMathTableCell = BuiltinCmd("mtd", ArgTypeSeq)
	SymMathUnderOver = BuiltinCmd("munderover", ArgTypeSeq, ArgTypeSeq, ArgTypeSeq)
	SymMathSubSup    = BuiltinCmd("msubsup", ArgTypeSeq, ArgTypeSeq, ArgTypeSeq)

	// Builtin replacement commands
	SymLdots          = BuiltinReplacement("ldots", "…")
	SymCdots          = BuiltinReplacement("cdots", "⋯")
	SymDelta          = BuiltinReplacement("delta", "δ")
	SymCapitalDelta   = BuiltinReplacement("Delta", "Δ")
	SymPi             = BuiltinReplacement("pi", "π")
	SymFracSlash      = BuiltinReplacement("fracslash", "∕")
	SymPrime          = BuiltinReplacement("prime", "'")
	SymTimes          = BuiltinReplacement("times", "×")
	SymInvisibleTimes = BuiltinReplacement("itimes", "&InvisibleTimes;")
	SymApplyFunction  = BuiltinReplacement("applyFun", "&ApplyFunction;")
	SymCirc           = BuiltinReplacement("circ", "∘")
	SymInSet          = BuiltinReplacement("in", "∈")
	SymNiSet          = BuiltinReplacement("ni", "∋")
	SymNotInSet       = BuiltinReplacement("notin", "∉")
	SymInf            = BuiltinReplacement("inf", "∞")
	SymNotNiSet       = BuiltinReplacement("notni", "∌")
	SymRightArrow     = BuiltinReplacement("rightarrow", "→")
	SymDRighAarrow    = BuiltinReplacement("Rightarrow", "⇒")
	SymLeftArrow      = BuiltinReplacement("leftarrow", "←")
	SymDLeftArrow     = BuiltinReplacement("Leftarrow", "⇐")
	SymSum            = BuiltinReplacement("sum", "&sum;")
	SymProd           = BuiltinReplacement("prod", "&prod;")
	SymInt            = BuiltinReplacement("int", "&int;")
	SymLim            = BuiltinReplacement("lim", "lim")
	SymLeq            = BuiltinReplacement("leq", "≤")
	SymIff            = BuiltinReplacement("iff", "⇔")

	// Builtin environments
	SymDocument    = BuiltinEnv("document")
	SymAbstract    = BuiltinEnv("abstract")
	SymEnumerate   = BuiltinEnv("enumerate")
	SymItemize     = BuiltinEnv("itemize")
	SymChecklist   = BuiltinEnv("checklist")
	SymFigure      = BuiltinEnv("figure")
	SymTabular     = BuiltinEnv("tabular")
	SymTabularS    = BuiltinEnv("tabular*")
	SymDescription = BuiltinEnv("description")

	// Builtin math commands
	SymFrac      = BuiltinMathCmd("frac", MathArgExpr, MathArgExpr)
	SymBinom     = BuiltinMathCmd("binom", MathArgExpr, MathArgExpr)
	SymOpName    = BuiltinMathCmd("operatorname", MathArgSym)
	SymMathLeft  = BuiltinMathCmd("left")
	SymMathRight = BuiltinMathCmd("right")

	mathOpList = []sym{
		SymInSet,
		SymNiSet,
		SymNotInSet,
		SymNotNiSet,
		SymRightArrow,
		SymDRighAarrow,
		SymLeftArrow,
		SymDLeftArrow,
		SymSum,
		SymLeq,
		SymIff,
	}
)

func init() {
	for _, s := range mathOpList {
		mathOps[s] = struct{}{}
	}
}

func BuiltinEnv(name string) sym {
	return Symbol(name)
}

func BuiltinCmd(name string, argTypes ...ArgType) sym {
	s := Symbol(name)
	cmdArgTypes[s] = argTypes
	return s
}

func BuiltinMathCmd(name string, argTypes ...MathArgType) sym {
	s := Symbol(name)
	mathCmds[s] = argTypes
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

func MathCmdArgTypes(name sym) []MathArgType {
	return mathCmds[name]
}

func FindReplacment(name sym) (replacement string, found bool) {
	replacement, found = replacements[name]
	return
}
