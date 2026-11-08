package service

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/middleware"
	"shinepick/internal/model"
)

// AdminService 运营接口（S8-01/S8-05 精选与指标；v0.6.0 扩展治理与运营）。
type AdminService struct {
	db   *gorm.DB
	feed *FeedService
	rdb  *redis.Client
}

func NewAdminService(db *gorm.DB, feed *FeedService, rdb *redis.Client) *AdminService {
	return &AdminService{db: db, feed: feed, rdb: rdb}
}

// StatsVO 内测数据面板（北极星：周打卡 ≥3 天用户占 WAU 比例）。
type StatsVO struct {
	UsersTotal    int64     `json:"users_total"`
	UsersNew7d    int64     `json:"users_new_7d"`
	CheckinsToday int64     `json:"checkins_today"`
	Checkins7d    int64     `json:"checkins_7d"`
	WAU           int64     `json:"wau"`
	PolarStarPct  float64   `json:"polar_star_pct"` // 周打卡≥3天用户 / WAU
	GeneratedAt   time.Time `json:"generated_at"`
}

// Stats 计算面板指标。
func (s *AdminService) Stats(ctx context.Context) (*StatsVO, error) {
	now := time.Now().In(cstZone)
	today := now.Format("2006-01-02")
	weekAgo := now.AddDate(0, 0, -7)

	out := &StatsVO{GeneratedAt: now}
	if err := s.db.WithContext(ctx).Table("users").Count(&out.UsersTotal).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("users").
		Where("created_at > ?", weekAgo).Count(&out.UsersNew7d).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("checkins").
		Where("status = 0 AND checkin_date = ?", today).
		Count(&out.CheckinsToday).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("checkins").
		Where("status = 0 AND created_at > ?", weekAgo).
		Count(&out.Checkins7d).Error; err != nil {
		return nil, err
	}
	if err := s.db.WithContext(ctx).Table("checkins").
		Where("status = 0 AND created_at > ?", weekAgo).
		Distinct("user_id").Count(&out.WAU).Error; err != nil {
		return nil, err
	}
	// 北极星：近 7 天打卡 ≥3 个不同日期的用户数 / WAU
	var polar int64
	if err := s.db.WithContext(ctx).Table("checkins").
		Select("user_id").
		Where("status = 0 AND created_at > ?", weekAgo).
		Group("user_id").
		Having("COUNT(DISTINCT checkin_date) >= 3").
		Count(&polar).Error; err != nil {
		return nil, err
	}
	if out.WAU > 0 {
		out.PolarStarPct = float64(polar) / float64(out.WAU) * 100
	}
	return out, nil
}

// ---------- 举报处理台（v0.6.0 T3） ----------

// ReportVO 举报列表项：举报信息 + 被举报对象快照（判罚无需另查内容）。
type ReportVO struct {
	ID         int64           `json:"id"`
	ReporterID int64           `json:"reporter_id"`
	TargetType int8            `json:"target_type"` // 1打卡 2留言 3用户
	TargetID   int64           `json:"target_id"`
	Reason     int8            `json:"reason"`
	Detail     string          `json:"detail"`
	Status     int8            `json:"status"` // 0待处理 1已处理 2驳回
	CreatedAt  time.Time       `json:"created_at"`
	Snapshot   *ReportSnapshot `json:"snapshot,omitempty"`
}

// ReportSnapshot 被举报对象内容快照。
type ReportSnapshot struct {
	Content   string `json:"content,omitempty"`    // 打卡正文 / 留言内容
	Images    string `json:"images,omitempty"`     // 打卡图 image_urls 原样 JSON
	AuthorID  int64  `json:"author_id,omitempty"`  // 内容作者 / 目标用户 id
	Author    string `json:"author,omitempty"`     // 作者或目标用户昵称
	CheckinID int64  `json:"checkin_id,omitempty"` // 留言所属打卡（跳详情用）
}

// Reports 举报分页列表。status<0 查全部；快照按目标类型批量补齐（避免 N+1）。
func (s *AdminService) Reports(ctx context.Context, status int8, page, pageSize int) ([]*ReportVO, int64, error) {
	q := s.db.WithContext(ctx).Model(&model.Report{})
	if status >= 0 {
		q = q.Where("status = ?", status)
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if total == 0 {
		return []*ReportVO{}, 0, nil
	}
	var rows []*model.Report
	if err := q.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&rows).Error; err != nil {
		return nil, 0, err
	}
	out := make([]*ReportVO, 0, len(rows))
	for _, r := range rows {
		out = append(out, &ReportVO{
			ID: r.ID, ReporterID: r.ReporterID, TargetType: r.TargetType,
			TargetID: r.TargetID, Reason: r.Reason, Detail: r.Detail,
			Status: r.Status, CreatedAt: r.CreatedAt,
		})
	}
	s.fillSnapshots(ctx, rows, out)
	return out, total, nil
}

// fillSnapshots 三类目标各一条批量 IN 查询补快照。
func (s *AdminService) fillSnapshots(ctx context.Context, rows []*model.Report, out []*ReportVO) {
	var checkinIDs, commentIDs, userIDs []int64
	for _, r := range rows {
		switch r.TargetType {
		case 1:
			checkinIDs = append(checkinIDs, r.TargetID)
		case 2:
			commentIDs = append(commentIDs, r.TargetID)
		case 3:
			userIDs = append(userIDs, r.TargetID)
		}
	}
	type ckRow struct {
		ID        int64
		Content   string
		ImageURLs string `gorm:"column:image_urls"`
		UserID    int64
		Nickname  string
	}
	cks := map[int64]*ckRow{}
	if len(checkinIDs) > 0 {
		var list []*ckRow
		s.db.WithContext(ctx).Table("checkins").
			Select("`checkins`.`id`, `checkins`.`content`, `checkins`.`image_urls`, `checkins`.`user_id`, `users`.`nickname`").
			Joins("LEFT JOIN `users` ON `users`.`id` = `checkins`.`user_id`").
			Where("`checkins`.`id` IN ?", checkinIDs).Scan(&list)
		for _, it := range list {
			cks[it.ID] = it
		}
	}
	type cmRow struct {
		ID        int64
		CheckinID int64
		Content   string
		UserID    int64
		Nickname  string
	}
	cms := map[int64]*cmRow{}
	if len(commentIDs) > 0 {
		var list []*cmRow
		s.db.WithContext(ctx).Table("comments").
			Select("`comments`.`id`, `comments`.`checkin_id`, `comments`.`content`, `comments`.`user_id`, `users`.`nickname`").
			Joins("LEFT JOIN `users` ON `users`.`id` = `comments`.`user_id`").
			Where("`comments`.`id` IN ?", commentIDs).Scan(&list)
		for _, it := range list {
			cms[it.ID] = it
		}
	}
	type uRow struct {
		ID       int64
		Nickname string
	}
	us := map[int64]*uRow{}
	if len(userIDs) > 0 {
		var list []*uRow
		s.db.WithContext(ctx).Table("users").
			Select("`id`, `nickname`").Where("`id` IN ?", userIDs).Scan(&list)
		for _, it := range list {
			us[it.ID] = it
		}
	}
	for i, r := range rows {
		switch r.TargetType {
		case 1:
			if it := cks[r.TargetID]; it != nil {
				out[i].Snapshot = &ReportSnapshot{Content: it.Content, Images: it.ImageURLs, AuthorID: it.UserID, Author: it.Nickname}
			}
		case 2:
			if it := cms[r.TargetID]; it != nil {
				out[i].Snapshot = &ReportSnapshot{Content: it.Content, AuthorID: it.UserID, Author: it.Nickname, CheckinID: it.CheckinID}
			}
		case 3:
			if it := us[r.TargetID]; it != nil {
				out[i].Snapshot = &ReportSnapshot{AuthorID: it.ID, Author: it.Nickname}
			}
		}
	}
}

// HandleReport 处理举报：delete_content 软删目标内容 / ban_user 封禁目标作者 / dismiss 驳回。
// 处理后回写 reports.status（1 已处理 / 2 驳回）；封禁与删打卡会重建今日微光缓存。
func (s *AdminService) HandleReport(ctx context.Context, id int64, action, note string) error {
	var rep model.Report
	if err := s.db.WithContext(ctx).First(&rep, id).Error; err != nil {
		return err
	}
	if rep.Status != 0 {
		return validateErrf("该举报已处理过")
	}
	switch action {
	case "delete_content":
		if rep.TargetType == 3 {
			return validateErrf("用户举报不支持删内容，请选择封禁或驳回")
		}
		if err := s.adminDeleteTarget(ctx, rep.TargetType, rep.TargetID); err != nil {
			return err
		}
	case "ban_user":
		uid := rep.TargetID
		if rep.TargetType != 3 {
			// 内容举报：定位作者
			var uidQ int64
			table := "checkins"
			if rep.TargetType == 2 {
				table = "comments"
			}
			if err := s.db.WithContext(ctx).Table(table).Select("user_id").
				Where("id = ?", rep.TargetID).Scan(&uidQ).Error; err != nil {
				return err
			}
			if uidQ == 0 {
				return gorm.ErrRecordNotFound
			}
			uid = uidQ
		}
		if err := s.BanUser(ctx, uid); err != nil {
			return err
		}
	case "dismiss":
		// 仅回写状态
	default:
		return validateErrf("action 取值不合法")
	}

	status := int8(1)
	if action == "dismiss" {
		status = 2
	}
	updates := map[string]interface{}{"status": status}
	// 处理备注追加进 detail（有长度护栏，detail 列 255）
	if note != "" && len(rep.Detail)+len(note) < 200 {
		updates["detail"] = rep.Detail + "｜备注：" + note
	}
	return s.db.WithContext(ctx).Model(&model.Report{}).Where("id = ?", id).Updates(updates).Error
}

// adminDeleteTarget 管理端软删：打卡删后重建今日微光（与作者自删同路径语义）。
func (s *AdminService) adminDeleteTarget(ctx context.Context, targetType int8, targetID int64) error {
	switch targetType {
	case 1:
		res := s.db.WithContext(ctx).Model(&model.Checkin{}).
			Where("id = ? AND status = 0", targetID).Update("status", 1)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected > 0 && s.feed != nil {
			today := time.Now().In(cstZone).Format("2006-01-02")
			if err := s.feed.RebuildDailySelected(ctx, today); err != nil {
				return err
			}
		}
	case 2:
		return s.db.WithContext(ctx).Model(&model.Comment{}).
			Where("id = ? AND status = 0", targetID).Update("status", 1).Error
	}
	return nil
}

// BanUser 封禁用户并即时失效其登录态缓存（v0.6.0 T2/T4 配套）。
func (s *AdminService) BanUser(ctx context.Context, uid int64) error {
	res := s.db.WithContext(ctx).Model(&model.User{}).
		Where("id = ? AND status = 0", uid).Update("status", 1)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected > 0 {
		middleware.InvalidateUserStatus(s.rdb, ctx, uid)
		// 作者被封后其内容需从公开流消失——精选候选查询带作者过滤（T4 补），重建缓存即可剔除
		if s.feed != nil {
			today := time.Now().In(cstZone).Format("2006-01-02")
			_ = s.feed.RebuildDailySelected(ctx, today)
		}
	}
	return nil
}

// UnbanUser 解封并即时恢复登录态。
func (s *AdminService) UnbanUser(ctx context.Context, uid int64) error {
	res := s.db.WithContext(ctx).Model(&model.User{}).
		Where("id = ? AND status = 1", uid).Update("status", 0)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected > 0 {
		middleware.InvalidateUserStatus(s.rdb, ctx, uid)
	}
	return nil
}

// ---------- 用户管理（v0.6.0 T4） ----------

// AdminUserVO 管理端用户行。手机号密文存储不可搜索——按昵称/ID 定位。
type AdminUserVO struct {
	ID           int64     `json:"id"`
	Nickname     string    `json:"nickname"`
	AvatarURL    string    `json:"avatar_url"`
	Bio          string    `json:"bio"`
	Status       int8      `json:"status"` // 0正常 1封禁
	CreatedAt    time.Time `json:"created_at"`
	CheckinCount int64     `json:"checkin_count"`
}

// AdminUsers 用户分页列表：昵称模糊搜索，纯数字关键词同时按 ID 精确匹配。
func (s *AdminService) AdminUsers(ctx context.Context, keyword string, page, pageSize int) ([]*AdminUserVO, int64, error) {
	q := s.db.WithContext(ctx).Model(&model.User{})
	if keyword != "" {
		kw := "%" + keyword + "%"
		if id, err := strconv.ParseInt(keyword, 10, 64); err == nil {
			q = q.Where("nickname LIKE ? OR id = ?", kw, id)
		} else {
			q = q.Where("nickname LIKE ?", kw)
		}
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if total == 0 {
		return []*AdminUserVO{}, 0, nil
	}
	var users []*model.User
	if err := q.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&users).Error; err != nil {
		return nil, 0, err
	}
	out := make([]*AdminUserVO, 0, len(users))
	ids := make([]int64, 0, len(users))
	for _, u := range users {
		out = append(out, &AdminUserVO{
			ID: u.ID, Nickname: u.Nickname, AvatarURL: u.AvatarURL,
			Bio: u.Bio, Status: u.Status, CreatedAt: u.CreatedAt,
		})
		ids = append(ids, u.ID)
	}
	// 打卡数批量统计（避免逐行子查询）
	type cntRow struct {
		UserID int64
		N      int64
	}
	var cnts []cntRow
	if err := s.db.WithContext(ctx).Table("checkins").
		Select("user_id, COUNT(*) AS n").
		Where("user_id IN ? AND status = 0", ids).
		Group("user_id").Scan(&cnts).Error; err == nil {
		m := map[int64]int64{}
		for _, c := range cnts {
			m[c.UserID] = c.N
		}
		for _, vo := range out {
			vo.CheckinCount = m[vo.ID]
		}
	}
	return out, total, nil
}

// AdminCheckinItem 管理端打卡行（巡检/用户详情共用，含未公开与已删）。
type AdminCheckinItem struct {
	ID          int64     `json:"id"`
	UserID      int64     `json:"user_id"`
	Author      string    `json:"author"`
	Category    int8      `json:"category"`
	Content     string    `json:"content"`
	Images      string    `json:"images,omitempty"` // image_urls 原样 JSON
	Visibility  int8      `json:"visibility"`
	Status      int8      `json:"status"` // 0正常 1已删
	CheckinDate string    `json:"checkin_date"`
	CreatedAt   time.Time `json:"created_at"`
}

const adminCheckinSelect = "`checkins`.`id`, `checkins`.`user_id`, `users`.`nickname` AS `author`, `checkins`.`category`, " +
	"`checkins`.`content`, `checkins`.`image_urls` AS `images`, `checkins`.`visibility`, `checkins`.`status`, " +
	"`checkins`.`checkin_date`, `checkins`.`created_at`"

// trimDate DATE 列可能扫出 RFC3339 长串，取前 10 位（踩坑 12）。
func trimDate(s string) string {
	if len(s) > 10 {
		return s[:10]
	}
	return s
}

// AdminUserDetail 用户详情：资料 + 统计 + 最近 10 条打卡（含未公开，判罚参考）。
func (s *AdminService) AdminUserDetail(ctx context.Context, uid int64) (*AdminUserVO, []*AdminCheckinItem, error) {
	var u model.User
	if err := s.db.WithContext(ctx).First(&u, uid).Error; err != nil {
		return nil, nil, err
	}
	vo := &AdminUserVO{
		ID: u.ID, Nickname: u.Nickname, AvatarURL: u.AvatarURL,
		Bio: u.Bio, Status: u.Status, CreatedAt: u.CreatedAt,
	}
	_ = s.db.WithContext(ctx).Table("checkins").
		Where("user_id = ? AND status = 0", uid).Count(&vo.CheckinCount).Error
	var items []*AdminCheckinItem
	if err := s.db.WithContext(ctx).Table("checkins").
		Select(adminCheckinSelect).
		Joins("LEFT JOIN `users` ON `users`.`id` = `checkins`.`user_id`").
		Where("checkins.user_id = ?", uid).
		Order("checkins.id DESC").Limit(10).Scan(&items).Error; err != nil {
		return vo, nil, err
	}
	for _, it := range items {
		it.CheckinDate = trimDate(it.CheckinDate)
	}
	return vo, items, nil
}

// SetUserStatus 封禁(1)/解封(0)，内部走 Ban/Unban 保证缓存即时失效。
func (s *AdminService) SetUserStatus(ctx context.Context, uid int64, status int8) error {
	if status != 0 && status != 1 {
		return validateErrf("status 取值不合法")
	}
	if status == 1 {
		return s.BanUser(ctx, uid)
	}
	return s.UnbanUser(ctx, uid)
}

// ---------- 内容巡检（v0.6.0 T5） ----------

// AdminCheckins 全量打卡巡检：关键词搜正文，品类过滤，含未公开与已删。
func (s *AdminService) AdminCheckins(ctx context.Context, keyword string, category int8, page, pageSize int) ([]*AdminCheckinItem, int64, error) {
	q := s.db.WithContext(ctx).Table("checkins").
		Joins("LEFT JOIN `users` ON `users`.`id` = `checkins`.`user_id`")
	if keyword != "" {
		q = q.Where("checkins.content LIKE ?", "%"+keyword+"%")
	}
	if category > 0 {
		q = q.Where("checkins.category = ?", category)
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if total == 0 {
		return []*AdminCheckinItem{}, 0, nil
	}
	var items []*AdminCheckinItem
	if err := q.Select(adminCheckinSelect).
		Order("checkins.id DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).Scan(&items).Error; err != nil {
		return nil, 0, err
	}
	for _, it := range items {
		it.CheckinDate = trimDate(it.CheckinDate)
	}
	return items, total, nil
}

// AdminDeleteCheckin 管理端下架打卡（软删 + 重建今日微光）。
func (s *AdminService) AdminDeleteCheckin(ctx context.Context, id int64) error {
	return s.adminDeleteTarget(ctx, 1, id)
}

// AdminCommentItem 管理端留言行。
type AdminCommentItem struct {
	ID        int64     `json:"id"`
	CheckinID int64     `json:"checkin_id"`
	UserID    int64     `json:"user_id"`
	Author    string    `json:"author"`
	Content   string    `json:"content"`
	Status    int8      `json:"status"` // 0正常 1已删
	CreatedAt time.Time `json:"created_at"`
}

// AdminComments 留言巡检：关键词搜索。
func (s *AdminService) AdminComments(ctx context.Context, keyword string, page, pageSize int) ([]*AdminCommentItem, int64, error) {
	q := s.db.WithContext(ctx).Table("comments").
		Joins("LEFT JOIN `users` ON `users`.`id` = `comments`.`user_id`")
	if keyword != "" {
		q = q.Where("comments.content LIKE ?", "%"+keyword+"%")
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if total == 0 {
		return []*AdminCommentItem{}, 0, nil
	}
	var items []*AdminCommentItem
	if err := q.Select("`comments`.`id`, `comments`.`checkin_id`, `comments`.`user_id`, `users`.`nickname` AS `author`, " +
		"`comments`.`content`, `comments`.`status`, `comments`.`created_at`").
		Order("comments.id DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).Scan(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// AdminDeleteComment 管理端删留言（软删）。
func (s *AdminService) AdminDeleteComment(ctx context.Context, id int64) error {
	return s.adminDeleteTarget(ctx, 2, id)
}

// ---------- 系统公告（v0.6.0 T6） ----------

// Announce 系统公告：写入 notifications（type=5，extra=文案，客户端通知页已支持渲染）。
// user_ids 为空发全员（正常状态用户）；公告不经内容审核（管理员内容信任）。
// 返回实际下发条数。
func (s *AdminService) Announce(ctx context.Context, userIDs []int64, content string) (int64, error) {
	content = strings.TrimSpace(content)
	if content == "" {
		return 0, validateErrf("公告内容不能为空")
	}
	// extra 列 varchar(140)，按字符数限长（中文一字一符）
	if len([]rune(content)) > 140 {
		return 0, validateErrf("公告内容不能超过 140 字")
	}
	targets := userIDs
	if len(targets) == 0 {
		if err := s.db.WithContext(ctx).Table("users").
			Where("status = 0").Pluck("id", &targets).Error; err != nil {
			return 0, err
		}
	}
	if len(targets) == 0 {
		return 0, nil
	}
	rows := make([]model.Notification, 0, len(targets))
	for _, uid := range targets {
		rows = append(rows, model.Notification{UserID: uid, Type: 5, Extra: content})
	}
	// 批量 INSERT，一条多 VALUES，按 500 一批（逐条循环单插在全员场景不可接受）
	const batch = 500
	for i := 0; i < len(rows); i += batch {
		end := i + batch
		if end > len(rows) {
			end = len(rows)
		}
		batchRows := rows[i:end]
		if err := s.db.WithContext(ctx).Create(&batchRows).Error; err != nil {
			return 0, err
		}
	}
	return int64(len(rows)), nil
}

// ---------- 趋势指标（v0.6.0 T7） ----------

// TrendPoint 单日趋势点。DAU 按当日有正常打卡的去重用户数。
type TrendPoint struct {
	Date     string `json:"date"`
	DAU      int64  `json:"dau"`
	Checkins int64  `json:"checkins"`
	NewUsers int64  `json:"new_users"`
}

// Trend 近 N 天（1–60，缺省 14）逐日趋势：打卡数/DAU 按 checkin_date，
// 新增用户按 created_at。缺数日期补零，保证前端连线完整。
func (s *AdminService) Trend(ctx context.Context, days int) ([]*TrendPoint, error) {
	if days < 1 {
		days = 14
	}
	if days > 60 {
		days = 60
	}
	today := time.Now().In(cstZone)
	start := today.AddDate(0, 0, -(days - 1)).Format("2006-01-02")

	type dateCount struct {
		Date string
		N    int64
		DAU  int64
	}
	var ck []dateCount
	if err := s.db.WithContext(ctx).Table("checkins").
		Select("checkin_date AS `date`, COUNT(*) AS n, COUNT(DISTINCT user_id) AS dau").
		Where("status = 0 AND checkin_date >= ?", start).
		Group("checkin_date").Scan(&ck).Error; err != nil {
		return nil, err
	}
	var nu []dateCount
	if err := s.db.WithContext(ctx).Table("users").
		Select("DATE(created_at) AS `date`, COUNT(*) AS n").
		Where("created_at >= ?", start+" 00:00:00").
		Group("DATE(created_at)").Scan(&nu).Error; err != nil {
		return nil, err
	}

	ckMap := map[string]*dateCount{}
	for i := range ck {
		d := trimDate(ck[i].Date)
		ck[i].Date = d
		ckMap[d] = &ck[i]
	}
	nuMap := map[string]int64{}
	for _, r := range nu {
		nuMap[trimDate(r.Date)] = r.N
	}

	out := make([]*TrendPoint, 0, days)
	for i := 0; i < days; i++ {
		d := today.AddDate(0, 0, -(days - 1 - i)).Format("2006-01-02")
		p := &TrendPoint{Date: d}
		if c := ckMap[d]; c != nil {
			p.Checkins = c.N
			p.DAU = c.DAU
		}
		p.NewUsers = nuMap[d]
		out = append(out, p)
	}
	return out, nil
}

// ---------- 反馈查看与操作留底（v0.6.0 T8/T9） ----------

// AdminFeedbackItem 反馈列表行。
type AdminFeedbackItem struct {
	ID        int64     `json:"id"`
	UserID    int64     `json:"user_id"`
	Author    string    `json:"author"`
	Content   string    `json:"content"`
	Status    int8      `json:"status"` // 0待处理 1已处理
	CreatedAt time.Time `json:"created_at"`
}

// AdminFeedback 反馈分页列表（status<0 全部）。
func (s *AdminService) AdminFeedback(ctx context.Context, status int8, page, pageSize int) ([]*AdminFeedbackItem, int64, error) {
	q := s.db.WithContext(ctx).Table("feedback").
		Joins("LEFT JOIN `users` ON `users`.`id` = `feedback`.`user_id`")
	if status >= 0 {
		q = q.Where("feedback.status = ?", status)
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if total == 0 {
		return []*AdminFeedbackItem{}, 0, nil
	}
	var items []*AdminFeedbackItem
	if err := q.Select("`feedback`.`id`, `feedback`.`user_id`, `users`.`nickname` AS `author`, " +
		"`feedback`.`content`, `feedback`.`status`, `feedback`.`created_at`").
		Order("feedback.id DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).Scan(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// MarkFeedbackDone 标记反馈已处理。
func (s *AdminService) MarkFeedbackDone(ctx context.Context, id int64) error {
	return s.db.WithContext(ctx).Model(&model.Feedback{}).
		Where("id = ? AND status = 0", id).Update("status", 1).Error
}

// LogAction 管理操作留底：失败不阻断业务（日志非关键路径）。
func (s *AdminService) LogAction(ctx context.Context, action, targetType string, targetID int64, detail string) {
	if r := []rune(detail); len(r) > 80 {
		detail = string(r[:80])
	}
	_ = s.db.WithContext(ctx).Create(&model.AdminAction{
		Action: action, TargetType: targetType, TargetID: targetID, Detail: detail,
	}).Error
}

// Actions 操作日志分页列表（新→旧）。
func (s *AdminService) Actions(ctx context.Context, page, pageSize int) ([]*model.AdminAction, int64, error) {
	q := s.db.WithContext(ctx).Model(&model.AdminAction{})
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if total == 0 {
		return []*model.AdminAction{}, 0, nil
	}
	var items []*model.AdminAction
	if err := q.Order("id DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).Find(&items).Error; err != nil {
		return nil, 0, err
	}
	return items, total, nil
}
