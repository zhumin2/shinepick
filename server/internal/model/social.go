package model

import "time"

// Notification 应用内通知（对齐迁移 0005）。
type Notification struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    int64     `gorm:"column:user_id;index:idx_user_read,priority:1" json:"user_id"`
	Type      int8      `json:"type"` // 1点亮 2拥抱 3同路 4留言 5系统
	ActorID   *int64    `gorm:"column:actor_id" json:"actor_id,omitempty"`
	CheckinID *int64    `gorm:"column:checkin_id" json:"checkin_id,omitempty"`
	CommentID *int64    `gorm:"column:comment_id" json:"comment_id,omitempty"`
	AggCount  int32     `gorm:"column:agg_count" json:"agg_count"`
	Extra     string    `gorm:"column:extra;size:140" json:"extra,omitempty"` // type=5 系统文案
	IsRead    int8      `gorm:"column:is_read" json:"is_read"`
	CreatedAt time.Time `json:"created_at"`
}

func (Notification) TableName() string { return "notifications" }

// Block 拉黑。
type Block struct {
	ID        int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	BlockerID int64     `gorm:"column:blocker_id;uniqueIndex:uk_pair,priority:1" json:"blocker_id"`
	BlockedID int64     `gorm:"column:blocked_id;uniqueIndex:uk_pair,priority:2;index:idx_blocked" json:"blocked_id"`
	CreatedAt time.Time `json:"created_at"`
}

func (Block) TableName() string { return "blocks" }

// Report 举报。
type Report struct {
	ID         int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	ReporterID int64     `gorm:"column:reporter_id;index:idx_reporter" json:"reporter_id"`
	TargetType int8      `json:"target_type"` // 1打卡 2留言 3用户
	TargetID   int64     `json:"target_id"`
	Reason     int8      `json:"reason"`
	Detail     string    `gorm:"size:255" json:"detail"`
	Status     int8      `json:"-"` // 0待处理 1已处理 2驳回
	CreatedAt  time.Time `json:"created_at"`
}

func (Report) TableName() string { return "reports" }
