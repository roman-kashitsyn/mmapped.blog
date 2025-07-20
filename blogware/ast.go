package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

type Node interface {
	String() string
}

// Cmd represents a command node (\cmd[opts]{arg}...).
type Cmd struct {
	pos  int
	name sym
	opts []sym
	args [][]Node
}

func (c *Cmd) ArgText(i int, dst *string) error {
	if len(c.args) <= i {
		return fmt.Errorf("expected the %s command to have at least %d arguments", SymbolName(c.name), i+1)
	}
	arg := c.args[i]
	if len(arg) != 1 {
		return fmt.Errorf("expected the %s command argument #%d to be one text node, got %s", SymbolName(c.name), i+1, arg)
	}
	switch v := arg[0].(type) {
	case Text:
		*dst = v.body
		return nil
	default:
		return fmt.Errorf("expected the %s command #%d argument to be one text node, got %s", SymbolName(c.name), i+1, arg)
	}
}

func (c *Cmd) HasOpt(opt string) (found bool) {
	sym := Symbol(opt)
	for _, c := range c.opts {
		if c == sym {
			found = true
		}
	}
	return
}

func (c *Cmd) ArgNum(i int, dst *int) error {
	var value string
	if err := c.ArgText(i, &value); err != nil {
		return err
	}
	n, err := strconv.Atoi(value)
	if err != nil {
		return fmt.Errorf("failed to parse integer from string %s: %w", value, err)
	}
	*dst = n
	return nil
}

func (c *Cmd) ArgDate(i int, dst *time.Time) error {
	var value string
	if err := c.ArgText(i, &value); err != nil {
		return err
	}
	t, err := time.Parse("2006-01-02", value)
	if err != nil {
		return fmt.Errorf("failed to parse date %s: %w", value, err)
	}
	*dst = t
	return nil
}

func (c *Cmd) ArgSeq(i int, dst *[]Node) error {
	if len(c.args) <= i {
		return fmt.Errorf("expected the %s command to have at least %d arguments", SymbolName(c.name), i+1)
	}
	*dst = c.args[i]
	return nil
}

func parseColSpecs(s string) (specs []ColSpec, err error) {
	for _, c := range s {
		switch c {
		case 'c':
			Push(&specs, ColSpecCenter)
		case 'l':
			Push(&specs, ColSpecLeft)
		case 'r':
			Push(&specs, ColSpecRight)
		case ' ':
			continue
		default:
			err = fmt.Errorf("unsupported alignment spec char %s", string(c))
		}
	}
	return
}

func (c *Cmd) ArgAlignSpec(i int, dst *[]ColSpec) error {
	var value string
	if err := c.ArgText(i, &value); err != nil {
		return err
	}
	specs, err := parseColSpecs(value)
	if err != nil {
		return err
	}
	*dst = specs
	return nil
}

func (c *Cmd) Name() string {
	return SymbolName(c.name)
}

func (c Cmd) String() string {
	var buf strings.Builder
	fmt.Fprintf(&buf, "Cmd { pos: %d, name: %s, opts: [", c.pos, SymbolName(c.name))
	for _, opt := range c.opts {
		fmt.Fprintf(&buf, "%s, ", SymbolName(opt))
	}
	buf.WriteString("], args: [")
	for _, arg := range c.args {
		fmt.Fprintf(&buf, "%s, ", arg)
	}
	buf.WriteString("]}")
	return buf.String()
}

// Env represents an environment node (\begin{env}[opts]...\end{env}).
type Env struct {
	beginPos int
	endPos   int
	name     sym
	opts     []sym
	body     []Node
}

func (env *Env) Name() string {
	return SymbolName(env.name)
}

func (env Env) String() string {
	var buf strings.Builder
	fmt.Fprintf(&buf, "Env { name: %s, span: [%d, %d], opts: [", SymbolName(env.name), env.beginPos, env.endPos)
	for _, opt := range env.opts {
		fmt.Fprintf(&buf, "%s, ", SymbolName(opt))
	}
	buf.WriteString("], body: [")
	for _, e := range env.body {
		fmt.Fprintf(&buf, "%s, ", e)
	}
	buf.WriteString("]}")
	return buf.String()
}

type Text struct {
	pos  int
	body string
}

func (t Text) String() string {
	return fmt.Sprintf("Text { pos: %d, body: %s }", t.pos, t.body)
}

// Group represents an arbitrary sequence of nodes.
type Group struct {
	pos   int
	nodes []Node
}

func (g Group) String() string {
	var buf strings.Builder
	fmt.Fprintf(&buf, "Group { pos: %d, nodes: [", g.pos)
	for _, node := range g.nodes {
		fmt.Fprintf(&buf, "%s, ", node)
	}
	buf.WriteString("]}")
	return buf.String()
}

type ColSpec int

const (
	ColSpecLeft ColSpec = iota
	ColSpecRight
	ColSpecCenter
)

type RowBorder int

const (
	BorderNone   RowBorder = 0
	BorderTop    RowBorder = 1
	BorderBottom RowBorder = 2
)

// Cell represents a cell within a table row.
type Cell struct {
	pos       int
	alignSpec ColSpec
	colspan   int
	body      []Node
}

// Row represents a row within a table.
type Row struct {
	borders RowBorder
	cells   []Cell
}

// Table represents a table node (\begin{tabular}[opts]{spec}...\end{tabular}).
type Table struct {
	name     sym
	beginPos int
	endPos   int
	opts     []sym
	spec     []ColSpec
	rows     []Row
}

func (t Table) String() string {
	return fmt.Sprintf("Table { beginPos: %d, endPos: %d, opts: %v, spec: %v, rows: %v}", t.beginPos, t.endPos, t.opts, t.spec, t.rows)
}

// MathNode represents a parsed math expression.
// See “TeX the Program”, p. 280 (#680, Data structures for math mode.).
type MathNode struct {
	pos   int
	mlist []MathSubnode
}

func (n MathNode) String() string {
	return fmt.Sprintf("MathNode { mlist: %+v }", n.mlist)
}

type MathSubnode any

// MathTerm represents a term with optional super- and subscripts.
type MathTerm struct {
	pos       int
	nucleus   MathSubnode
	subscript MathSubnode
	supscript MathSubnode
}

// MathFrac represents a fraction.
type MathFrac struct {
	nom   MathSubnode
	denom MathSubnode
}

// MathOp represents an operation in math mode.
type MathOp struct {
	op string
}

// MathNum represents a number in math mode.
type MathNum struct {
	num string
}

// MathText represents arbitrary text that should be rendered by itself.
// It corresponds to math identifiers.
type MathText struct {
	contents string
}
