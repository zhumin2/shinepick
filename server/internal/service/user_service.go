package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
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

// UserStats 统计骨架（S3 打卡、S5 同路人上线后填充真实值）。
type UserStats struct {
	CheckinDays int `json:"checkin_days"`
	StreakDays  int `json:"streak_days"`
	Companions  int `json:"companions"`
}

// ProfileVO 我的页资料视图。
type ProfileVO struct {
	ID          int64      `json:"id"`
	Nickname    string     `json:"nickname"`
	AvatarURL   string     `json:"avatar_url"`
	Bio         string     `json:"bio"`
	Gender      int8       `json:"gender"`
	City        string     `json:"city"`
	Birthday    *string    `json:"birthday,omitempty"` // YYYY-MM-DD
	IsMinor     bool       `json:"is_minor"`
	CreatedAt   time.Time  `json:"created_at"`
	Stats       *UserStats `json:"stats,omitempty"`
}

// UserService 用户资料（S2-01/S2-02）。
type UserService struct {
	repo         *repository.UserRepo
	uploadDir    string // 头像存储根目录（dev 本地驱动）
	publicBase   string // 对外可访问的基础 URL（拼接头像链接）
}

func NewUserService(repo *repository.UserRepo, uploadDir, publicBase string) *UserService {
	return &UserService{repo: repo, uploadDir: uploadDir, publicBase: publicBase}
}

// Profile 返回我的资料（含统计骨架）。
func (s *UserService) Profile(ctx context.Context, uid int64) (*ProfileVO, error) {
	u, err := s.repo.ByID(ctx, uid)
	if err != nil {
		return nil, err
	}
	return toProfileVO(u, &UserStats{}), nil
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
