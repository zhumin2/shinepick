package service

import (
	"testing"
)

// S5-02：留言内容的空白归一（首尾空白与全角空格不占字数）。
func TestTrimSpace(t *testing.T) {
	cases := map[string]string{
		"  你好  ":   "你好",
		"\t\n你好\n": "你好",
		"　全角空格　":   "全角空格",
		"中间 空格保留":  "中间 空格保留",
		"":         "",
		"   ":      "",
		"a":        "a",
	}
	for in, want := range cases {
		if got := trimSpace(in); got != want {
			t.Fatalf("trimSpace(%q) = %q, want %q", in, got, want)
		}
	}
}
