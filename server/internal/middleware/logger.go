package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"github.com/gin-gonic/gin"
)

// RequestID 为每个请求生成 request_id 注入上下文与响应头。
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		rid := c.GetHeader("X-Request-ID")
		if rid == "" {
			rid = newID()
		}
		c.Set("request_id", rid)
		c.Header("X-Request-ID", rid)
		c.Next()
	}
}

// Logger 精简访问日志：method path status latency request_id。
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		gin.DefaultWriter.Write([]byte(
			time.Now().Format("2006-01-02 15:04:05") + " " +
				c.Request.Method + " " + c.Request.URL.Path + " " +
				itoa(c.Writer.Status()) + " " + time.Since(start).Round(time.Millisecond).String() +
				" rid=" + c.GetString("request_id") + "\n"))
	}
}

func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [8]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
