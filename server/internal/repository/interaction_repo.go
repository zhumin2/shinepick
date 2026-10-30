package repository

import (
	"context"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"shinepick/internal/model"
)

// InteractionRepo 互动/留言/同路人数据访问（S5）。
type InteractionRepo struct{ db *gorm.DB }

func NewInteractionRepo(db *gorm.DB) *InteractionRepo { return &InteractionRepo{db: db} }

// ---- reactions ----

// AddReaction 幂等添加互动（唯一键冲突时忽略）。
func (r *InteractionRepo) AddReaction(ctx context.Context, checkinID, userID int64, typ int8) error {
	rr := &model.Reaction{CheckinID: checkinID, UserID: userID, Type: typ}
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(rr).Error
}

// RemoveReaction 取消互动（幂等：不存在时无副作用）。
func (r *InteractionRepo) RemoveReaction(ctx context.Context, checkinID, userID int64, typ int8) error {
	return r.db.WithContext(ctx).
		Where("checkin_id = ? AND user_id = ? AND type = ?", checkinID, userID, typ).
		Delete(&model.Reaction{}).Error
}

// MyReactionTypes 某用户在一批打卡上的互动类型（feed 回填按钮态）。
func (r *InteractionRepo) MyReactionTypes(ctx context.Context, userID int64, checkinIDs []int64) (map[int64][]int8, error) {
	out := map[int64][]int8{}
	if len(checkinIDs) == 0 {
		return out, nil
	}
	var list []model.Reaction
	err := r.db.WithContext(ctx).
		Where("user_id = ? AND checkin_id IN ?", userID, checkinIDs).
		Find(&list).Error
	if err != nil {
		return nil, err
	}
	for _, rr := range list {
		out[rr.CheckinID] = append(out[rr.CheckinID], rr.Type)
	}
	return out, nil
}

// ---- comments ----

// CommentWithUser 留言 + 作者信息。
type CommentWithUser struct {
	model.Comment
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
}

// PreviewComments 批量取一批打卡的卡片展示留言（每条最多 per 条）。
// 排序：作者指定(is_featured) 优先，其次最新；按打卡分组后截断。
// 一次查询避免列表页 N+1。
func (r *InteractionRepo) PreviewComments(ctx context.Context, checkinIDs []int64, per int) (map[int64][]*CommentWithUser, error) {
	out := map[int64][]*CommentWithUser{}
	if len(checkinIDs) == 0 || per <= 0 {
		return out, nil
	}
	var list []*CommentWithUser
	err := r.db.WithContext(ctx).Model(&model.Comment{}).
		Select("`comments`.*, `users`.`nickname` AS `nickname`, `users`.`avatar_url` AS `avatar_url`").
		Joins("JOIN `users` ON `users`.`id` = `comments`.`user_id`").
		Where("comments.checkin_id IN ? AND comments.status = 0", checkinIDs).
		Order("comments.is_featured DESC, comments.id DESC").
		Limit(len(checkinIDs) * per * 4). // 上限保护：每条打卡最多留 4 倍余量
		Find(&list).Error
	if err != nil {
		return nil, err
	}
	for _, c := range list {
		group := out[c.CheckinID]
		if len(group) >= per {
			continue
		}
		out[c.CheckinID] = append(group, c)
	}
	return out, nil
}

// SetFeatured 设置/取消卡片的留言展示（仅打卡作者可调用，权限在 service 校验）。
func (r *InteractionRepo) SetFeatured(ctx context.Context, commentID int64, featured bool) error {
	v := int8(0)
	if featured {
		v = 1
	}
	return r.db.WithContext(ctx).Model(&model.Comment{}).
		Where("id = ? AND status = 0", commentID).
		Update("is_featured", v).Error
}

// AddComment 写入留言。
func (r *InteractionRepo) AddComment(ctx context.Context, c *model.Comment) error {
	return r.db.WithContext(ctx).Create(c).Error
}

// ListComments 某打卡的留言（新→旧，游标分页，不含已删；无 total——产品设计 4.6）。
func (r *InteractionRepo) ListComments(ctx context.Context, checkinID, cursor int64, limit int) ([]*CommentWithUser, error) {
	q := r.db.WithContext(ctx).Model(&model.Comment{}).
		Select("`comments`.*, `users`.`nickname` AS `nickname`, `users`.`avatar_url` AS `avatar_url`").
		Joins("JOIN `users` ON `users`.`id` = `comments`.`user_id`").
		Where("comments.checkin_id = ? AND comments.status = 0", checkinID)
	if cursor > 0 {
		q = q.Where("comments.id < ?", cursor)
	}
	var list []*CommentWithUser
	err := q.Order("comments.id DESC").Limit(limit).Find(&list).Error
	return list, err
}

// CommentByID 单条留言（删除鉴权用）。
func (r *InteractionRepo) CommentByID(ctx context.Context, id int64) (*model.Comment, error) {
	var c model.Comment
	err := r.db.WithContext(ctx).First(&c, id).Error
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// SoftDeleteComment status 置 1。
func (r *InteractionRepo) SoftDeleteComment(ctx context.Context, id int64) error {
	return r.db.WithContext(ctx).Model(&model.Comment{}).
		Where("id = ? AND status = 0", id).
		Update("status", 1).Error
}

// ---- companion_relations ----

// UpsertCompanion 建立同路关系（a<b 归一；已解除的重新激活）。
func (r *InteractionRepo) UpsertCompanion(ctx context.Context, userA, userB, sourceCheckinID int64) error {
	if userA > userB {
		userA, userB = userB, userA
	}
	rel := &model.CompanionRelation{
		UserA: userA, UserB: userB, SourceCheckinID: sourceCheckinID, Status: 0,
	}
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "user_a"}, {Name: "user_b"}},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"status": 0, "source_checkin_id": sourceCheckinID,
		}),
	}).Create(rel).Error
}

// CompanionCount 某用户的同路人数（我的页统计）。
func (r *InteractionRepo) CompanionCount(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.CompanionRelation{}).
		Where("status = 0 AND (user_a = ? OR user_b = ?)", uid, uid).
		Count(&n).Error
	return n, err
}

// MutualCompanion a 与 b 是否互为同路人（通知匿名化判断用，技术文档 6.3）。
func (r *InteractionRepo) MutualCompanion(ctx context.Context, a, b int64) (bool, error) {
	if a == b {
		return false, nil
	}
	lo, hi := a, b
	if lo > hi {
		lo, hi = hi, lo
	}
	var n int64
	err := r.db.WithContext(ctx).Model(&model.CompanionRelation{}).
		Where("user_a = ? AND user_b = ? AND status = 0", lo, hi).
		Count(&n).Error
	return n > 0, err
}
