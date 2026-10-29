package service

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	cryptorand "crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	mathrand "math/rand"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/model"
	"shinepick/internal/pkg/jwt"
	"shinepick/internal/pkg/sms"
	"shinepick/internal/repository"
)

const (
	smsTTL      = 5 * time.Minute
	smsCooldown = time.Minute
	maxAttempts = 5
	refreshTTL  = 30 * 24 * time.Hour
	accessTTL   = 7 * 24 * time.Hour
	// phoneAESKey 用于手机号加密派生密钥；TODO: 生产环境迁移到配置/密钥管理，勿硬编码
	phoneAESKey = "shinepick-phone-key"
	phoneSalt   = "shinepick-salt-v1"
)

// 哨兵错误：handler 用 errors.Is 判断业务分支。
var (
	ErrFrequent   = errors.New("frequent")
	ErrSmsInvalid = errors.New("sms_invalid")
	ErrUnauthorized = errors.New("unauthorized")
)

// AuthService 账号体系：验证码、登录、刷新。
type AuthService struct {
	db   *gorm.DB
	rdb  *redis.Client
	jwt  *jwt.Manager
	sms  *sms.Sender
	repo *repository.UserRepo
}

func NewAuthService(db *gorm.DB, rdb *redis.Client, jm *jwt.Manager, sender *sms.Sender, repo *repository.UserRepo) *AuthService {
	return &AuthService{db: db, rdb: rdb, jwt: jm, sms: sender, repo: repo}
}

// SendSmsCode 发送验证码：60s 频控 + Redis 存储。
func (s *AuthService) SendSmsCode(ctx context.Context, phone string) error {
	cooldownKey := "rl:sms:" + phone
	if n, err := s.rdb.Get(ctx, cooldownKey).Int(); err == nil && n == 1 {
		return ErrFrequent
	}
	codeVal := fmt.Sprintf("%06d", mathrand.Intn(1000000))
	if s.sms.IsMock() {
		codeVal = "123456" // dev 固定验证码，便于联调（S1 计划 §3.1）
	}
	if err := s.rdb.Set(ctx, "sms:"+phone, codeVal, smsTTL).Err(); err != nil {
		return err
	}
	if err := s.rdb.Set(ctx, cooldownKey, "1", smsCooldown).Err(); err != nil {
		return err
	}
	return s.sms.Send(phone, codeVal)
}

// Login 校验验证码 → 查/建用户 → 签发双 Token。
func (s *AuthService) Login(ctx context.Context, phone, smsCode string) (*LoginResult, error) {
	// 1. 校验验证码（错误 5 次作废）
	key := "sms:" + phone
	stored, err := s.rdb.Get(ctx, key).Result()
	if errors.Is(err, redis.Nil) || stored != smsCode {
		if err := s.failAttempt(ctx, key); err != nil {
			return nil, err
		}
		return nil, ErrSmsInvalid
	}
	s.rdb.Del(ctx, key)

	// 2. 查/建用户
	hash := phoneHash(phone)
	u, err := s.repo.ByPhoneHash(ctx, hash)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		enc, salt, e := encryptPhone(phone)
		if e != nil {
			return nil, e
		}
		u = &model.User{PhoneHash: hash}
		if e := s.repo.Create(ctx, u, &model.UserSecure{PhoneEnc: enc, Salt: salt}); e != nil {
			return nil, e
		}
		// 默认昵称依赖 ID，单独更新
		u.Nickname = fmt.Sprintf("拾光用户_%d", u.ID)
		if e := s.db.WithContext(ctx).Model(u).Update("nickname", u.Nickname).Error; e != nil {
			return nil, e
		}
	} else if err != nil {
		return nil, err
	}

	// 3. 签发双 Token
	access, err := s.jwt.Generate(u.ID, accessTTL)
	if err != nil {
		return nil, err
	}
	refresh := "rt_" + randStr(32)
	if err := s.rdb.Set(ctx, "rt:"+refresh, u.ID, refreshTTL).Err(); err != nil {
		return nil, err
	}

	return &LoginResult{
		AccessToken:  access,
		RefreshToken: refresh,
		ExpiresIn:    int(accessTTL.Seconds()),
		User:         toVO(u, maskPhone(phone)),
	}, nil
}

// Refresh 轮换 refresh token。
func (s *AuthService) Refresh(ctx context.Context, refreshToken string) (*LoginResult, error) {
	uid, err := s.rdb.Get(ctx, "rt:"+refreshToken).Int64()
	if errors.Is(err, redis.Nil) {
		return nil, ErrUnauthorized
	}
	if err != nil {
		return nil, err
	}
	// 用一次删一次（轮换）
	s.rdb.Del(ctx, "rt:"+refreshToken)

	access, err := s.jwt.Generate(uid, accessTTL)
	if err != nil {
		return nil, err
	}
	newRefresh := "rt_" + randStr(32)
	if err := s.rdb.Set(ctx, "rt:"+newRefresh, uid, refreshTTL).Err(); err != nil {
		return nil, err
	}
	return &LoginResult{
		AccessToken:  access,
		RefreshToken: newRefresh,
		ExpiresIn:    int(accessTTL.Seconds()),
	}, nil
}

// failAttempt 记录错误次数，达到上限删除验证码。
func (s *AuthService) failAttempt(ctx context.Context, key string) error {
	n, err := s.rdb.Incr(ctx, key+":attempts").Result()
	if err != nil {
		return err
	}
	s.rdb.Expire(ctx, key+":attempts", smsTTL)
	if n >= maxAttempts {
		s.rdb.Del(ctx, key)
	}
	return nil
}

// ---------------- VO / 工具 ----------------

type LoginResult struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	ExpiresIn    int         `json:"expires_in"`
	User         *UserVO     `json:"user,omitempty"`
}

type UserVO struct {
	ID          int64  `json:"id"`
	Nickname    string `json:"nickname"`
	AvatarURL   string `json:"avatar_url"`
	PhoneMasked string `json:"phone_masked"`
}

func toVO(u *model.User, masked string) *UserVO {
	return &UserVO{ID: u.ID, Nickname: u.Nickname, AvatarURL: u.AvatarURL, PhoneMasked: masked}
}

func phoneHash(phone string) string {
	sum := sha256.Sum256([]byte(phone + phoneSalt))
	return hex.EncodeToString(sum[:])
}

func encryptPhone(phone string) ([]byte, string, error) {
	salt := randStr(8)
	key := sha256.Sum256([]byte(phoneAESKey + salt))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, "", err
	}
	// GCM 认证加密
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := cryptorand.Read(nonce); err != nil {
		return nil, "", err
	}
	sealed := gcm.Seal(nonce, nonce, []byte(phone), nil)
	enc := []byte(base64.StdEncoding.EncodeToString(sealed))
	return enc, salt, nil
}

func maskPhone(phone string) string {
	if len(phone) != 11 {
		return phone
	}
	return phone[:3] + "****" + phone[7:]
}

func randStr(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[mathrand.Intn(len(letters))]
	}
	return string(b)
}
