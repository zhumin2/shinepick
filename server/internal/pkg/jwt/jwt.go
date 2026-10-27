package jwt

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims JWT 载荷。
type Claims struct {
	UID int64 `json:"uid"`
	jwt.RegisteredClaims
}

// Manager 负责签发与校验 access token。
type Manager struct {
	secret []byte
}

func NewManager(secret string) *Manager {
	return &Manager{secret: []byte(secret)}
}

// Generate 签发 access token。
func (m *Manager) Generate(uid int64, ttl time.Duration) (string, error) {
	claims := Claims{
		UID: uid,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.secret)
}

// Parse 校验并解析 access token。
func (m *Manager) Parse(token string) (*Claims, error) {
	claims := &Claims{}
	t, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (interface{}, error) {
		return m.secret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		return nil, err
	}
	if !t.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
