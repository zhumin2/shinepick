package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/model"
	"shinepick/internal/pkg/audit"
	"shinepick/internal/repository"
)

// 留言业务常量（对齐产品 4.6 / 技术 5.3③）。
const (
	commentMaxLen    = 80               // 80 字上限（DB 与客户端双保险）
	commentWindow    = 10 * time.Second // 频控窗口
	commentWindowMax = 1                // 10 秒 1 条
	commentIdemTTL   = 10 * time.Minute
	commentPageLimit = 20
)

// 哨兵错误。
var (
	ErrCommentFrequent = errors.New("comment_frequent")
	ErrForbidden       = errors.New("forbidden")
)

// InteractionService 互动与留言（S5-01/02/03）。
type InteractionService struct {
	checkins *repository.CheckinRepo
	inter    *repository.InteractionRepo
	rdb      *redis.Client
	aud      audit.Auditor
	social   *SocialService // S6：通知落表 + 拉黑静默拒绝
}

func NewInteractionService(
	checkins *repository.CheckinRepo,
	inter *repository.InteractionRepo,
	rdb *redis.Client,
	aud audit.Auditor,
	social *SocialService,
) *InteractionService {
	return &InteractionService{checkins: checkins, inter: inter, rdb: rdb, aud: aud, social: social}
}

// React 点亮/拥抱/同路（幂等；同路额外建立同路人关系）。
func (s *InteractionService) React(ctx context.Context, uid, checkinID int64, typ int8) error {
	if typ < 1 || typ > 3 {
		return &ValidationError{msg: "互动类型不合法"}
	}
	c, err := s.checkins.ByID(ctx, checkinID)
	if err != nil {
		return err // NotFound 语义
	}
	if c.Status != 0 || (c.UserID != uid && c.Visibility != 2) {
		return gorm.ErrRecordNotFound
	}
	if s.social != nil {
		if err := s.social.CanInteract(ctx, uid, c.UserID); err != nil {
			return err // 双向拉黑：静默拒绝
		}
	}
	if err := s.inter.AddReaction(ctx, checkinID, uid, typ); err != nil {
		return err
	}
	if typ == 3 {
		// 「同路」：建立同路人关系（产品 4.5）
		if err := s.inter.UpsertCompanion(ctx, c.UserID, uid, checkinID); err != nil {
			return err
		}
	}
	if s.social != nil {
		s.social.notifyEvent(ctx, typ, c.UserID, uid, checkinID, 0)
	}
	return nil
}

// Unreact 取消互动（幂等）。
func (s *InteractionService) Unreact(ctx context.Context, uid, checkinID int64, typ int8) error {
	if typ < 1 || typ > 3 {
		return &ValidationError{msg: "互动类型不合法"}
	}
	return s.inter.RemoveReaction(ctx, checkinID, uid, typ)
}

// CommentVO 留言视图。
type CommentVO struct {
	ID         int64     `json:"id"`
	CheckinID  int64     `json:"checkin_id"`
	UserID     int64     `json:"user_id"`
	Nickname   string    `json:"nickname"`
	AvatarURL  string    `json:"avatar_url"`
	Content    string    `json:"content"`
	IsFeatured bool      `json:"is_featured"` // 作者指定在卡片展示
	CreatedAt  time.Time `json:"created_at"`
}

// AddComment 发留言：可见性 → 80 字 → 审核 → 频控 → 幂等 → 落库。
func (s *InteractionService) AddComment(ctx context.Context, uid, checkinID int64, content, clientToken string) (*CommentVO, error) {
	c, err := s.checkins.ByID(ctx, checkinID)
	if err != nil {
		return nil, err
	}
	if c.Status != 0 || (c.UserID != uid && c.Visibility != 2) {
		return nil, gorm.ErrRecordNotFound
	}
	if s.social != nil {
		if err := s.social.CanInteract(ctx, uid, c.UserID); err != nil {
			return nil, err // 拉黑后无法留言（静默生效，产品 4.6）
		}
	}
	content = trimSpace(content)
	if n := utf8.RuneCountInString(content); n < 1 || n > commentMaxLen {
		return nil, &ValidationError{msg: fmt.Sprintf("留言需为 1-%d 字", commentMaxLen)}
	}
	if v := s.aud.Text(ctx, content); !v.Pass {
		return nil, ErrCheckinReject // 复用审核拒绝语义（4101）
	}

	// 幂等优先：同 client_token 的客户端重试直接返回首次结果，
	// 不能被频控误拦（否则弱网重试会提示"操作过于频繁"）。
	var idemKey string
	if clientToken != "" {
		idemKey = fmt.Sprintf("idem:cm:%d:%s", uid, clientToken)
		if val, err := s.rdb.Get(ctx, idemKey).Result(); err == nil {
			var id int64
			if _, e := fmt.Sscan(val, &id); e == nil && id > 0 {
				return s.commentByID(ctx, id)
			}
		}
	}

	// 频控：10 秒 1 条（仅在非重放请求上计数）
	rlKey := fmt.Sprintf("rl:cm:%d", uid)
	if n, _ := s.rdb.Incr(ctx, rlKey).Result(); n == 1 {
		s.rdb.Expire(ctx, rlKey, commentWindow)
	} else if n > commentWindowMax {
		return nil, ErrCommentFrequent
	}

	cm := &model.Comment{CheckinID: checkinID, UserID: uid, Content: content}
	if err := s.inter.AddComment(ctx, cm); err != nil {
		return nil, err
	}
	if idemKey != "" {
		s.rdb.Set(ctx, idemKey, cm.ID, commentIdemTTL)
	}
	if s.social != nil {
		s.social.notifyEvent(ctx, 4, c.UserID, uid, checkinID, cm.ID)
	}
	return s.commentByID(ctx, cm.ID)
}

// ListComments 留言列表（新→旧，游标分页；刻意不返回 total——产品 4.6）。
func (s *InteractionService) ListComments(ctx context.Context, uid, checkinID, cursor int64) ([]*CommentVO, int64, error) {
	c, err := s.checkins.ByID(ctx, checkinID)
	if err != nil {
		return nil, 0, err
	}
	if c.Status != 0 || (c.UserID != uid && c.Visibility != 2) {
		return nil, 0, gorm.ErrRecordNotFound
	}
	list, err := s.inter.ListComments(ctx, checkinID, cursor, commentPageLimit+1)
	if err != nil {
		return nil, 0, err
	}
	next := int64(0)
	if len(list) > commentPageLimit {
		list = list[:commentPageLimit]
		next = list[len(list)-1].ID
	}
	out := make([]*CommentVO, 0, len(list))
	for _, cw := range list {
		out = append(out, toCommentVO(cw))
	}
	return out, next, nil
}

// DeleteComment 删除留言：本人可删自己的；打卡作者可删任意（产品 4.6）。
func (s *InteractionService) DeleteComment(ctx context.Context, viewer, commentID int64) error {
	cm, err := s.inter.CommentByID(ctx, commentID)
	if err != nil {
		return err
	}
	if cm.Status != 0 {
		return gorm.ErrRecordNotFound
	}
	owner, err := s.checkins.ByID(ctx, cm.CheckinID)
	if err != nil {
		return err
	}
	if cm.UserID != viewer && owner.UserID != viewer {
		return ErrForbidden
	}
	return s.inter.SoftDeleteComment(ctx, commentID)
}

func (s *InteractionService) commentByID(ctx context.Context, id int64) (*CommentVO, error) {
	cm, err := s.inter.CommentByID(ctx, id)
	if err != nil {
		return nil, err
	}
	// 复用列表联表查询拿作者信息（cursor=id+1 → 仅含 id<=该值的最新一条）
	cw, err := s.inter.ListComments(ctx, cm.CheckinID, id+1, 1)
	if err != nil || len(cw) == 0 {
		return &CommentVO{
			ID: cm.ID, CheckinID: cm.CheckinID, UserID: cm.UserID,
			Content: cm.Content, CreatedAt: cm.CreatedAt,
		}, err
	}
	return toCommentVO(cw[0]), nil
}

func toCommentVO(c *repository.CommentWithUser) *CommentVO {
	return &CommentVO{
		ID:         c.ID,
		CheckinID:  c.CheckinID,
		UserID:     c.UserID,
		Nickname:   c.Nickname,
		AvatarURL:  c.AvatarURL,
		Content:    c.Content,
		IsFeatured: c.IsFeatured == 1,
		CreatedAt:  c.CreatedAt,
	}
}

// FillMyReactions 给一批 CheckinVO 回填当前观众的互动状态（按钮选中态）。
func (s *InteractionService) FillMyReactions(ctx context.Context, viewer int64, items []*CheckinVO) {
	if len(items) == 0 || viewer <= 0 {
		return
	}
	ids := make([]int64, 0, len(items))
	for _, it := range items {
		ids = append(ids, it.ID)
	}
	m, err := s.inter.MyReactionTypes(ctx, viewer, ids)
	if err != nil {
		return // 回填失败不阻塞内容返回
	}
	for _, it := range items {
		if t, ok := m[it.ID]; ok {
			it.MyReactions = t
		}
	}
}

// previewPerCheckin 卡片上每条打卡展示的留言条数上限（产品原则：只给温度，不给数量）。
const previewPerCheckin = 2

// FillPreviewComments 给一批 CheckinVO 回填卡片展示留言（作者指定优先，其次最新）。
func (s *InteractionService) FillPreviewComments(ctx context.Context, items []*CheckinVO) {
	if len(items) == 0 {
		return
	}
	ids := make([]int64, 0, len(items))
	for _, it := range items {
		ids = append(ids, it.ID)
	}
	m, err := s.inter.PreviewComments(ctx, ids, previewPerCheckin)
	if err != nil {
		return // 回填失败不阻塞内容返回
	}
	for _, it := range items {
		if list, ok := m[it.ID]; ok && len(list) > 0 {
			vos := make([]*CommentVO, 0, len(list))
			for _, c := range list {
				vos = append(vos, toCommentVO(c))
			}
			it.PreviewComments = vos
		}
	}
}

// SetFeatured 作者指定某条留言在卡片上展示（或取消）。
// 仅打卡作者可操作（产品 4.6：打卡作者可管理自己内容下的留言）。
func (s *InteractionService) SetFeatured(ctx context.Context, viewer, commentID int64, featured bool) error {
	cm, err := s.inter.CommentByID(ctx, commentID)
	if err != nil {
		return err
	}
	if cm.Status != 0 {
		return gorm.ErrRecordNotFound
	}
	owner, err := s.checkins.ByID(ctx, cm.CheckinID)
	if err != nil {
		return err
	}
	if owner.UserID != viewer {
		return ErrForbidden
	}
	return s.inter.SetFeatured(ctx, commentID, featured)
}

// trimSpace 去除首尾空白（含全角空格等 Unicode 空白）。
// 注：strings.TrimSpace 按 rune 处理，能正确识别多字节空白符。
func trimSpace(s string) string {
	return strings.TrimSpace(s)
}
