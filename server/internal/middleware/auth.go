package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/pkg/jwt"
)

// Auth JWT 鉴权中间件：从 Authorization 头解析 uid 注入上下文。
func Auth(jm *jwt.Manager) gin.HandlerFunc {
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
		c.Set("uid", claims.UID)
		c.Next()
	}
}
