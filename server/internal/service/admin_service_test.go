package service

import (
	"testing"

	"shinepick/internal/pkg/code"
)

// v0.6.0 T5/T7：DATE 列扫描可能带出 RFC3339 长串（踩坑 12），trimDate 必须取前 10 位。
func TestTrimDate(t *testing.T) {
	cases := []struct{ in, want string }{
		{"2026-11-08", "2026-11-08"},
		{"2026-11-08T00:00:00+08:00", "2026-11-08"},
		{"2026-11-08 00:00:00", "2026-11-08"},
		{"", ""},
		{"short", "short"},
	}
	for _, c := range cases {
		if got := trimDate(c.in); got != c.want {
			t.Fatalf("trimDate(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// v0.6.0 T2：封禁错误码 5003 有客户端可展示文案。
func TestBannedCodeMessage(t *testing.T) {
	if got := code.Message(code.ErrBanned); got != "账号已被封禁" {
		t.Fatalf("Message(5003) = %q, want 账号已被封禁", got)
	}
}
