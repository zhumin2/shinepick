package model

import "time"

// Badge 徽章定义。
type Badge struct {
	ID            int64          `gorm:"primaryKey;autoIncrement" json:"id"`
	Code          string         `gorm:"size:50;uniqueIndex" json:"code"`
	Name          string         `gorm:"size:30" json:"name"`
	Icon          string         `gorm:"size:30" json:"icon"`
	Description   string         `gorm:"size:140" json:"description"`
	ConditionJSON JSONRaw        `gorm:"column:condition_json;type:json" json:"-"`
}

func (Badge) TableName() string { return "badges" }

// BadgeCondition 徽章触发条件（condition_json 解析）。
type BadgeCondition struct {
	Type      string `json:"type"` // streak | total | category
	Category  int8   `json:"category,omitempty"`
	Threshold int    `json:"threshold"`
}

// UserBadge 用户已获得的徽章。
type UserBadge struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    int64     `gorm:"column:user_id;uniqueIndex:uk_user_badge,priority:1" json:"user_id"`
	BadgeID   int64     `gorm:"column:badge_id;uniqueIndex:uk_user_badge,priority:2;index:idx_badge" json:"badge_id"`
	CheckinID *int64    `gorm:"column:checkin_id" json:"checkin_id,omitempty"`
	CreatedAt time.Time `gorm:"column:created_at" json:"earned_at"`
}

func (UserBadge) TableName() string { return "user_badges" }
