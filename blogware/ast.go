package main

import (
	"fmt"
	"strings"
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
