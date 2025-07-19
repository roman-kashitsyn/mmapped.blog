package main

import (
	"testing"
)

func TestStreamLocate(t *testing.T) {
	tests := []struct {
		name  string
		input string
		pos   int
		want  Location
	}{
		// First line tests
		{
			name:  "first line, first character",
			input: "hello\nworld\ntest",
			pos:   0,
			want:  Location{Line: 1, Column: 1, SourceLine: "hello"},
		},
		{
			name:  "first line, middle character",
			input: "hello\nworld\ntest",
			pos:   2,
			want:  Location{Line: 1, Column: 3, SourceLine: "hello"},
		},
		{
			name:  "first line, last character",
			input: "hello\nworld\ntest",
			pos:   4,
			want:  Location{Line: 1, Column: 5, SourceLine: "hello"},
		},

		// Middle line tests
		{
			name:  "second line, first character",
			input: "hello\nworld\ntest",
			pos:   6,
			want:  Location{Line: 2, Column: 1, SourceLine: "world"},
		},
		{
			name:  "second line, middle character",
			input: "hello\nworld\ntest",
			pos:   8,
			want:  Location{Line: 2, Column: 3, SourceLine: "world"},
		},

		// Last line tests
		{
			name:  "last line, first character",
			input: "hello\nworld\ntest",
			pos:   12,
			want:  Location{Line: 3, Column: 1, SourceLine: "test"},
		},
		{
			name:  "last line, last character",
			input: "hello\nworld\ntest",
			pos:   15,
			want:  Location{Line: 3, Column: 4, SourceLine: "test"},
		},

		// No final newline tests
		{
			name:  "single line, no newline",
			input: "hello",
			pos:   2,
			want:  Location{Line: 1, Column: 3, SourceLine: "hello"},
		},
		{
			name:  "multiple lines, no final newline",
			input: "line1\nline2",
			pos:   8,
			want:  Location{Line: 2, Column: 3, SourceLine: "line2"},
		},

		// With final newline tests
		{
			name:  "with final newline, at newline",
			input: "hello\nworld\n",
			pos:   5,
			want:  Location{Line: 1, Column: 6, SourceLine: "hello"},
		},
		{
			name:  "with final newline, after last newline",
			input: "hello\nworld\n",
			pos:   12,
			want:  Location{Line: 3, Column: 1, SourceLine: ""},
		},

		// Unicode character tests
		{
			name:  "unicode first line",
			input: "café\nworld",
			pos:   2,
			want:  Location{Line: 1, Column: 3, SourceLine: "café"},
		},
		{
			name:  "unicode at é character",
			input: "café\nworld",
			pos:   3,
			want:  Location{Line: 1, Column: 4, SourceLine: "café"},
		},
		{
			name:  "unicode mixed characters",
			input: "🚀hello\n世界test",
			pos:   1,
			want:  Location{Line: 1, Column: 2, SourceLine: "🚀hello"},
		},
		{
			name:  "unicode second line multichar",
			input: "hello\nёчtest",
			pos:   8,
			want:  Location{Line: 2, Column: 2, SourceLine: "ёчtest"},
		},
		{
			name:  "unicode second line ascii",
			input: "hello\nёчtest",
			pos:   9,
			want:  Location{Line: 2, Column: 3, SourceLine: "ёчtest"},
		},
		{
			name:  "unicode emoji and text",
			input: "🎉🎊\ntest",
			pos:   2,
			want:  Location{Line: 1, Column: 2, SourceLine: "🎉🎊"},
		},

		// Edge cases
		{
			name:  "empty string",
			input: "",
			pos:   0,
			want:  Location{Line: 1, Column: 1, SourceLine: ""},
		},
		{
			name:  "only newlines",
			input: "\n\n\n",
			pos:   1,
			want:  Location{Line: 2, Column: 1, SourceLine: ""},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := StreamFromString(tt.input)
			got := s.locate(tt.pos)

			if got != tt.want {
				t.Errorf("locate(%d) = %+v, want %+v", tt.pos, got, tt.want)
			}
		})
	}
}
