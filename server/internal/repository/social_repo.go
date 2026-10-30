package repository

import (
	"context"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"shinepick/internal/model"
)

// SocialRepo 通知 / 拉黑 / 举报（S6）。
type SocialRepo struct{ db *gorm.DB }

func NewSocialRepo(db *gorm.DB) *SocialRepo { return &SocialRepo{db: db} }

// DB 暴露底层连接（少量跨表查询用）。
func (r *SocialRepo) DB() *gorm.DB { return r.db }

// ---- 通知 ----

// aggWindow 同类聚合窗口（技术文档 6.3：10 分钟）。
const aggWindow = 10 * time.Minute

// Notify 记录一条通知；同（接收者,类型,打卡,触发者）在聚合窗口内的未读通知合并计数。
// actorID 为 nil 表示匿名文案（非互相同路的点亮/拥抱）。
func (r *SocialRepo) Notify(ctx context.Context, n *model.Notification) error {
	windowStart := time.Now().Add(-aggWindow)
	var exist model.Notification
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND type = ? AND is_read = 0 AND created_at > ?"+
			" AND (checkin_id <=> ?) AND (actor_id <=> ?)",
			n.UserID, n.Type, windowStart, n.CheckinID, n.ActorID).
		First(&exist).Error
	if err == nil {
		return r.db.WithContext(ctx).Model(&model.Notification{}).
			Where("id = ?", exist.ID).
			Updates(map[string]interface{}{
				"agg_count":  exist.AggCount + 1,
				"created_at": time.Now(),
			}).Error
	}
	if err != gorm.ErrRecordNotFound {
		return err
	}
	// 显式 AggCount=1：GORM 会把零值也写入，不能依赖列默认值
	return r.db.WithContext(ctx).Create(&model.Notification{
		UserID: n.UserID, Type: n.Type, ActorID: n.ActorID,
		CheckinID: n.CheckinID, CommentID: n.CommentID, AggCount: 1,
	}).Error
}

// ListNotifications 通知列表（新→旧，游标分页）。
func (r *SocialRepo) ListNotifications(ctx context.Context, uid, cursor int64, limit int) ([]*model.Notification, error) {
	q := r.db.WithContext(ctx).Where("user_id = ?", uid)
	if cursor > 0 {
		q = q.Where("id < ?", cursor)
	}
	var list []*model.Notification
	err := q.Order("id DESC").Limit(limit).Find(&list).Error
	return list, err
}

// UnreadCount 未读通知数（铃铛角标，轻提示不做轰炸）。
func (r *SocialRepo) UnreadCount(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.Notification{}).
		Where("user_id = ? AND is_read = 0", uid).Count(&n).Error
	return n, err
}

// MarkAllRead 全部已读。
func (r *SocialRepo) MarkAllRead(ctx context.Context, uid int64) error {
	return r.db.WithContext(ctx).Model(&model.Notification{}).
		Where("user_id = ? AND is_read = 0", uid).Update("is_read", 1).Error
}

// ActorNicknames 批量取触发者昵称（匿名时调用方不查）。
func (r *SocialRepo) ActorNicknames(ctx context.Context, ids []int64) (map[int64]string, error) {
	out := map[int64]string{}
	if len(ids) == 0 {
		return out, nil
	}
	var rows []struct {
		ID       int64
		Nickname string
	}
	err := r.db.WithContext(ctx).Table("users").
		Select("id, nickname").Where("id IN ?", ids).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		out[row.ID] = row.Nickname
	}
	return out, nil
}

// ---- 拉黑 ----

// Block 拉黑（幂等）。
func (r *SocialRepo) Block(ctx context.Context, blocker, blocked int64) error {
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).
		Create(&model.Block{BlockerID: blocker, BlockedID: blocked}).Error
}

// Unblock 取消拉黑。
func (r *SocialRepo) Unblock(ctx context.Context, blocker, blocked int64) error {
	return r.db.WithContext(ctx).
		Where("blocker_id = ? AND blocked_id = ?", blocker, blocked).
		Delete(&model.Block{}).Error
}

// BlockedIDs 我拉黑的人。
func (r *SocialRepo) BlockedIDs(ctx context.Context, uid int64) (map[int64]bool, error) {
	var rows []int64
	err := r.db.WithContext(ctx).Model(&model.Block{}).
		Where("blocker_id = ?", uid).Pluck("blocked_id", &rows).Error
	if err != nil {
		return nil, err
	}
	set := make(map[int64]bool, len(rows))
	for _, id := range rows {
		set[id] = true
	}
	return set, nil
}

// BlockedByList 拉黑我的人（正确列方向）。
func (r *SocialRepo) BlockedByList(ctx context.Context, uid int64) (map[int64]bool, error) {
	var rows []int64
	err := r.db.WithContext(ctx).Model(&model.Block{}).
		Where("blocked_id = ?", uid).Pluck("blocker_id", &rows).Error
	if err != nil {
		return nil, err
	}
	set := make(map[int64]bool, len(rows))
	for _, id := range rows {
		set[id] = true
	}
	return set, nil
}

// IsBlocked 双向拉黑判断（a 拉黑 b 或 b 拉黑 a）。
func (r *SocialRepo) IsBlocked(ctx context.Context, a, b int64) (bool, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.Block{}).
		Where("(blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)", a, b, b, a).
		Count(&n).Error
	return n > 0, err
}

// ---- 举报 ----

// AddReport 记录举报。
func (r *SocialRepo) AddReport(ctx context.Context, rp *model.Report) error {
	return r.db.WithContext(ctx).Create(rp).Error
}
