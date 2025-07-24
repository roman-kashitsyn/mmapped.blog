package main

import (
	"testing"
)

func TestMathScanner(t *testing.T) {
	for _, tc := range []struct {
		input string
		toks  []mathToken
	}{
		{
			input: "1 + 20",
			toks: []mathToken{
				{pos: 0, kind: MathTokNum, body: "1"},
				{pos: 2, kind: MathTokOp, body: "+"},
				{pos: 4, kind: MathTokNum, body: "20"},
			},
		},
		{
			input: "E = mc^2",
			toks: []mathToken{
				{pos: 0, kind: MathTokSym, body: "E"},
				{pos: 2, kind: MathTokOp, body: "="},
				{pos: 4, kind: MathTokSym, body: "m"},
				{pos: 5, kind: MathTokSym, body: "c"},
				{pos: 6, kind: MathTokSup, body: "^"},
				{pos: 7, kind: MathTokNum, body: "2"},
			},
		},
		{
			input: `\argmax`,
			toks: []mathToken{
				{pos: 0, kind: MathTokControl, name: Symbol("argmax")},
			},
		},
		{
			input: `\forall c_1, c_2 \in \mathbb{C}`,
			toks: []mathToken{
				{pos: 0, kind: MathTokControl, name: Symbol("forall")},
				{pos: 8, kind: MathTokSym, body: "c"},
				{pos: 9, kind: MathTokSub, body: "_"},
				{pos: 10, kind: MathTokNum, body: "1"},
				{pos: 11, kind: MathTokOp, body: ","},
				{pos: 13, kind: MathTokSym, body: "c"},
				{pos: 14, kind: MathTokSub, body: "_"},
				{pos: 15, kind: MathTokNum, body: "2"},
				{pos: 17, kind: MathTokControl, name: SymInSet},
				{pos: 21, kind: MathTokControl, name: Symbol("mathbb")},
				{pos: 28, kind: MathTokGroupStart, body: "{"},
				{pos: 29, kind: MathTokSym, body: "C"},
				{pos: 30, kind: MathTokGroupEnd, body: "}"},
			},
		},
		{
			input: `e^{i\pi}=-1`,
			toks: []mathToken{
				{pos: 0, kind: MathTokSym, body: "e"},
				{pos: 1, kind: MathTokSup, body: "^"},
				{pos: 2, kind: MathTokGroupStart, body: "{"},
				{pos: 3, kind: MathTokSym, body: "i"},
				{pos: 4, kind: MathTokControl, name: SymPi},
				{pos: 7, kind: MathTokGroupEnd, body: "}"},
				{pos: 8, kind: MathTokOp, body: "="},
				{pos: 9, kind: MathTokOp, body: "-"},
				{pos: 10, kind: MathTokNum, body: "1"},
			},
		},
	} {
		t.Run(tc.input, func(t *testing.T) {
			s := StreamFromString(tc.input)
			for i, want := range tc.toks {
				var tok mathToken
				err := s.NextMathToken(&tok)
				if err != nil {
					t.Errorf("failed to parse %s: unexpected error: %v", tc.input, err)
					break
				}
				if tok != want {
					t.Errorf("%s: token %d: got %+v, want %+v", tc.input, i, tok, want)
				}
			}
			var tok mathToken
			if s.NextMathToken(&tok) == nil {
				t.Errorf("expected EOF, got %+v", tok)
			}
		})
	}
}
