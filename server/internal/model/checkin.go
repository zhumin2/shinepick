package model

import (
	"encoding/json"
	"time"
)

// Checkin 打卡主表（对齐迁移 0002 / 技术文档 4.2）。
type Checkin struct {
	ID          int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID      int64     `gorm:"column:user_id;index:idx_user_date,priority:1" json:"-"`
	Category    int8      `json:"category"` // 1运动 2阅读 3旅行 4社交 5宠物 6自定义
	Content     string    `gorm:"size:500" json:"content"`
	ImageURLs   JSONRaw   `gorm:"column:image_urls;type:json" json:"image_urls"` // JSON 数组字符串，如 ["..."]
	VideoURL    string    `gorm:"column:video_url;size:255" json:"video_url,omitempty"`
	Visibility  int8      `json:"visibility"` // 1仅自己 2同路人 3小树洞
	Extra       JSONRaw   `gorm:"type:json" json:"extra,omitempty"`
	CheckinDate string    `gorm:"column:checkin_date;index" json:"checkin_date"` // YYYY-MM-DD（东八区归属日）
	Status      int8      `json:"-"`                                             // 0正常 1已删 2审核中 3拒绝
	CreatedAt   time.Time `json:"created_at"`
}

func (Checkin) TableName() string { return "checkins" }

// JSONRaw 原始 JSON 文本的 []byte 适配（gorm 标准模式，nil → NULL）。
type JSONRaw []byte

func (j JSONRaw) Value() (interface{}, error) {
	if len(j) == 0 {
		return nil, nil
	}
	return string(j), nil
}

func (j *JSONRaw) Scan(v interface{}) error {
	switch raw := v.(type) {
	case nil:
		*j = nil
	case []byte:
		*j = append((*j)[:0], raw...)
	case string:
		*j = JSONRaw(raw)
	}
	return nil
}

func (j JSONRaw) MarshalJSON() ([]byte, error) {
	if len(j) == 0 {
		return []byte("null"), nil
	}
	return j, nil
}

func (j *JSONRaw) UnmarshalJSON(b []byte) error {
	*j = append((*j)[:0], b...)
	return nil
}

// Strings 反序列化为字符串数组（image_urls 用）。
func (j JSONRaw) Strings() []string {
	if len(j) == 0 {
		return []string{}
	}
	var out []string
	if err := json.Unmarshal(j, &out); err != nil {
		return []string{}
	}
	return out
}

// TreeProgress 拾光树进度。
type TreeProgress struct {
	UserID     int64     `gorm:"primaryKey" json:"user_id"`
	Level      int8      `json:"level"` // 1-12
	Points     int32     `json:"points"`
	Season     int8      `json:"season"` // 1春 2夏 3秋 4冬
	YearCount  int32     `gorm:"column:year_count" json:"year_count"`
	YearTarget int32     `gorm:"column:year_target" json:"year_target"`
	UpdatedAt  time.Time `gorm:"column:updated_at" json:"-"`
}

func (TreeProgress) TableName() string { return "tree_progress" }
