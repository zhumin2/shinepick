package service

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/model"
)

// FeedbackService 意见反馈（v0.6.0 T8）：设置页提交 → 运营面板查看。
type FeedbackService struct {
	db  *gorm.DB
	rdb *redis.Client
}

func NewFeedbackService(db *gorm.DB, rdb *redis.Client) *FeedbackService {
	return &FeedbackService{db: db, rdb: rdb}
}

// Submit 提交反馈：≤200 字，每用户 10 分钟 1 条（Redis SETNX 窗口）。
func (s *FeedbackService) Submit(ctx context.Context, uid int64, content string) error {
	content = strings.TrimSpace(content)
	if content == "" {
		return validateErrf("反馈内容不能为空")
	}
	if len([]rune(content)) > 200 {
		return validateErrf("反馈内容不能超过 200 字")
	}
	key := "fb:rl:" + strconv.FormatInt(uid, 10)
	ok, err := s.rdb.SetNX(ctx, key, 1, 10*time.Minute).Result()
	if err == nil && !ok {
		return ErrFrequent
	}
	return s.db.WithContext(ctx).Create(&model.Feedback{
		UserID: uid, Content: content,
	}).Error
}
