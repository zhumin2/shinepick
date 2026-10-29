package repository

import (
	"context"

	"gorm.io/gorm"

	"shinepick/internal/model"
)

// UserRepo 用户数据访问。
type UserRepo struct{ db *gorm.DB }

func NewUserRepo(db *gorm.DB) *UserRepo { return &UserRepo{db: db} }

func (r *UserRepo) ByPhoneHash(ctx context.Context, hash string) (*model.User, error) {
	var u model.User
	err := r.db.WithContext(ctx).Where("phone_hash = ?", hash).First(&u).Error
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (r *UserRepo) Create(ctx context.Context, u *model.User, secure *model.UserSecure) error {
	// 事务：用户 + 敏感信息必须同生同灭
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(u).Error; err != nil {
			return err
		}
		if secure != nil {
			secure.UserID = u.ID
			if err := tx.Create(secure).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *UserRepo) ByID(ctx context.Context, id int64) (*model.User, error) {
	var u model.User
	err := r.db.WithContext(ctx).First(&u, id).Error
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// UpdateFields 按脏字段更新（map 形式避开 GORM 结构体零值跳过问题）。
func (r *UserRepo) UpdateFields(ctx context.Context, id int64, fields map[string]interface{}) error {
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", id).Updates(fields).Error
}
