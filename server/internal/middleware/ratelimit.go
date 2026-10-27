package middleware

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

// RateLimit 通用 IP 维度限流（简单固定窗口）。
// 业务级频控（验证码 60s 等）在 service 内实现，这里管粗粒度防护。
func RateLimit(rdb *redis.Client, window time.Duration, max int) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := "rl:ip:" + c.ClientIP()
		n, err := rdb.Incr(c, key).Result()
		if err != nil {
			// Redis 异常时放行，不因限流组件故障拖垮业务
			c.Next()
			return
		}
		if n == 1 {
			rdb.Expire(c, key, window)
		}
		if n > int64(max) {
			c.AbortWithStatusJSON(200, gin.H{
				"code":       4001,
				"message":    "操作过于频繁，请稍后再试",
				"data":       nil,
				"request_id": c.GetString("request_id"),
			})
			return
		}
		c.Next()
	}
}
