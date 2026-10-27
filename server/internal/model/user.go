package model

import "time"

// User 用户主表（对齐迁移 0001_init.sql）。
type User struct {
	ID        int64      `gorm:"primaryKey;autoIncrement" json:"id"`
	PhoneHash string     `gorm:"column:phone_hash;uniqueIndex;size:64" json:"-"`
	Nickname  string     `gorm:"size:30" json:"nickname"`
	AvatarURL string     `gorm:"column:avatar_url;size:255" json:"avatar_url"`
	Bio       string     `gorm:"size:140" json:"bio"`
	Gender    int8       `json:"gender"`
	City      string     `gorm:"size:50" json:"city"`
	Birthday  *time.Time `json:"birthday,omitempty"`
	IsMinor   int8       `gorm:"column:is_minor" json:"-"`
	Status    int8       `json:"-"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"-"`
}

func (User) TableName() string { return "users" }

// UserSecure 用户敏感信息（手机号 AES 加密隔离存储）。
type UserSecure struct {
	UserID   int64  `gorm:"primaryKey" json:"-"`
	PhoneEnc []byte `gorm:"column:phone_enc" json:"-"`
	Salt     string `gorm:"size:32" json:"-"`
}

func (UserSecure) TableName() string { return "user_secure" }
