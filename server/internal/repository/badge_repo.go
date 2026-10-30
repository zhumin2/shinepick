package repository

import (
	"context"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"shinepick/internal/model"
)

// BadgeRepo 徽章数据访问（S7-02）。
type BadgeRepo struct{ db *gorm.DB }

func NewBadgeRepo(db *gorm.DB) *BadgeRepo { return &BadgeRepo{db: db} }

// AllBadges 全部徽章定义。
func (r *BadgeRepo) AllBadges(ctx context.Context) ([]*model.Badge, error) {
	var list []*model.Badge
	err := r.db.WithContext(ctx).Order("id ASC").Find(&list).Error
	return list, err
}

// OwnedBadgeMap 用户已获得徽章：badgeID → 获得时间。
func (r *BadgeRepo) OwnedBadgeMap(ctx context.Context, uid int64) (map[int64]time.Time, error) {
	var list []*model.UserBadge
	err := r.db.WithContext(ctx).Where("user_id = ?", uid).Find(&list).Error
	if err != nil {
		return nil, err
	}
	out := make(map[int64]time.Time, len(list))
	for _, ub := range list {
		out[ub.BadgeID] = ub.CreatedAt
	}
	return out, nil
}

// GrantBadges 授予徽章（幂等：唯一键冲突忽略），返回本次实际新获得的 badgeID。
func (r *BadgeRepo) GrantBadges(ctx context.Context, uid int64, badgeIDs []int64, checkinID *int64) ([]int64, error) {
	if len(badgeIDs) == 0 {
		return nil, nil
	}
	granted := make([]int64, 0, len(badgeIDs))
	for _, bid := range badgeIDs {
		ub := &model.UserBadge{UserID: uid, BadgeID: bid, CheckinID: checkinID}
		res := r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(ub)
		if res.Error != nil {
			return granted, res.Error
		}
		if res.RowsAffected > 0 {
			granted = append(granted, bid)
		}
	}
	return granted, nil
}
