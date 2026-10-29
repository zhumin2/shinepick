package service

import (
	"context"
	"encoding/json"
	"time"

	"github.com/redis/go-redis/v9"

	"shinepick/internal/repository"
)

// Feed 缓存键与 TTL（技术文档 8.2）。
const (
	feedSelectedKey  = "feed:selected"     // 每日精选 List
	feedDoingKeyFmt  = "feed:doing:%d:%s"  // feed:doing:{uid}:{date}（按人按日）
	feedCacheTTL     = 60 * time.Second
	dailySelectedN   = 5                    // 今日微光条数
	doingN           = 5                    // 同品类横滑条数
)

// FeedUser Feed 条目的作者信息。
type FeedUser struct {
	ID        int64  `json:"id"`
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
}

// FeedItem 今日微光/同品类条目。
type FeedItem struct {
	CheckinVO
	User FeedUser `json:"user"`
}

// FeedVO GET /feed 响应。
type FeedVO struct {
	DailySelected []*FeedItem `json:"daily_selected"`
	Doing         []*FeedItem `json:"doing"`
}

// FeedService 首页 Feed（S4-01/S4-02）。
type FeedService struct {
	repo *repository.CheckinRepo
	rdb  *redis.Client
}

func NewFeedService(repo *repository.CheckinRepo, rdb *redis.Client) *FeedService {
	return &FeedService{repo: repo, rdb: rdb}
}

// Today 今日页 Feed：每日微光 + 同品类打卡的陌生人。
// 每日微光走 Redis 缓存（cron 08:00 重建 + 空时懒重建，TTL 60s 供高频读）；
// doing 按人按日缓存 60s。
func (s *FeedService) Today(ctx context.Context, uid int64) (*FeedVO, error) {
	today := time.Now().In(cstZone).Format("2006-01-02")

	selected, err := s.dailySelected(ctx, today)
	if err != nil {
		return nil, err
	}
	doing, err := s.doingForUser(ctx, uid, today)
	if err != nil {
		return nil, err
	}
	return &FeedVO{DailySelected: selected, Doing: doing}, nil
}

// dailySelected 读取每日精选；缓存空则即时重建（含 cron 未跑的冷启动场景）。
func (s *FeedService) dailySelected(ctx context.Context, today string) ([]*FeedItem, error) {
	n, err := s.rdb.LLen(ctx, feedSelectedKey).Result()
	if err == nil && n > 0 {
		vals, err := s.rdb.LRange(ctx, feedSelectedKey, 0, -1).Result()
		if err == nil {
			items := make([]*FeedItem, 0, len(vals))
			ok := true
			for _, v := range vals {
				var it FeedItem
				if e := json.Unmarshal([]byte(v), &it); e != nil {
					ok = false
					break
				}
				items = append(items, &it)
			}
			if ok && len(items) > 0 {
				return items, nil
			}
		}
	}
	// 重建（当日候选）
	if err := s.RebuildDailySelected(ctx, today); err != nil {
		return nil, err
	}
	vals, err := s.rdb.LRange(ctx, feedSelectedKey, 0, -1).Result()
	if err != nil {
		return []*FeedItem{}, nil
	}
	items := make([]*FeedItem, 0, len(vals))
	for _, v := range vals {
		var it FeedItem
		if json.Unmarshal([]byte(v), &it) == nil {
			items = append(items, &it)
		}
	}
	return items, nil
}

// RebuildDailySelected 规则模型挑选当日精选：品类均衡轮转 + 新旧混合（技术文档 6.1）。
// cron 每日 08:00 调用；读取路径冷启动兜底也会调用。
func (s *FeedService) RebuildDailySelected(ctx context.Context, date string) error {
	candidates, err := s.repo.ListDailyCandidates(ctx, date, 200)
	if err != nil {
		return err
	}
	picked := selectDaily(candidates, dailySelectedN)
	s.rdb.Del(ctx, feedSelectedKey)
	if len(picked) > 0 {
		vals := make([]interface{}, 0, len(picked))
		for _, p := range picked {
			b, _ := json.Marshal(toFeedItem(p))
			vals = append(vals, string(b))
		}
		s.rdb.RPush(ctx, feedSelectedKey, vals...)
	}
	// 60s TTL 控制陈旧度；cron 每日重建保证新鲜
	s.rdb.Expire(ctx, feedSelectedKey, feedCacheTTL)
	return nil
}

// selectDaily 品类均衡轮转：每品类轮流取一条，避免 Feed 被单一品类刷屏。
// 同品类内按 id 新→旧（SQL DESC 保证）；品类首次出现序即最新优先。
func selectDaily(candidates []*repository.CheckinWithUser, n int) []*repository.CheckinWithUser {
	byCat := map[int8][]*repository.CheckinWithUser{}
	order := []int8{}
	for _, c := range candidates {
		if _, seen := byCat[c.Category]; !seen {
			order = append(order, c.Category)
		}
		byCat[c.Category] = append(byCat[c.Category], c)
	}

	picked := make([]*repository.CheckinWithUser, 0, n)
	idx := map[int8]int{}
	for len(picked) < n {
		added := false
		for _, cat := range order {
			list := byCat[cat]
			if idx[cat] < len(list) {
				picked = append(picked, list[idx[cat]])
				idx[cat]++
				added = true
				if len(picked) == n {
					break
				}
			}
		}
		if !added {
			break
		}
	}
	return picked
}

// doingForUser 「我正在打卡的事」：我今日打卡的品类里，今天也在打卡的陌生人。
// 品类偏好本身不含内容，仅自己可见的打卡只参与品类归纳。
func (s *FeedService) doingForUser(ctx context.Context, uid int64, today string) ([]*FeedItem, error) {
	mine, err := s.repo.ListByUser(ctx, uid, 0, 20)
	if err != nil {
		return nil, err
	}
	cats := map[int8]bool{}
	for _, c := range mine {
		if normalizeDate(c.CheckinDate) == today {
			cats[c.Category] = true
		}
	}
	if len(cats) == 0 {
		return []*FeedItem{}, nil
	}
	// 合并去重（同人取最新一条），总数 doingN
	seen := map[int64]bool{}
	out := make([]*FeedItem, 0, doingN)
	for cat := range cats {
		list, err := s.repo.ListTodayPublicByCategory(ctx, today, cat, uid, doingN)
		if err != nil {
			continue
		}
		for _, c := range list {
			if seen[c.UserID] {
				continue
			}
			seen[c.UserID] = true
			out = append(out, toFeedItem(c))
			if len(out) >= doingN {
				return out, nil
			}
		}
	}
	return out, nil
}

func toFeedItem(c *repository.CheckinWithUser) *FeedItem {
	vo := toCheckinVO(&c.Checkin)
	return &FeedItem{
		CheckinVO: *vo,
		User: FeedUser{
			ID:        c.UserID,
			Nickname:  c.Nickname,
			AvatarURL: c.AvatarURL,
		},
	}
}

// Explore 发现页：品类过滤（0=全部）+ 游标分页（S4-05）。
func (s *FeedService) Explore(ctx context.Context, category int8, cursor int64) ([]*FeedItem, int64, error) {
	const limit = 20
	list, err := s.repo.ListExplore(ctx, category, cursor, limit+1)
	if err != nil {
		return nil, 0, err
	}
	next := int64(0)
	if len(list) > limit {
		list = list[:limit]
		next = list[len(list)-1].ID
	}
	out := make([]*FeedItem, 0, len(list))
	for _, c := range list {
		out = append(out, toFeedItem(c))
	}
	return out, next, nil
}

// StartDailyCron 每日 08:00（东八区）重建精选（S4-02）。阻塞调用，go 程启动。
func StartDailyCron(ctx context.Context, svc *FeedService) {
	go func() {
		for {
			now := time.Now().In(cstZone)
			next := time.Date(now.Year(), now.Month(), now.Day(), 8, 0, 0, 0, cstZone)
			if !next.After(now) {
				next = next.AddDate(0, 0, 1)
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(next.Sub(now)):
			}
			_ = svc.RebuildDailySelected(ctx, time.Now().In(cstZone).Format("2006-01-02"))
		}
	}()
}
