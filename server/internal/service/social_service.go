package service

import (
	"context"
	"fmt"
	"time"

	"gorm.io/gorm"

	"shinepick/internal/model"
	"shinepick/internal/repository"
)

// SocialService 通知 / 拉黑 / 举报（S6）。
type SocialService struct {
	social   *repository.SocialRepo
	inter    *repository.InteractionRepo
	checkins *repository.CheckinRepo
}

func NewSocialService(
	social *repository.SocialRepo,
	inter *repository.InteractionRepo,
	checkins *repository.CheckinRepo,
) *SocialService {
	return &SocialService{social: social, inter: inter, checkins: checkins}
}

// notifyEvent 事件落表入口（由互动/留言调用）。
// 匿名规则（技术文档 6.3）：非互相同路的点亮/拥抱不显示触发者；
// 同路与留言本身非匿名，显示触发者。自己给自己的动作不通知。
func (s *SocialService) notifyEvent(ctx context.Context, typ int8, ownerID, actorID, checkinID, commentID int64) {
	if ownerID == actorID {
		return
	}
	var actorPtr *int64
	switch typ {
	case 1, 2: // 点亮/拥抱：互相同路才显示
		mutual, err := s.inter.MutualCompanion(ctx, ownerID, actorID)
		if err != nil || !mutual {
			actorPtr = nil // 匿名
		} else {
			id := actorID
			actorPtr = &id
		}
	default: // 3同路 4留言：显示触发者
		id := actorID
		actorPtr = &id
	}
	cid := checkinID
	var cidPtr *int64
	if cid > 0 {
		cidPtr = &cid
	}
	var cmidPtr *int64
	if commentID > 0 {
		cmidPtr = &commentID
	}
	_ = s.social.Notify(ctx, &model.Notification{
		UserID: ownerID, Type: typ, ActorID: actorPtr,
		CheckinID: cidPtr, CommentID: cmidPtr,
	})
	// 极光推送通道：待凭据接入（S6-02），静默时段 22:00-07:00 拦截在推送侧实现
}

// NotificationVO 通知视图（服务端生成文案，客户端直接展示）。
type NotificationVO struct {
	ID        int64     `json:"id"`
	Type      int8      `json:"type"`
	ActorID   *int64    `json:"actor_id,omitempty"`
	ActorName string    `json:"actor_name,omitempty"`
	CheckinID *int64    `json:"checkin_id,omitempty"`
	CommentID *int64    `json:"comment_id,omitempty"`
	AggCount  int32     `json:"agg_count"`
	Copy      string    `json:"copy"`
	IsRead    bool      `json:"is_read"`
	CreatedAt time.Time `json:"created_at"`
}

// List 通知列表（含未读数，供铃铛轻提示）。
func (s *SocialService) List(ctx context.Context, uid, cursor int64) ([]*NotificationVO, int64, int64, error) {
	const limit = 20
	list, err := s.social.ListNotifications(ctx, uid, cursor, limit+1)
	if err != nil {
		return nil, 0, 0, err
	}
	next := int64(0)
	if len(list) > limit {
		list = list[:limit]
		next = list[len(list)-1].ID
	}
	unread, err := s.social.UnreadCount(ctx, uid)
	if err != nil {
		return nil, 0, 0, err
	}
	// 收集需要展示昵称的 actor
	actorIDs := make([]int64, 0, len(list))
	for _, n := range list {
		if n.ActorID != nil {
			actorIDs = append(actorIDs, *n.ActorID)
		}
	}
	names, err := s.social.ActorNicknames(ctx, actorIDs)
	if err != nil {
		names = map[int64]string{}
	}
	out := make([]*NotificationVO, 0, len(list))
	for _, n := range list {
		out = append(out, buildNotificationVO(n, names))
	}
	return out, next, unread, nil
}

func buildNotificationVO(n *model.Notification, names map[int64]string) *NotificationVO {
	vo := &NotificationVO{
		ID: n.ID, Type: n.Type, ActorID: n.ActorID,
		CheckinID: n.CheckinID, CommentID: n.CommentID,
		AggCount: n.AggCount, IsRead: n.IsRead == 1,
	}
	if n.ActorID != nil {
		vo.ActorName = names[*n.ActorID]
	}
	action := ""
	switch n.Type {
	case 1:
		action = "点亮"
	case 2:
		action = "拥抱"
	case 3:
		action = "和你同路"
	case 4:
		action = "留言"
	}
	switch {
	case n.Type == 1 || n.Type == 2:
		if n.ActorID == nil {
			vo.Copy = fmt.Sprintf("有 %d 个人%s了你的拾光", n.AggCount, action)
		} else {
			vo.Copy = fmt.Sprintf("%s %s了你的拾光", vo.ActorName, action)
		}
	case n.Type == 3:
		vo.Copy = fmt.Sprintf("%s 和你同路了，你们可以互相看见彼此的拾光", vo.ActorName)
	case n.Type == 4:
		vo.Copy = fmt.Sprintf("%s 留言了你的拾光", vo.ActorName)
	default:
		vo.Copy = "你有新的消息"
	}
	return vo
}

// MarkAllRead 全部已读。
func (s *SocialService) MarkAllRead(ctx context.Context, uid int64) error {
	return s.social.MarkAllRead(ctx, uid)
}

// ---- 拉黑 ----

// Block 拉黑（静默生效：对方无法再互动/留言，Feed 双向不可见）。
func (s *SocialService) Block(ctx context.Context, blocker, blocked int64) error {
	if blocker == blocked {
		return &ValidationError{msg: "不能拉黑自己"}
	}
	if _, err := s.checkins.ByID(ctx, blocked); err != nil && err != gorm.ErrRecordNotFound {
		// 被拉黑者不存在也允许（用户可能注销）；这里仅做库错误透传
	}
	return s.social.Block(ctx, blocker, blocked)
}

// Unblock 取消拉黑。
func (s *SocialService) Unblock(ctx context.Context, blocker, blocked int64) error {
	return s.social.Unblock(ctx, blocker, blocked)
}

// BlockedSet 双向合并的黑名单（Feed 过滤用）：我拉黑的 + 拉黑我的。
func (s *SocialService) BlockedSet(ctx context.Context, uid int64) (map[int64]bool, error) {
	mine, err := s.social.BlockedIDs(ctx, uid)
	if err != nil {
		return nil, err
	}
	by, err := s.social.BlockedByList(ctx, uid)
	if err != nil {
		return nil, err
	}
	for id := range by {
		mine[id] = true
	}
	return mine, nil
}

// FilterBlocked 原地过滤 VO 列表中的黑名单作者。
func (s *SocialService) FilterBlocked(ctx context.Context, uid int64, items []*CheckinVO) error {
	if len(items) == 0 {
		return nil
	}
	set, err := s.BlockedSet(ctx, uid)
	if err != nil || len(set) == 0 {
		return err
	}
	kept := items[:0]
	for _, it := range items {
		if !set[it.UserID] {
			kept = append(kept, it)
		}
	}
	// 就地截断（调用方持有 slice）
	for i := len(kept); i < len(items); i++ {
		items[i] = nil
	}
	return nil
}

// FilterBlockedFeedItems 过滤 Feed 条目（含作者信息），返回新切片。
// 注意：必须以返回值替换原切片，range 循环里的指针副本不可靠。
func (s *SocialService) FilterBlockedFeedItems(ctx context.Context, uid int64, items []*FeedItem) []*FeedItem {
	if len(items) == 0 {
		return items
	}
	set, err := s.BlockedSet(ctx, uid)
	if err != nil || len(set) == 0 {
		return items
	}
	out := make([]*FeedItem, 0, len(items))
	for _, it := range items {
		if it != nil && !set[it.CheckinVO.UserID] {
			out = append(out, it)
		}
	}
	return out
}

// CanInteract 互动/留言前置：双向拉黑任一成立即静默拒绝（返回 NotFound 语义）。
func (s *SocialService) CanInteract(ctx context.Context, actor, owner int64) error {
	blocked, err := s.social.IsBlocked(ctx, actor, owner)
	if err != nil {
		return err
	}
	if blocked {
		return gorm.ErrRecordNotFound // 静默生效，不提示"被拉黑"
	}
	return nil
}

// ---- 举报 ----

// Report 举报（目标存在性宽松校验：打卡/留言需存在，用户允许任意）。
func (s *SocialService) Report(ctx context.Context, reporterID int64, targetType int8, targetID int64, reason int8, detail string) error {
	if targetType < 1 || targetType > 3 {
		return &ValidationError{msg: "举报目标类型不合法"}
	}
	switch targetType {
	case 1:
		if _, err := s.checkins.ByID(ctx, targetID); err != nil {
			return err
		}
	case 2:
		if _, err := s.social.ActorNicknames(ctx, []int64{}); err != nil {
			return err
		}
		var cm model.Comment
		if err := s.social.DB().WithContext(ctx).First(&cm, targetID).Error; err != nil {
			return err
		}
	}
	if len([]rune(detail)) > 255 {
		detail = string([]rune(detail)[:255])
	}
	return s.social.AddReport(ctx, &model.Report{
		ReporterID: reporterID, TargetType: targetType,
		TargetID: targetID, Reason: reason, Detail: detail,
	})
}
