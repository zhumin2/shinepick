package service

import (
	"context"
	"time"

	"gorm.io/gorm"
)

// AdminService 运营接口（S8-01/S8-05）：精选管理 + 数据指标。
type AdminService struct {
	db   *gorm.DB
	feed *FeedService
}

func NewAdminService(db *gorm.DB, feed *FeedService) *AdminService {
	return &AdminService{db: db, feed: feed}
}

// StatsVO 内测数据面板（北极星：周打卡 ≥3 天用户占 WAU 比例）。
type StatsVO struct {
	UsersTotal    int64     `json:"users_total"`
	UsersNew7d    int64     `json:"users_new_7d"`
	CheckinsToday int64     `json:"checkins_today"`
	Checkins7d    int64     `json:"checkins_7d"`
	WAU           int64     `json:"wau"`
	PolarStarPct  float64   `json:"polar_star_pct"` // 周打卡≥3天用户 / WAU
	GeneratedAt   time.Time `json:"generated_at"`
}

// Stats 计算面板指标。
func (s *AdminService) Stats(ctx context.Context) (*StatsVO, error) {
	now := time.Now().In(cstZone)
	today := now.Format("2006-01-02")
	weekAgo := now.AddDate(0, 0, -7)

	out := &StatsVO{GeneratedAt: now}
	if err := s.db.WithContext(ctx).Table("users").Count(&out.UsersTotal).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("users").
		Where("created_at > ?", weekAgo).Count(&out.UsersNew7d).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("checkins").
		Where("status = 0 AND checkin_date = ?", today).
		Count(&out.CheckinsToday).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("checkins").
		Where("status = 0 AND created_at > ?", weekAgo).
		Count(&out.Checkins7d).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("checkins").
		Where("status = 0 AND created_at > ?", weekAgo).
		Distinct("user_id").Count(&out.WAU).Error; err != nil {
		return nil, err
	}
	// 北极星：近 7 天打卡 ≥3 个不同日期的用户数 / WAU
	var polar int64
	if err := s.db.WithContext(ctx).Table("checkins").
		Select("user_id").
		Where("status = 0 AND created_at > ?", weekAgo).
		Group("user_id").
		Having("COUNT(DISTINCT checkin_date) >= 3").
		Count(&polar).Error; err != nil {
		return nil, err
	}
	if out.WAU > 0 {
		out.PolarStarPct = float64(polar) / float64(out.WAU) * 100
	}
	return out, nil
}
