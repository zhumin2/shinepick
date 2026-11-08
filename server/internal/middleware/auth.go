package middleware

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/pkg/jwt"
)

// 用户状态缓存 key 前缀。封禁/解封时由管理端主动删 key，缓存仅兜底省查询。
const userStatusKey = "ustatus:"

// Auth JWT 鉴权中间件：从 Authorization 头解析 uid 注入上下文，
// 并校验用户封禁状态（v0.6.0 T2——此前封禁后旧 token 仍可用 7 天）。
// db/rdb 任一为 nil 时跳过状态校验（单测/无 Redis 场景不受影响）。
func Auth(jm *jwt.Manager, db *gorm.DB, rdb *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			httpx.Abort(c, code.ErrUnauthorized)
			return
		}
		token := strings.TrimPrefix(auth, "Bearer ")
		claims, err := jm.Parse(token)
		if err != nil {
			httpx.Abort(c, code.ErrUnauthorized)
			return
		}
		if banned(c, db, rdb, claims.UID) {
			// 401 让客户端走清登录态的既有路径，code=5003 区分封禁
			httpx.Abort(c, code.ErrBanned)
			return
		}
		c.Set("uid", claims.UID)
		c.Next()
	}
}

// banned 查用户是否被封禁：Redis 短缓存 → DB 兜底；缓存/DB 异常时放行（可用性优先，
// DB 挂了业务查询本身也会失败，这里不放大故障面）。
func banned(c *gin.Context, db *gorm.DB, rdb *redis.Client, uid int64) bool {
	if db == nil {
		return false
	}
	key := userStatusKey + strconv.FormatInt(uid, 10)
	if rdb != nil {
		if v, err := rdb.Get(c, key).Result(); err == nil {
			return v == "1"
		}
	}
	var status int8
	if err := db.WithContext(c).Table("users").Select("status").Where("id = ?", uid).Scan(&status).Error; err != nil {
		return false
	}
	if rdb != nil {
		rdb.Set(c, key, strconv.Itoa(int(status)), 60*time.Second)
	}
	return status == 1
}

// InvalidateUserStatus 封禁/解封后删用户态缓存，保证 Auth 中间件即时生效。
// 治理动作要求即时，60s TTL 只是兜底省查询——管理端（service 层）调此函数。
func InvalidateUserStatus(rdb *redis.Client, ctx context.Context, uid int64) {
	if rdb != nil {
		rdb.Del(ctx, userStatusKey+strconv.FormatInt(uid, 10))
	}
}
