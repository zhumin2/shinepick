package service

import (
	"testing"

	"shinepick/internal/model"
	"shinepick/internal/repository"
)

func cand(id int64, cat int8) *repository.CheckinWithUser {
	return &repository.CheckinWithUser{
		Checkin: model.Checkin{ID: id, Category: cat, Visibility: 2, Status: 0},
	}
}

// S4-01：每日精选规则——品类均衡轮转，单一品类不刷屏。
func TestSelectDaily(t *testing.T) {
	t.Run("品类均衡轮转", func(t *testing.T) {
		// 运动 3 条、阅读 2 条、旅行 1 条（id 新→旧）
		in := []*repository.CheckinWithUser{
			cand(1, 1), cand(2, 1), cand(3, 1),
			cand(4, 2), cand(5, 2),
			cand(6, 3),
		}
		got := selectDaily(in, 5)
		if len(got) != 5 {
			t.Fatalf("want 5 items, got %d", len(got))
		}
		cats := map[int8]int{}
		for _, c := range got {
			cats[c.Category]++
		}
		if cats[1] != 2 || cats[2] != 2 || cats[3] != 1 {
			t.Fatalf("品类应均衡轮转, got %v", cats)
		}
		// 轮转序应为 1,2,3,1,2（最新品类优先）
		wantOrder := []int64{1, 4, 6, 2, 5}
		for i, c := range got {
			if c.ID != wantOrder[i] {
				t.Fatalf("position %d: want id %d, got %d", i, wantOrder[i], c.ID)
			}
		}
	})
	t.Run("候选不足时全取", func(t *testing.T) {
		in := []*repository.CheckinWithUser{cand(1, 1), cand(2, 1)}
		got := selectDaily(in, 5)
		if len(got) != 2 {
			t.Fatalf("want 2, got %d", len(got))
		}
	})
	t.Run("空候选", func(t *testing.T) {
		if got := selectDaily(nil, 5); len(got) != 0 {
			t.Fatalf("want 0, got %d", len(got))
		}
	})
	t.Run("同品类保持新→旧", func(t *testing.T) {
		in := []*repository.CheckinWithUser{cand(9, 1), cand(3, 1), cand(7, 1)}
		got := selectDaily(in, 3)
		if got[0].ID != 9 || got[1].ID != 3 || got[2].ID != 7 {
			t.Fatalf("同品类内应按输入序（新→旧）: %v", got)
		}
	})
}
