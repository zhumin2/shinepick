package httpx

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
)

// Body 统一响应结构。
type Body struct {
	Code      int         `json:"code"`
	Message   string      `json:"message"`
	Data      interface{} `json:"data"`
	RequestID string      `json:"request_id"`
}

func OK(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Body{
		Code:      code.OK,
		Message:   code.Message(code.OK),
		Data:      data,
		RequestID: c.GetString("request_id"),
	})
}

func Fail(c *gin.Context, errCode int) {
	FailMsg(c, errCode, code.Message(errCode))
}

func FailMsg(c *gin.Context, errCode int, msg string) {
	c.JSON(http.StatusOK, Body{
		Code:      errCode,
		Message:   msg,
		Data:      nil,
		RequestID: c.GetString("request_id"),
	})
}

// Abort 用于中间件（鉴权失败），HTTP 层用 401 便于客户端拦截刷新。
func Abort(c *gin.Context, errCode int) {
	c.AbortWithStatusJSON(http.StatusUnauthorized, Body{
		Code:      errCode,
		Message:   code.Message(errCode),
		Data:      nil,
		RequestID: c.GetString("request_id"),
	})
}
