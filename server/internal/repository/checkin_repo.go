package repository

import (
	"context"

	"gorm.io/gorm"

	"shinepick/internal/model"
)

// CheckinRepo 打卡数据访问。
type CheckinRepo struct{ db *gorm.DB }

func NewCheckinRepo(db *gorm.DB) *CheckinRepo { return &CheckinRepo{db: db} }

// CreateWithTx 在事务内写打卡并联动树进度（points+1 / year_count+1 / level 按 points 重算）。
// level 重算逻辑由 service 注入（阈值配置化），保证仓库层不含业务规则。
func (r *CheckinRepo) CreateWithTx(ctx context.Context, c *model.Checkin, bumpTree func(tx *gorm.DB, uid int64) error) (*model.Checkin, error) {
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(c).Error; err != nil {
			return err
		}
		return bumpTree(tx, c.UserID)
	})
	if err != nil {
		return nil, err
	}
	return c, nil
}

// ListByUser 某用户的打卡（游标分页，新→旧；仅自己视角含全部可见范围）。
func (r *CheckinRepo) ListByUser(ctx context.Context, uid int64, cursor int64, limit int) ([]*model.Checkin, error) {
	q := r.db.WithContext(ctx).Where("user_id = ? AND status = 0", uid)
	if cursor > 0 {
		q = q.Where("id < ?", cursor)
	}
	var list []*model.Checkin
	err := q.Order("id DESC").Limit(limit).Find(&list).Error
	return list, err
}

// ListPublic 他人视角：仅同路人可见（visibility=2）。
// v1「小树洞=关注者可见」在 S5 同路人体系上线后扩展。
func (r *CheckinRepo) ListPublic(ctx context.Context, uid int64, cursor int64, limit int) ([]*model.Checkin, error) {
	q := r.db.WithContext(ctx).Where("user_id = ? AND visibility = 2 AND status = 0", uid)
	if cursor > 0 {
		q = q.Where("id < ?", cursor)
	}
	var list []*model.Checkin
	err := q.Order("id DESC").Limit(limit).Find(&list).Error
	return list, err
}

// ByID 单条查询（含已删，供作者删除幂等与详情校验）。
func (r *CheckinRepo) ByID(ctx context.Context, id int64) (*model.Checkin, error) {
	var c model.Checkin
	err := r.db.WithContext(ctx).First(&c, id).Error
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// SoftDelete status 置 1（审计保留，技术文档 4.3）。
func (r *CheckinRepo) SoftDelete(ctx context.Context, id, uid int64) error {
	res := r.db.WithContext(ctx).Model(&model.Checkin{}).
		Where("id = ? AND user_id = ? AND status = 0", id, uid).
		Update("status", 1)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// TreeByUser 树进度（不存在返回零值+false）。
func (r *CheckinRepo) TreeByUser(ctx context.Context, uid int64) (*model.TreeProgress, bool, error) {
	var t model.TreeProgress
	err := r.db.WithContext(ctx).First(&t, uid).Error
	if err == gorm.ErrRecordNotFound {
		return &model.TreeProgress{UserID: uid, Level: 1}, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	return &t, true, nil
}

// CountByUser 用户累计有效打卡次数（每次打卡计数，不去重日期）。
func (r *CheckinRepo) CountByUser(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.Checkin{}).
		Where("user_id = ? AND status = 0", uid).
		Count(&n).Error
	return n, err
}

// DistinctDates 用户有打卡的日期（去重，新→旧），供资料页统计。
func (r *CheckinRepo) DistinctDates(ctx context.Context, uid int64, limit int) ([]string, error) {
	var dates []string
	err := r.db.WithContext(ctx).Model(&model.Checkin{}).
		Where("user_id = ? AND status = 0", uid).
		Distinct("checkin_date").
		Order("checkin_date DESC").
		Limit(limit).
		Pluck("checkin_date", &dates).Error
	return dates, err
}

// CheckinWithUser 打卡 + 作者信息（Feed/发现页用）。
type CheckinWithUser struct {
	model.Checkin
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
}

const withUserSelect = "`checkins`.*, `users`.`nickname` AS `nickname`, `users`.`avatar_url` AS `avatar_url`"

// ListTodayPublicByCategory 当天某品类的同路人可见打卡（含作者），排除指定用户，新→旧。
func (r *CheckinRepo) ListTodayPublicByCategory(ctx context.Context, date string, category int8, excludeUID int64, limit int) ([]*CheckinWithUser, error) {
	var list []*CheckinWithUser
	err := r.db.WithContext(ctx).Model(&model.Checkin{}).
		Select(withUserSelect).
		Joins("JOIN `users` ON `users`.`id` = `checkins`.`user_id`").
		Where("checkins.checkin_date = ? AND checkins.category = ? AND checkins.visibility = 2 AND checkins.status = 0 AND checkins.user_id <> ?",
			date, category, excludeUID).
		Order("checkins.id DESC").
		Limit(limit).
		Find(&list).Error
	return list, err
}

// ListDailyCandidates 每日精选候选：日期内同路人可见打卡（含作者），新→旧。
func (r *CheckinRepo) ListDailyCandidates(ctx context.Context, date string, limit int) ([]*CheckinWithUser, error) {
	var list []*CheckinWithUser
	err := r.db.WithContext(ctx).Model(&model.Checkin{}).
		Select(withUserSelect).
		Joins("JOIN `users` ON `users`.`id` = `checkins`.`user_id`").
		Where("checkins.checkin_date = ? AND checkins.visibility = 2 AND checkins.status = 0", date).
		Order("checkins.id DESC").
		Limit(limit).
		Find(&list).Error
	return list, err
}

// ListExplore 发现页：按品类（0=全部）游标分页，同路人可见。
func (r *CheckinRepo) ListExplore(ctx context.Context, category int8, cursor int64, limit int) ([]*CheckinWithUser, error) {
	q := r.db.WithContext(ctx).Model(&model.Checkin{}).
		Select(withUserSelect).
		Joins("JOIN `users` ON `users`.`id` = `checkins`.`user_id`").
		Where("checkins.visibility = 2 AND checkins.status = 0")
	if category > 0 {
		q = q.Where("checkins.category = ?", category)
	}
	if cursor > 0 {
		q = q.Where("checkins.id < ?", cursor)
	}
	var list []*CheckinWithUser
	err := q.Order("checkins.id DESC").Limit(limit).Find(&list).Error
	return list, err
}
