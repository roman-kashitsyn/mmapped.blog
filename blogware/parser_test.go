package main

import (
	"reflect"
	"testing"
)

func TestParsing(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []Node
	}{
		{
			name:  "no groups",
			input: `\b{hello world}`,
			expected: []Node{
				Cmd{
					pos:  0,
					name: SymBold,
					args: [][]Node{{Text{pos: 3, body: "hello world"}}},
				},
			},
		},
		{
			name:  "simple group",
			input: "{hello world}",
			expected: []Node{
				Group{
					pos:   0,
					nodes: []Node{Text{pos: 1, body: "hello world"}},
				},
			},
		},
		{
			name:  "group with command",
			input: `{text with \b{bold} inside}`,
			expected: []Node{
				Group{
					pos: 0,
					nodes: []Node{
						Text{pos: 1, body: "text with "},
						Cmd{
							pos:  11,
							name: SymBold,
							args: [][]Node{
								{Text{pos: 14, body: "bold"}},
							},
						},
						Text{pos: 19, body: " inside"},
					},
				},
			},
		},
		{
			name:  "command with multiple groups",
			input: `\b{bold text}{inside \b{nested}}`,
			expected: []Node{
				Cmd{
					pos:  0,
					name: SymBold,
					args: [][]Node{
						{Text{pos: 3, body: "bold text"}},
					},
				},
				Group{
					pos: 13,
					nodes: []Node{
						Text{pos: 14, body: "inside "},
						Cmd{
							pos:  21,
							name: SymBold,
							args: [][]Node{
								{Text{pos: 24, body: "nested"}},
							},
						},
					},
				},
			},
		},
		{
			name:  "nested groups",
			input: "{outer {inner text} more}",
			expected: []Node{
				Group{
					pos: 0,
					nodes: []Node{
						Text{pos: 1, body: "outer "},
						Group{
							pos: 7,
							nodes: []Node{
								Text{pos: 8, body: "inner text"},
							},
						},
						Text{pos: 19, body: " more"},
					},
				},
			},
		},
		{
			name:  "simple math formula",
			input: "$E = mc^2$",
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathText{contents: "E"},
						MathOp{op: "="},
						MathText{contents: "m"},
						MathTerm{
							pos:       6,
							nucleus:   MathText{contents: "c"},
							supscript: MathNum{num: "2"},
						},
					},
				},
			},
		},
		{
			name:  "simple math formula display mode",
			input: `\[E = mc^2\]`,
			expected: []Node{
				MathNode{
					display: true,
					pos:     0,
					mlist: []MathSubnode{
						MathText{contents: "E"},
						MathOp{op: "="},
						MathText{contents: "m"},
						MathTerm{
							pos:       7,
							nucleus:   MathText{contents: "c"},
							supscript: MathNum{num: "2"},
						},
					},
				},
			},
		},
		{
			name:  "subscript then superscript",
			input: "$m_i^j$",
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathTerm{
							pos:       1,
							nucleus:   MathText{contents: "m"},
							supscript: MathText{contents: "j"},
							subscript: MathText{contents: "i"},
						},
					},
				},
			},
		},
		{
			name:  "superscript then subscript",
			input: "$m^j_i$",
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathTerm{
							pos:       1,
							nucleus:   MathText{contents: "m"},
							supscript: MathText{contents: "j"},
							subscript: MathText{contents: "i"},
						},
					},
				},
			},
		},
		{
			name:  "eulers formula",
			input: `$e^{i\pi}=-1$`,
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathTerm{
							pos:     1,
							nucleus: MathText{contents: "e"},
							supscript: MathNode{
								pos: 3,
								mlist: []MathSubnode{
									MathText{contents: "i"},
									MathCmd{
										pos: 5,
										cmd: SymPi,
									},
								},
							},
						},
						MathOp{op: "="},
						MathOp{op: "-"}, // TODO: merge -1 into a single number
						MathNum{num: "1"},
					},
				},
			},
		},
		{
			name:  "fundamental theorem of calculus",
			input: `$\int_a^b f^\prime(x) dx = f(b) - f(a)$`,
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathTerm{
							pos:       1,
							nucleus:   MathCmd{pos: 1, cmd: SymInt},
							subscript: MathText{contents: "a"},
							supscript: MathText{contents: "b"},
						},
						MathTerm{
							pos:       10,
							nucleus:   MathText{contents: "f"},
							supscript: MathCmd{pos: 12, cmd: SymPrime},
						},
						MathOp{op: "("},
						MathText{contents: "x"},
						MathOp{op: ")"},
						MathText{contents: "d"},
						MathText{contents: "x"},
						MathOp{op: "="},
						MathText{contents: "f"},
						MathOp{op: "("},
						MathText{contents: "b"},
						MathOp{op: ")"},
						MathOp{op: "-"},
						MathText{contents: "f"},
						MathOp{op: "("},
						MathText{contents: "a"},
						MathOp{op: ")"},
					},
				},
			},
		},
		{
			name:  "binomial coefficient",
			input: `$\binom{n-1}{k}$`,
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathCmd{
							pos: 1,
							cmd: SymBinom,
							args: []MathSubnode{
								MathTerm{
									pos: 7,
									nucleus: MathNode{
										pos: 7,
										mlist: []MathSubnode{
											MathText{contents: "n"},
											MathOp{op: "-"},
											MathNum{num: "1"},
										},
									},
								},
								MathTerm{
									pos: 12,
									nucleus: MathNode{
										pos: 12,
										mlist: []MathSubnode{
											MathText{contents: "k"},
										},
									},
								},
							},
						},
					},
				},
			},
		},
		{

			name:  "operatorname max",
			input: `$\operatorname{max}\left(a, b\right)$`,
			expected: []Node{
				MathNode{
					pos: 0,
					mlist: []MathSubnode{
						MathCmd{
							pos:  1,
							cmd:  SymOpName,
							args: []MathSubnode{MathOp{op: "max"}},
						},
						MathCmd{pos: 19, cmd: SymMathLeft, args: []MathSubnode{MathOp{op: "(", stretchy: true}}},
						MathText{contents: "a"},
						MathOp{op: ","},
						MathText{contents: "b"},
						MathCmd{pos: 29, cmd: SymMathRight, args: []MathSubnode{MathOp{op: ")", stretchy: true}}},
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := StreamFromString(tt.input)
			nodes, err := ParseSequence(s)
			if err != nil {
				t.Fatalf("ParseSequence failed: %v", err)
			}

			if !reflect.DeepEqual(nodes, tt.expected) {
				t.Errorf("Expected to parse %q as:\n%+v\nGot:\n%+v", tt.input, tt.expected, nodes)
			}
		})
	}
}
