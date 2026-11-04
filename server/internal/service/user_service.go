package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"shinepick/internal/model"
	"shinepick/internal/repository"
)

// ProfilePatch 用户资料局部更新（指针字段区分「未传」与「清空」）。
type ProfilePatch struct {
	Nickname *string `json:"nickname"`
	Bio      *string `json:"bio"`
	Gender   *int8   `json:"gender"`
	City     *string `json:"city"`
	Birthday *string `json:"birthday"` // YYYY-MM-DD
}

// UserStats 我的页统计（companions 在 S5 同路人上线后填充）。
type UserStats struct {
	CheckinCount int `json:"checkin_count"` // 累计打卡次数（每次 +1）
	CheckinDays  int `json:"checkin_days"`  // 有打卡的天数（按日去重）
	StreakDays   int `json:"streak_days"`   // 连续打卡天数
	Companions   int `json:"companions"`    // 同路人数
}

// ProfileVO 我的页资料视图。
type ProfileVO struct {
	ID        int64      `json:"id"`
	Nickname  string     `json:"nickname"`
	AvatarURL string     `json:"avatar_url"`
	Bio       string     `json:"bio"`
	Gender    int8       `json:"gender"`
	City      string     `json:"city"`
	Birthday  *string    `json:"birthday,omitempty"` // YYYY-MM-DD
	IsMinor   bool       `json:"is_minor"`
	CreatedAt time.Time  `json:"created_at"`
	Stats     *UserStats `json:"stats,omitempty"`
}

// UserService 用户资料（S2-01/S2-02；S3 起统计含打卡数据，S5 起含同路人）。
type UserService struct {
	repo       *repository.UserRepo
	checkins   *repository.CheckinRepo
	inter      *repository.InteractionRepo
	uploadDir  string // 头像存储根目录（dev 本地驱动）
	publicBase string // 对外可访问的基础 URL（拼接头像链接）
}

func NewUserService(
	repo *repository.UserRepo,
	checkins *repository.CheckinRepo,
	inter *repository.InteractionRepo,
	uploadDir, publicBase string,
) *UserService {
	return &UserService{repo: repo, checkins: checkins, inter: inter, uploadDir: uploadDir, publicBase: publicBase}
}

// Profile 返回我的资料（含打卡与同路人统计）。
func (s *UserService) Profile(ctx context.Context, uid int64) (*ProfileVO, error) {
	u, err := s.repo.ByID(ctx, uid)
	if err != nil {
		return nil, err
	}
	stats := &UserStats{}
	if s.checkins != nil {
		dates, err := s.checkins.DistinctDates(ctx, uid, 400)
		if err == nil { // 统计查询失败不阻塞资料返回
			checkinDays, streakDays := computeStreak(dates, time.Now().In(cstZone))
			stats.CheckinDays = checkinDays
			stats.StreakDays = streakDays
		}
		if n, err := s.checkins.CountByUser(ctx, uid); err == nil {
			stats.CheckinCount = int(n)
		}
	}
	if s.inter != nil {
		if n, err := s.inter.CompanionCount(ctx, uid); err == nil {
			stats.Companions = int(n)
		}
	}
	return toProfileVO(u, stats), nil
}

// OtherProfile 他人公开主页（S9）：只暴露公开字段（无手机号/未成年标记）。
// 返回 (profile, notFound)。
func (s *UserService) OtherProfile(ctx context.Context, viewerUID, targetUID int64) (*ProfileVO, bool, error) {
	if targetUID == viewerUID {
		vo, err := s.Profile(ctx, targetUID)
		return vo, false, err
	}
	u, err := s.repo.ByID(ctx, targetUID)
	if err != nil {
		return nil, true, err
	}
	if u.Status != 0 {
		return nil, true, nil // 封禁用户主页不可见
	}
	stats := &UserStats{}
	if s.checkins != nil {
		if n, err := s.checkins.CountPublicByUser(ctx, targetUID); err == nil {
			stats.CheckinCount = int(n)
		}
	}
	vo := toProfileVO(u, stats)
	vo.IsMinor = false // 他人视角不暴露未成年标记
	return vo, false, nil
}

// CompanionVO 同路人列表项（我的页/他人主页共用，只含公开信息）。
type CompanionVO struct {
	ID        int64     `json:"id"`
	Nickname  string    `json:"nickname"`
	AvatarURL string    `json:"avatar_url"`
	Since     time.Time `json:"since"` // 建立同路的时间
}

// Companions 某用户的同路人列表（封禁账号已在查询中过滤）。
func (s *UserService) Companions(ctx context.Context, uid int64) ([]*CompanionVO, error) {
	if s.inter == nil {
		return []*CompanionVO{}, nil
	}
	rows, err := s.inter.ListCompanions(ctx, uid)
	if err != nil {
		return nil, err
	}
	out := make([]*CompanionVO, 0, len(rows))
	for _, r := range rows {
		out = append(out, &CompanionVO{
			ID: r.UID, Nickname: r.Nickname, AvatarURL: r.AvatarURL, Since: r.Since,
		})
	}
	return out, nil
}

// DailyPoint 周报中的单日数据。
type DailyPoint struct {
	Date     string `json:"date"`    // YYYY-MM-DD
	Weekday  int    `json:"weekday"` // 1=周一 ... 7=周日
	Count    int    `json:"count"`
	Category int8   `json:"category"` // 当天主品类（出现最多），0=当天无打卡
}

// CategoryStat 品类分布项。
type CategoryStat struct {
	Category int8 `json:"category"`
	Count    int  `json:"count"`
}

// WeeklyReportVO 拾光周报（周一至周日，东八区）。
type WeeklyReportVO struct {
	StartDate  string         `json:"start_date"`
	EndDate    string         `json:"end_date"`
	Count      int            `json:"count"`       // 本周打卡次数
	Days       int            `json:"days"`        // 本周有打卡的天数
	StreakDays int            `json:"streak_days"` // 当前连续天数（非仅本周）
	LastCount  int            `json:"last_count"`  // 上周打卡次数
	Delta      int            `json:"delta"`       // 本周 - 上周
	Daily      []DailyPoint   `json:"daily"`
	Categories []CategoryStat `json:"categories"`
}

// WeeklyReport 本周拾光汇总：每日柱状、品类分布、与上周对比、连续天数。
func (s *UserService) WeeklyReport(ctx context.Context, uid int64) (*WeeklyReportVO, error) {
	now := time.Now().In(cstZone)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, cstZone)
	// 周一为一周起点：Weekday() 周日=0，换算为 0(周一)..6(周日)
	offset := (int(now.Weekday()) + 6) % 7
	monday := today.AddDate(0, 0, -offset)
	sunday := monday.AddDate(0, 0, 6)
	lastMonday := monday.AddDate(0, 0, -7)
	lastSunday := monday.AddDate(0, 0, -1)

	vo := &WeeklyReportVO{
		StartDate: monday.Format("2006-01-02"),
		EndDate:   sunday.Format("2006-01-02"),
		Daily:     make([]DailyPoint, 7),
	}

	// 每日槽位（即使没打卡也占位，客户端画 7 根柱子）
	for i := 0; i < 7; i++ {
		d := monday.AddDate(0, 0, i)
		vo.Daily[i] = DailyPoint{Date: d.Format("2006-01-02"), Weekday: i + 1}
	}
	if s.checkins == nil {
		return vo, nil
	}

	list, err := s.checkins.BriefInRange(ctx, uid,
		vo.StartDate, vo.EndDate)
	if err != nil {
		return nil, err
	}
	// 日聚合 + 品类聚合 + 每日主品类
	dayCount := map[string]int{}
	dayCat := map[string]map[int8]int{}
	catCount := map[int8]int{}
	for _, c := range list {
		d := normalizeDate(c.CheckinDate)
		dayCount[d]++
		catCount[c.Category]++
		if dayCat[d] == nil {
			dayCat[d] = map[int8]int{}
		}
		dayCat[d][c.Category]++
	}
	vo.Count = len(list)
	for i := range vo.Daily {
		d := vo.Daily[i].Date
		vo.Daily[i].Count = dayCount[d]
		if cnt := len(dayCat[d]); cnt > 0 {
			vo.Daily[i].Category = dominantCategory(dayCat[d])
		}
	}
	for _, c := range vo.Daily {
		if c.Count > 0 {
			vo.Days++
		}
	}
	for cat, n := range catCount {
		vo.Categories = append(vo.Categories, CategoryStat{Category: cat, Count: n})
	}
	sort.Slice(vo.Categories, func(i, j int) bool {
		if vo.Categories[i].Count != vo.Categories[j].Count {
			return vo.Categories[i].Count > vo.Categories[j].Count
		}
		return vo.Categories[i].Category < vo.Categories[j].Category
	})

	// 上周对比
	if last, err := s.checkins.BriefInRange(ctx, uid,
		lastMonday.Format("2006-01-02"), lastSunday.Format("2006-01-02")); err == nil {
		vo.LastCount = len(last)
	}
	vo.Delta = vo.Count - vo.LastCount

	// 连续天数（跨周连续，不是仅本周）
	if dates, err := s.checkins.DistinctDates(ctx, uid, 400); err == nil {
		_, vo.StreakDays = computeStreak(dates, now)
	}
	return vo, nil
}

// dominantCategory 取出现次数最多的品类（并列时取编号小的，保证稳定）。
func dominantCategory(m map[int8]int) int8 {
	var best int8
	bestN := -1
	for cat, n := range m {
		if n > bestN || (n == bestN && cat < best) {
			best, bestN = cat, n
		}
	}
	return best
}

// normalizeDate 归一日期字符串：兼容 "2006-01-02" 与 parseTime 扫描出的
// RFC3339 全格式（DATE 列经 database/sql 转 string 会带时间与时区）。
func normalizeDate(d string) string {
	if len(d) >= 10 {
		return d[:10]
	}
	return d
}

// dateOnly normalizeDate 的同义别名，供其他 service 文件使用。
func dateOnly(d string) string { return normalizeDate(d) }

// computeStreak 由去重打卡日期计算 打卡总天数 与 连续天数。
// 连续天数：从今天往前数连续打卡的天数；今天未打卡不扣断（当日尚未结束），
// 从昨天开始数。输入顺序不敏感（内部降序排序）。
func computeStreak(dates []string, now time.Time) (checkinDays, streakDays int) {
	checkinDays = len(dates)
	if checkinDays == 0 {
		return 0, 0
	}
	sorted := make([]string, 0, len(dates))
	for _, d := range dates {
		sorted = append(sorted, normalizeDate(d))
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] > sorted[j] })

	today := now.Format("2006-01-02")
	yesterday := now.AddDate(0, 0, -1).Format("2006-01-02")

	expected := today
	if sorted[0] != today {
		if sorted[0] != yesterday {
			return checkinDays, 0
		}
		expected = yesterday
	}
	for _, d := range sorted {
		if d != expected {
			break
		}
		streakDays++
		t, err := time.ParseInLocation("2006-01-02", expected, cstZone)
		if err != nil {
			break
		}
		expected = t.AddDate(0, 0, -1).Format("2006-01-02")
	}
	return checkinDays, streakDays
}

// UpdateProfile 校验并落库资料变更，返回更新后的资料。
func (s *UserService) UpdateProfile(ctx context.Context, uid int64, patch *ProfilePatch) (*ProfileVO, error) {
	u, err := s.repo.ByID(ctx, uid)
	if err != nil {
		return nil, err
	}
	changes, err := applyPatch(u, patch, time.Now())
	if err != nil {
		return nil, err
	}
	if len(changes) > 0 {
		if err := s.repo.UpdateFields(ctx, uid, changes); err != nil {
			return nil, err
		}
	}
	updated, err := s.repo.ByID(ctx, uid)
	if err != nil {
		return nil, err
	}
	return toProfileVO(updated, nil), nil
}

// SaveAvatar 校验并保存头像文件（dev 本地驱动；OSS 直传在生产接入，见技术文档 8.3）。
func (s *UserService) SaveAvatar(ctx context.Context, uid int64, fh *multipart.FileHeader) (string, error) {
	const maxSize = 2 << 20 // 2MB
	if fh.Size <= 0 || fh.Size > maxSize {
		return "", validateErrf("头像文件需在 2MB 以内")
	}
	ext := avatarExt(fh.Filename)
	if ext == "" {
		return "", validateErrf("头像仅支持 jpg/png/webp 格式")
	}
	src, err := fh.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	dir := filepath.Join(s.uploadDir, "avatars")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	name := fmt.Sprintf("u%d_%d%s", uid, time.Now().UnixMilli(), ext)
	dst, err := os.Create(filepath.Join(dir, name))
	if err != nil {
		return "", err
	}
	defer dst.Close()
	if _, err := io.Copy(dst, src); err != nil {
		return "", err
	}

	url := strings.TrimRight(s.publicBase, "/") + "/static/avatars/" + name
	if err := s.repo.UpdateFields(ctx, uid, map[string]interface{}{"avatar_url": url}); err != nil {
		return "", err
	}
	return url, nil
}

// avatarExt 白名单扩展名（统一小写，.jpeg 归一为 .jpg）。
func avatarExt(filename string) string {
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".jpg", ".jpeg":
		return ".jpg"
	case ".png":
		return ".png"
	case ".webp":
		return ".webp"
	default:
		return ""
	}
}

// applyPatch 校验字段并应用到内存模型，返回 GORM Updates 用的脏字段集。
// 校验规则对齐迁移 0001 的列宽（nickname 30 / bio 140 / city 50）。
func applyPatch(u *model.User, p *ProfilePatch, now time.Time) (map[string]interface{}, error) {
	changes := map[string]interface{}{}
	if p == nil {
		return changes, nil
	}
	if p.Nickname != nil {
		nick := strings.TrimSpace(*p.Nickname)
		if n := utf8.RuneCountInString(nick); n < 1 || n > 30 {
			return nil, validateErrf("昵称需为 1-30 个字符")
		}
		u.Nickname = nick
		changes["nickname"] = nick
	}
	if p.Bio != nil {
		if utf8.RuneCountInString(*p.Bio) > 140 {
			return nil, validateErrf("简介不能超过 140 字")
		}
		u.Bio = *p.Bio
		changes["bio"] = *p.Bio
	}
	if p.Gender != nil {
		if *p.Gender < 0 || *p.Gender > 2 {
			return nil, validateErrf("性别取值不合法")
		}
		u.Gender = *p.Gender
		changes["gender"] = *p.Gender
	}
	if p.City != nil {
		if utf8.RuneCountInString(*p.City) > 50 {
			return nil, validateErrf("城市不能超过 50 字")
		}
		u.City = *p.City
		changes["city"] = *p.City
	}
	if p.Birthday != nil {
		bd, err := time.ParseInLocation("2006-01-02", *p.Birthday, cstZone)
		if err != nil {
			return nil, validateErrf("生日格式应为 YYYY-MM-DD")
		}
		if bd.After(now) {
			return nil, validateErrf("生日不能晚于今天")
		}
		u.Birthday = &bd
		u.IsMinor = deriveMinor(bd, now)
		changes["birthday"] = &bd
		changes["is_minor"] = u.IsMinor
	}
	return changes, nil
}

// cstZone 业务时区：东八区（技术文档 4.3 checkin_date 同口径）。
var cstZone = time.FixedZone("CST", 8*3600)

// CstZone 供其他模块取业务时区。
func CstZone() *time.Location { return cstZone }

// deriveMinor 未成年人标记：未满 18 周岁（按东八区日历计算）。
func deriveMinor(birthday, now time.Time) int8 {
	b := birthday.In(cstZone)
	n := now.In(cstZone)
	age := n.Year() - b.Year()
	// 未到生日则减一
	if n.Month() < b.Month() || (n.Month() == b.Month() && n.Day() < b.Day()) {
		age--
	}
	if age < 18 {
		return 1
	}
	return 0
}

func toProfileVO(u *model.User, stats *UserStats) *ProfileVO {
	vo := &ProfileVO{
		ID:        u.ID,
		Nickname:  u.Nickname,
		AvatarURL: u.AvatarURL,
		Bio:       u.Bio,
		Gender:    u.Gender,
		City:      u.City,
		IsMinor:   u.IsMinor == 1,
		CreatedAt: u.CreatedAt,
		Stats:     stats,
	}
	if u.Birthday != nil {
		s := u.Birthday.In(cstZone).Format("2006-01-02")
		vo.Birthday = &s
	}
	return vo
}

// ErrUserNotFound 统一未找到语义（handler 映射 5001）。
var ErrUserNotFound = errors.New("user_not_found")

// ValidationError 参数/规则校验失败（文案可直接展示给用户，映射 1001）。
type ValidationError struct{ msg string }

func (e *ValidationError) Error() string { return e.msg }

func validateErrf(format string, a ...interface{}) error {
	return &ValidationError{msg: fmt.Sprintf(format, a...)}
}
