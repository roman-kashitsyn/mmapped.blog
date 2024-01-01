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
	fmt.Fprintf(&buf, "Cmd { name: %s, opts: [", SymbolName(c.name))
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

type Cell struct {
	pos       int
	alignSpec ColSpec
	colspan   int
	body      []Node
}

type Row struct {
	borders RowBorder
	cells   []Cell
}

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
