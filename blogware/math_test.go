package main

import (
	"io"
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
				{kind: MathTokNum, body: "1"},
				{kind: MathTokOp, body: "+"},
				{kind: MathTokNum, body: "20"},
			},
		},
		{
			input: "E = mc^2",
			toks: []mathToken{
				{kind: MathTokSym, body: "E"},
				{kind: MathTokOp, body: "="},
				{kind: MathTokSym, body: "m"},
				{kind: MathTokSym, body: "c"},
				{kind: MathTokSup, body: "^"},
				{kind: MathTokNum, body: "2"},
			},
		},
		{
			input: `\argmax`,
			toks: []mathToken{
				{kind: MathTokControl, name: Symbol("argmax")},
			},
		},
		{
			input: `\forall c_1, c_2 \in \mathbb{C}`,
			toks: []mathToken{
				{kind: MathTokControl, name: Symbol("forall")},
				{kind: MathTokSym, body: "c"},
				{kind: MathTokSub, body: "_"},
				{kind: MathTokNum, body: "1"},
				{kind: MathTokOp, body: ","},
				{kind: MathTokSym, body: "c"},
				{kind: MathTokSub, body: "_"},
				{kind: MathTokNum, body: "2"},
				{kind: MathTokControl, name: Symbol("in")},
				{kind: MathTokControl, name: Symbol("mathbb")},
				{kind: MathTokGroupStart, body: "{"},
				{kind: MathTokSym, body: "C"},
				{kind: MathTokGroupEnd, body: "}"},
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
					t.Errorf("%s: token %d: got %s, want %s", tc.input, i, &tok, &want)
				}
			}
			var tok mathToken
			if s.NextMathToken(&tok) != io.EOF {
				t.Errorf("expected EOF, got %+v", tok)
			}
		})
	}
}
