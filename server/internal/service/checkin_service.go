package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/model"
	"shinepick/internal/pkg/audit"
	"shinepick/internal/repository"
)

// 打卡业务常量（对齐产品/技术文档）。
const (
	checkinMaxLen    = 500              // 一句话上限
	checkinMaxImages = 9                // 最多 9 张
	checkinWindow    = time.Minute      // 频控窗口
	checkinWindowMax = 3                // 1 分钟最多 3 条（技术文档 5.3）
	checkinIdemTTL   = 10 * time.Minute // client_token 幂等保留
	checkinPageLimit = 20               // 列表单页上限（反"刷不停"）
)

// treeLevels 树阶段阈值（技术文档 6.4）：points 达阈值 → level=i+1。
var treeLevels = []int{1, 3, 7, 14, 30, 60, 100, 150, 200, 260, 330, 400}

// TreeLevelForPoints 按累计光点数映射树阶段（1-12）。
func TreeLevelForPoints(points int) int8 {
	level := int8(1)
	for i, th := range treeLevels {
		if points >= th {
			level = int8(i + 1)
		}
	}
	return level
}

// 哨兵错误。
var (
	ErrCheckinReject   = errors.New("checkin_rejected")
	ErrCheckinFrequent = errors.New("checkin_frequent")
)

// CreateCheckinReq 发布打卡请求。
type CreateCheckinReq struct {
	Category    int8            `json:"category"`
	CustomName  string          `json:"custom_name"` // category=6 必填（1-20 字，过审核）
	Content     string          `json:"content"`
	ImageURLs   []string        `json:"image_urls"`
	VideoURL    string          `json:"video_url"`
	Visibility  int8            `json:"visibility"`
	Extra       json.RawMessage `json:"extra"`
	ClientToken string          `json:"client_token"`
}

// CheckinVO 打卡视图（列表/详情/发布共用）。
type CheckinVO struct {
	ID              int64           `json:"id"`
	UserID          int64           `json:"user_id"`
	Category        int8            `json:"category"`
	CustomName      string          `json:"custom_name,omitempty"`
	Content         string          `json:"content"`
	ImageURLs       []string        `json:"image_urls"`
	VideoURL        string          `json:"video_url,omitempty"`
	Visibility      int8            `json:"visibility"`
	Extra           json.RawMessage `json:"extra,omitempty"`
	CheckinDate     string          `json:"checkin_date"`
	CreatedAt       time.Time       `json:"created_at"`
	MyReactions     []int8          `json:"my_reactions,omitempty"`     // 当前观众已点的互动类型（S5 按钮态）
	PreviewComments []*CommentVO    `json:"preview_comments,omitempty"` // 卡片展示的留言（最多 2 条，不暴露总数）
}

// PublishResult 发布结果（含树联动数据）。
type PublishResult struct {
	*CheckinVO
	TreeLevel        int8  `json:"tree_level"`
	LightPointsTotal int32 `json:"light_points_total"`
}

// CheckinService 打卡业务（S3-03/S3-04）。
type CheckinService struct {
	repo  *repository.CheckinRepo
	urepo *repository.UserRepo
	rdb   *redis.Client
	aud   audit.Auditor

	onPublished func(ctx context.Context, uid, checkinID int64) // 发布后回调（S7 徽章评估）
}

// SetOnPublished 注册发布后回调（徽章评估，S7）。
func (s *CheckinService) SetOnPublished(f func(ctx context.Context, uid, checkinID int64)) {
	s.onPublished = f
}

func NewCheckinService(
	repo *repository.CheckinRepo,
	urepo *repository.UserRepo,
	rdb *redis.Client,
	aud audit.Auditor,
) *CheckinService {
	return &CheckinService{repo: repo, urepo: urepo, rdb: rdb, aud: aud}
}

// Create 发布打卡：审核 → 频控 → 幂等 → 事务（insert + 树联动）。
func (s *CheckinService) Create(ctx context.Context, uid int64, req *CreateCheckinReq) (*PublishResult, error) {
	// 1. 参数校验
	if req.Category < 1 || req.Category > 6 {
		return nil, &ValidationError{msg: "品类不合法"}
	}
	// 自定义（category=6）= 统一兜底门类「其他」，不再要求自定义名称；
	// 历史字段兼容：收到 custom_name 仍照常存储，但无业务含义
	customName := strings.TrimSpace(req.CustomName)
	if req.Category != 6 {
		customName = "" // 固定品类忽略自定义名
	}
	if req.Visibility < 1 || req.Visibility > 3 {
		return nil, &ValidationError{msg: "可见范围不合法"}
	}
	if l := len([]rune(req.Content)); l < 1 || l > checkinMaxLen {
		return nil, &ValidationError{msg: fmt.Sprintf("内容需为 1-%d 字", checkinMaxLen)}
	}
	if len(req.ImageURLs) > checkinMaxImages {
		return nil, &ValidationError{msg: "图片最多 9 张"}
	}

	// 2. 内容审核（mock 关键词 / remote Python 服务；异常放行策略见 audit 包）
	// 自定义品类名同样过审（产品 §3.2「需审核」）
	if v := s.aud.Text(ctx, req.Content); !v.Pass {
		return nil, ErrCheckinReject
	}
	if customName != "" {
		if v := s.aud.Text(ctx, customName); !v.Pass {
			return nil, ErrCheckinReject
		}
	}

	// 3. 幂等优先：client_token 重复提交返回首次结果（弱网重试不该被频控误拦）
	var idemKey string
	if req.ClientToken != "" {
		idemKey = fmt.Sprintf("idem:ck:%d:%s", uid, req.ClientToken)
		if val, err := s.rdb.Get(ctx, idemKey).Result(); err == nil {
			var id int64
			if _, e := fmt.Sscan(val, &id); e == nil && id > 0 {
				return s.byIDResult(ctx, id)
			}
		}
		// SetNX 防并发：抢不到说明同 token 请求正在处理，短轮询等结果
		if ok, _ := s.rdb.SetNX(ctx, idemKey, 0, checkinIdemTTL).Result(); !ok {
			if r := s.waitIdem(ctx, idemKey); r > 0 {
				return s.byIDResult(ctx, r)
			}
			return nil, ErrCheckinFrequent // 兜底：极短窗口内并发重复
		}
	}

	// 4. 频控：单用户 1 分钟 3 条（仅对非重放请求计数）
	rlKey := fmt.Sprintf("rl:ck:%d", uid)
	if n, _ := s.rdb.Incr(ctx, rlKey).Result(); n == 1 {
		s.rdb.Expire(ctx, rlKey, checkinWindow)
	} else if n > checkinWindowMax {
		if idemKey != "" {
			s.rdb.Del(ctx, idemKey) // 释放占位，避免重放被锁死
		}
		return nil, ErrCheckinFrequent
	}

	// 5. 事务：insert checkin + 树联动
	today := time.Now().In(cstZone).Format("2006-01-02")
	imgJSON, _ := json.Marshal(req.ImageURLs)
	c := &model.Checkin{
		UserID:      uid,
		Category:    req.Category,
		CustomName:  customName,
		Content:     req.Content,
		ImageURLs:   model.JSONRaw(imgJSON),
		VideoURL:    req.VideoURL,
		Visibility:  req.Visibility,
		Extra:       model.JSONRaw(req.Extra),
		CheckinDate: today,
	}
	created, err := s.repo.CreateWithTx(ctx, c, s.bumpTree)
	if err != nil {
		if idemKey != "" {
			s.rdb.Del(ctx, idemKey) // 失败释放占位，允许重试
		}
		return nil, err
	}
	if idemKey != "" {
		s.rdb.Set(ctx, idemKey, created.ID, checkinIdemTTL)
	}
	if s.onPublished != nil {
		s.onPublished(ctx, uid, created.ID) // S7：徽章评估
	}
	tree, _, err := s.repo.TreeByUser(ctx, uid)
	if err != nil {
		return nil, err
	}
	return &PublishResult{
		CheckinVO:        toCheckinVO(created),
		TreeLevel:        tree.Level,
		LightPointsTotal: tree.Points,
	}, nil
}

// waitIdem 并发同 token 时等待首次请求写入结果（最多 ~2s）。
func (s *CheckinService) waitIdem(ctx context.Context, key string) int64 {
	for i := 0; i < 10; i++ {
		select {
		case <-ctx.Done():
			return 0
		case <-time.After(200 * time.Millisecond):
		}
		if val, err := s.rdb.Get(ctx, key).Result(); err == nil {
			var id int64
			if _, e := fmt.Sscan(val, &id); e == nil && id > 0 {
				return id
			}
		}
	}
	return 0
}

// bumpTree 事务内的树联动：首打卡建档，否则 points/year_count +1，level 重算。
func (s *CheckinService) bumpTree(tx *gorm.DB, uid int64) error {
	var t model.TreeProgress
	err := tx.Where("user_id = ?", uid).First(&t).Error
	if err == gorm.ErrRecordNotFound {
		return tx.Create(&model.TreeProgress{UserID: uid, Level: 1, Points: 1, YearCount: 1, YearTarget: 300}).Error
	}
	if err != nil {
		return err
	}
	points := t.Points + 1
	return tx.Model(&model.TreeProgress{}).Where("user_id = ?", uid).Updates(map[string]interface{}{
		"points":     points,
		"year_count": t.YearCount + 1,
		"level":      TreeLevelForPoints(int(points)),
	}).Error
}

func (s *CheckinService) byIDResult(ctx context.Context, id int64) (*PublishResult, error) {
	c, err := s.repo.ByID(ctx, id)
	if err != nil {
		return nil, err
	}
	tree, _, err := s.repo.TreeByUser(ctx, c.UserID)
	if err != nil {
		return nil, err
	}
	return &PublishResult{CheckinVO: toCheckinVO(c), TreeLevel: tree.Level, LightPointsTotal: tree.Points}, nil
}

// List 我的/他人打卡（S3-04）：me=true 全部可见范围；他人仅 visibility=2。
// 返回 items + nextCursor（0 表示没有更多）。
func (s *CheckinService) List(ctx context.Context, viewerUID, targetUID int64, cursor int64, me bool) ([]*CheckinVO, int64, error) {
	limit := checkinPageLimit
	var (
		list []*model.Checkin
		err  error
	)
	if me {
		list, err = s.repo.ListByUser(ctx, targetUID, cursor, limit+1)
	} else {
		list, err = s.repo.ListPublic(ctx, targetUID, cursor, limit+1)
	}
	if err != nil {
		return nil, 0, err
	}
	next := int64(0)
	if len(list) > limit {
		list = list[:limit]
		next = list[len(list)-1].ID
	}
	out := make([]*CheckinVO, 0, len(list))
	for _, c := range list {
		out = append(out, toCheckinVO(c))
	}
	return out, next, nil
}

// Detail 详情：作者看全部，他人仅 visibility=2（否则 5002）。
func (s *CheckinService) Detail(ctx context.Context, viewerUID, id int64) (*CheckinVO, error) {
	c, err := s.repo.ByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if c.Status != 0 || (c.UserID != viewerUID && c.Visibility != 2) {
		return nil, gorm.ErrRecordNotFound
	}
	return toCheckinVO(c), nil
}

// Delete 软删除自己的打卡（幂等：已删返回 NotFound 语义由 handler 映射）。
func (s *CheckinService) Delete(ctx context.Context, uid, id int64) error {
	return s.repo.SoftDelete(ctx, id, uid)
}

func toCheckinVO(c *model.Checkin) *CheckinVO {
	return &CheckinVO{
		ID:          c.ID,
		UserID:      c.UserID,
		Category:    c.Category,
		CustomName:  c.CustomName,
		Content:     c.Content,
		ImageURLs:   c.ImageURLs.Strings(),
		VideoURL:    c.VideoURL,
		Visibility:  c.Visibility,
		Extra:       json.RawMessage(c.Extra),
		CheckinDate: dateOnly(c.CheckinDate),
		CreatedAt:   c.CreatedAt,
	}
}
