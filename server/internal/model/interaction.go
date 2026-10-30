package model

import "time"

// Reaction 情绪互动（对齐迁移 0003）。
type Reaction struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	CheckinID int64     `gorm:"column:checkin_id;uniqueIndex:uk_target,priority:1" json:"checkin_id"`
	UserID    int64     `gorm:"column:user_id;uniqueIndex:uk_target,priority:2;index:idx_user" json:"user_id"`
	Type      int8      `gorm:"uniqueIndex:uk_target,priority:3" json:"type"` // 1点亮 2拥抱 3同路
	CreatedAt time.Time `json:"created_at"`
}

func (Reaction) TableName() string { return "reactions" }

// Comment 小便签留言。
type Comment struct {
	ID         int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	CheckinID  int64     `gorm:"column:checkin_id;index:idx_checkin,priority:1" json:"checkin_id"`
	UserID     int64     `gorm:"column:user_id" json:"user_id"`
	Content    string    `gorm:"size:80" json:"content"`
	Status     int8      `json:"-"`                                     // 0正常 1已删 2审核拒绝
	IsFeatured int8      `gorm:"column:is_featured" json:"is_featured"` // 1=作者指定在卡片展示
	CreatedAt  time.Time `json:"created_at"`
}

func (Comment) TableName() string { return "comments" }

// CompanionRelation 同路人关系（约定 userA < userB）。
type CompanionRelation struct {
	ID              int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserA           int64     `gorm:"column:user_a;uniqueIndex:uk_pair,priority:1" json:"user_a"`
	UserB           int64     `gorm:"column:user_b;uniqueIndex:uk_pair,priority:2;index:idx_b,priority:1" json:"user_b"`
	SourceCheckinID int64     `gorm:"column:source_checkin_id" json:"source_checkin_id"`
	Status          int8      `json:"status"` // 0已同路 1已解除
	CreatedAt       time.Time `json:"created_at"`
}

func (CompanionRelation) TableName() string { return "companion_relations" }
