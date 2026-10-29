package service

import (
	"strings"
	"testing"
	"time"

	"shinepick/internal/model"
)

// S2-01 DoD：未成年人标记逻辑单测（deriveMinor 边界）。
func TestDeriveMinor(t *testing.T) {
	cases := []struct {
		name      string
		birthday  string // YYYY-MM-DD
		now       string
		wantMinor int8
	}{
		{"刚满 18 周岁", "2008-10-29", "2026-10-29", 0},
		{"18 周岁前一天", "2008-10-30", "2026-10-29", 1},
		{"17 岁", "2009-01-01", "2026-10-29", 1},
		{"30 岁", "1996-06-01", "2026-10-29", 0},
		{"生日当天未到时辰也按日期算", "2008-10-29", "2026-10-29", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			bd, _ := time.ParseInLocation("2006-01-02", c.birthday, cstZone)
			now, _ := time.ParseInLocation("2006-01-02", c.now, cstZone)
			if got := deriveMinor(bd, now); got != c.wantMinor {
				t.Fatalf("deriveMinor(%s, %s) = %d, want %d", c.birthday, c.now, got, c.wantMinor)
			}
		})
	}
}

func strPtr(s string) *string { return &s }
func int8Ptr(i int8) *int8    { return &i }

func TestApplyPatchValidation(t *testing.T) {
	now, _ := time.ParseInLocation("2006-01-02", "2026-10-29", cstZone)

	t.Run("昵称为空被拒", func(t *testing.T) {
		u := &model.User{}
		if _, err := applyPatch(u, &ProfilePatch{Nickname: strPtr("  ")}, now); err == nil {
			t.Fatal("空白昵称应报错")
		}
	})
	t.Run("昵称超 30 字被拒", func(t *testing.T) {
		u := &model.User{}
		long := strings.Repeat("昵", 31)
		if _, err := applyPatch(u, &ProfilePatch{Nickname: strPtr(long)}, now); err == nil {
			t.Fatal("31 字昵称应报错")
		}
	})
	t.Run("昵称 30 字通过并去首尾空白", func(t *testing.T) {
		u := &model.User{}
		nick := strings.Repeat("昵", 30)
		changes, err := applyPatch(u, &ProfilePatch{Nickname: strPtr(" " + nick + " ")}, now)
		if err != nil {
			t.Fatalf("30 字昵称应通过: %v", err)
		}
		if u.Nickname != nick {
			t.Fatalf("应去除首尾空白，got %q", u.Nickname)
		}
		if changes["nickname"] != nick {
			t.Fatal("脏字段应包含 nickname")
		}
	})
	t.Run("bio 超 140 字被拒", func(t *testing.T) {
		u := &model.User{}
		if _, err := applyPatch(u, &ProfilePatch{Bio: strPtr(strings.Repeat("字", 141))}, now); err == nil {
			t.Fatal("141 字 bio 应报错")
		}
	})
	t.Run("性别取值不合法", func(t *testing.T) {
		u := &model.User{}
		if _, err := applyPatch(u, &ProfilePatch{Gender: int8Ptr(3)}, now); err == nil {
			t.Fatal("gender=3 应报错")
		}
	})
	t.Run("城市超 50 字被拒", func(t *testing.T) {
		u := &model.User{}
		if _, err := applyPatch(u, &ProfilePatch{City: strPtr(strings.Repeat("城", 51))}, now); err == nil {
			t.Fatal("51 字城市应报错")
		}
	})
	t.Run("生日格式错误被拒", func(t *testing.T) {
		u := &model.User{}
		if _, err := applyPatch(u, &ProfilePatch{Birthday: strPtr("2000/01/01")}, now); err == nil {
			t.Fatal("斜杠格式应报错")
		}
	})
	t.Run("生日晚于今天被拒", func(t *testing.T) {
		u := &model.User{}
		if _, err := applyPatch(u, &ProfilePatch{Birthday: strPtr("2027-01-01")}, now); err == nil {
			t.Fatal("未来生日应报错")
		}
	})
	t.Run("未成年生日联动 is_minor", func(t *testing.T) {
		u := &model.User{}
		changes, err := applyPatch(u, &ProfilePatch{Birthday: strPtr("2010-05-20")}, now)
		if err != nil {
			t.Fatalf("合法生日应通过: %v", err)
		}
		if u.IsMinor != 1 {
			t.Fatalf("2010 年出生应为未成年, got %d", u.IsMinor)
		}
		if changes["is_minor"] != int8(1) {
			t.Fatal("脏字段应包含 is_minor")
		}
	})
	t.Run("成年生日 is_minor=0", func(t *testing.T) {
		u := &model.User{IsMinor: 1}
		if _, err := applyPatch(u, &ProfilePatch{Birthday: strPtr("2000-01-01")}, now); err != nil {
			t.Fatalf("合法生日应通过: %v", err)
		}
		if u.IsMinor != 0 {
			t.Fatalf("成年应清除未成年标记, got %d", u.IsMinor)
		}
	})
	t.Run("nil patch 返回空脏字段", func(t *testing.T) {
		u := &model.User{Nickname: "原昵称"}
		changes, err := applyPatch(u, nil, now)
		if err != nil || len(changes) != 0 {
			t.Fatalf("nil patch 应无变更: changes=%v err=%v", changes, err)
		}
	})
	t.Run("未传字段不进脏集", func(t *testing.T) {
		u := &model.User{Nickname: "原昵称"}
		changes, err := applyPatch(u, &ProfilePatch{City: strPtr("杭州")}, now)
		if err != nil {
			t.Fatalf("应通过: %v", err)
		}
		if _, ok := changes["nickname"]; ok {
			t.Fatal("未传昵称不应出现在脏字段")
		}
	})
}

func TestAvatarExtWhitelist(t *testing.T) {
	cases := map[string]string{
		"a.jpg":  ".jpg",
		"a.JPEG": ".jpg",
		"a.png":  ".png",
		"a.webp": ".webp",
		"a.gif":  "",
		"a.exe":  "",
		"a":      "",
	}
	for name, want := range cases {
		if got := avatarExt(name); got != want {
			t.Fatalf("avatarExt(%q) = %q, want %q", name, got, want)
		}
	}
}

// S3 统计：打卡天数与连续天数（今天未打卡不断签，从昨天起算）。
func TestComputeStreak(t *testing.T) {
	now, _ := time.ParseInLocation("2006-01-02", "2026-10-30", cstZone)
	cases := []struct {
		name             string
		dates            []string
		wantDays, wantSt int
	}{
		{"无打卡", []string{}, 0, 0},
		{"仅今天", []string{"2026-10-30"}, 1, 1},
		{"今天断了但昨天有", []string{"2026-10-29"}, 1, 1},
		{"三天前打卡已断签", []string{"2026-10-27"}, 1, 0},
		{"今天+昨天", []string{"2026-10-30", "2026-10-29"}, 2, 2},
		{"昨天+前天（今天未打不断签）", []string{"2026-10-29", "2026-10-28"}, 2, 2},
		{"今天+隔一天断裂", []string{"2026-10-30", "2026-10-28", "2026-10-27"}, 3, 1},
		{"连续 5 天", []string{"2026-10-30", "2026-10-29", "2026-10-28", "2026-10-27", "2026-10-26"}, 5, 5},
		{"乱序输入也安全", []string{"2026-10-27", "2026-10-30", "2026-10-29", "2026-10-28"}, 4, 4},
		{"RFC3339 全格式归一化", []string{"2026-10-30T00:00:00+08:00", "2026-10-29T00:00:00+08:00"}, 2, 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			days, st := computeStreak(c.dates, now)
			if days != c.wantDays || st != c.wantSt {
				t.Fatalf("computeStreak(%v) = (%d, %d), want (%d, %d)",
					c.dates, days, st, c.wantDays, c.wantSt)
			}
		})
	}
}
