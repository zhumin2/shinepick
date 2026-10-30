package service

import (
	"context"
	"encoding/json"
	"time"

	"gorm.io/gorm"

	"shinepick/internal/model"
	"shinepick/internal/repository"
)

// TreeService 拾光树与徽章（S7）。
type TreeService struct {
	checkins *repository.CheckinRepo
	badges   *repository.BadgeRepo
	db       *gorm.DB
	social   *SocialService // 徽章获得通知（type 5 系统）
}

func NewTreeService(
	checkins *repository.CheckinRepo,
	badges *repository.BadgeRepo,
	db *gorm.DB,
	social *SocialService,
) *TreeService {
	return &TreeService{checkins: checkins, badges: badges, db: db, social: social}
}

// SeasonOf 东八区季节（技术文档 6.4：3-5 春 / 6-8 夏 / 9-11 秋 / 12-2 冬）。
func SeasonOf(now time.Time) int8 {
	m := now.In(cstZone).Month()
	switch {
	case m >= 3 && m <= 5:
		return 1
	case m >= 6 && m <= 8:
		return 2
	case m >= 9 && m <= 11:
		return 3
	default:
		return 4
	}
}

// LightPoint 树页光点（= 一次打卡，客户端按历史摆放）。
type LightPoint struct {
	Date     string `json:"date"`
	Category int8   `json:"category"`
}

// TreeVO GET /tree 响应。
type TreeVO struct {
	Level      int8         `json:"level"`
	Points     int32        `json:"points"`
	Season     int8         `json:"season"`
	YearCount  int32        `json:"year_count"`
	YearTarget int32        `json:"year_target"`
	StreakDays int          `json:"streak_days"`
	Total      int          `json:"total"`
	LightPoints []LightPoint `json:"light_points"`
}

// Tree 树状态：进度 + 季节 + 最近光点（技术文档 6.4：客户端按历史摆光点）。
func (s *TreeService) Tree(ctx context.Context, uid int64) (*TreeVO, error) {
	tree, _, err := s.checkins.TreeByUser(ctx, uid)
	if err != nil {
		return nil, err
	}
	dates, err := s.checkins.DistinctDates(ctx, uid, 400)
	if err != nil {
		dates = nil
	}
	_, streak := computeStreak(dates, time.Now().In(cstZone))
	total, _ := s.checkins.CountByUser(ctx, uid)

	now := time.Now().In(cstZone)
	vo := &TreeVO{
		Level:      tree.Level,
		Points:     tree.Points,
		Season:     SeasonOf(now),
		YearCount:  tree.YearCount,
		YearTarget: tree.YearTarget,
		StreakDays: streak,
		Total:      int(total),
		LightPoints: []LightPoint{},
	}
	// 光点历史：最近 100 条（性能兜底，技术文档 4.4）
	list, err := s.checkins.ListByUser(ctx, uid, 0, 100)
	if err == nil {
		for _, c := range list {
			vo.LightPoints = append(vo.LightPoints, LightPoint{
				Date: dateOnly(c.CheckinDate), Category: c.Category,
			})
		}
	}
	return vo, nil
}

// ---- 徽章 ----

// BadgeVO GET /badges 条目（已得/未得）。
type BadgeVO struct {
	Code        string     `json:"code"`
	Name        string     `json:"name"`
	Icon        string     `json:"icon"`
	Description string     `json:"description"`
	Owned       bool       `json:"owned"`
	EarnedAt    *time.Time `json:"earned_at,omitempty"`
}

// ListBadges 徽章列表（全量定义 + 是否拥有）。
func (s *TreeService) ListBadges(ctx context.Context, uid int64) ([]*BadgeVO, error) {
	defs, err := s.badges.AllBadges(ctx)
	if err != nil {
		return nil, err
	}
	owned, err := s.badges.OwnedBadgeMap(ctx, uid)
	if err != nil {
		return nil, err
	}
	out := make([]*BadgeVO, 0, len(defs))
	for _, d := range defs {
		vo := &BadgeVO{
			Code: d.Code, Name: d.Name, Icon: d.Icon,
			Description: d.Description,
		}
		if t, ok := owned[d.ID]; ok {
			vo.Owned = true
			tt := t
			vo.EarnedAt = &tt
		}
		out = append(out, vo)
	}
	return out, nil
}

// EvaluateBadges 按当前数据评估并授予徽章（发布打卡后调用，幂等）。
// 三类条件（技术文档 6.4）：连续 N 天 / 累计 N 次 / 品类累计 N 次。
func (s *TreeService) EvaluateBadges(ctx context.Context, uid int64, checkinID *int64) ([]*BadgeVO, error) {
	defs, err := s.badges.AllBadges(ctx)
	if err != nil {
		return nil, err
	}
	owned, err := s.badges.OwnedBadgeMap(ctx, uid)
	if err != nil {
		return nil, err
	}

	// 汇总数据：连续天数 / 总次数 / 各品类次数
	dates, _ := s.checkins.DistinctDates(ctx, uid, 400)
	_, streak := computeStreak(dates, time.Now().In(cstZone))
	total, _ := s.checkins.CountByUser(ctx, uid)
	catCount := map[int8]int{}
	list, err := s.checkins.ListByUser(ctx, uid, 0, 1000)
	if err == nil {
		for _, c := range list {
			catCount[c.Category]++
		}
	}

	grant := []int64{}
	for _, d := range defs {
		if _, have := owned[d.ID]; have {
			continue
		}
		var cond model.BadgeCondition
		if json.Unmarshal(d.ConditionJSON, &cond) != nil {
			continue
		}
		ok := false
		switch cond.Type {
		case "streak":
			ok = streak >= cond.Threshold
		case "total":
			ok = int(total) >= cond.Threshold
		case "category":
			ok = catCount[cond.Category] >= cond.Threshold
		}
		if ok {
			grant = append(grant, d.ID)
		}
	}
	granted, err := s.badges.GrantBadges(ctx, uid, grant, checkinID)
	if err != nil {
		return nil, err
	}
	// 新徽章 → 系统通知（type 5），文案温和不炫耀
	if s.social != nil {
		byID := map[int64]string{}
		for _, d := range defs {
			byID[d.ID] = d.Name
		}
		for _, bid := range granted {
			s.social.NotifySystem(ctx, uid, "获得新徽章：「"+byID[bid]+"」，它只挂在你自己的树上")
		}
	}
	return s.ListBadges(ctx, uid)
}
