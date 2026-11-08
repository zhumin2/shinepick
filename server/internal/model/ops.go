package model

import "time"

// Feedback 意见反馈（v0.6.0 T8：设置页提交，运营面板查看）。
type Feedback struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    int64     `gorm:"column:user_id" json:"user_id"`
	Content   string    `gorm:"size:200" json:"content"`
	Status    int8      `json:"status"` // 0待处理 1已处理
	CreatedAt time.Time `json:"created_at"`
}

func (Feedback) TableName() string { return "feedback" }

// AdminAction 管理操作留底（v0.6.0 T9：封禁/下架/公告/举报处理可追溯）。
type AdminAction struct {
	ID         int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	Action     string    `gorm:"size:40" json:"action"`
	TargetType string    `gorm:"column:target_type;size:20" json:"target_type"`
	TargetID   int64     `gorm:"column:target_id" json:"target_id"`
	Detail     string    `gorm:"size:255" json:"detail"`
	CreatedAt  time.Time `json:"created_at"`
}

func (AdminAction) TableName() string { return "admin_actions" }
