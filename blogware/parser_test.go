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
		/*
			{
				name:  "subscript and superscript",
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
		*/
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
