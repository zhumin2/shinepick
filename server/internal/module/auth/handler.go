package auth

import (
	"errors"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 账号模块路由与处理器。
type Handler struct {
	svc *service.AuthService
}

func NewHandler(svc *service.AuthService) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup) {
	g := r.Group("/auth")
	g.POST("/sms-code", h.SendCode)
	g.POST("/login", h.Login)
	g.POST("/refresh", h.Refresh)
}

func (h *Handler) SendCode(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required,len=11"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "手机号格式不正确")
		return
	}
	if err := h.svc.SendSmsCode(c, req.Phone); err != nil {
		if errors.Is(err, service.ErrFrequent) {
			httpx.Fail(c, code.ErrTooFrequent)
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"expire_seconds": 300, "cooldown_seconds": 60})
}

func (h *Handler) Login(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required,len=11"`
		Code  string `json:"code" binding:"required,len=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "手机号或验证码格式不正确")
		return
	}
	res, err := h.svc.Login(c, req.Phone, req.Code)
	if err != nil {
		if errors.Is(err, service.ErrSmsInvalid) {
			httpx.Fail(c, code.ErrSmsInvalid)
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, res)
}

func (h *Handler) Refresh(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "refresh_token 不能为空")
		return
	}
	res, err := h.svc.Refresh(c, req.RefreshToken)
	if err != nil {
		if errors.Is(err, service.ErrUnauthorized) {
			httpx.Fail(c, code.ErrUnauthorized)
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, res)
}
