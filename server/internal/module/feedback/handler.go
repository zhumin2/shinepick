package feedback

import (
	"errors"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 意见反馈（v0.6.0 T8，登录态）。
type Handler struct {
	svc *service.FeedbackService
}

func NewHandler(svc *service.FeedbackService) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup) {
	r.POST("/feedback", h.Submit)
}

// Submit POST /feedback {content}。
func (h *Handler) Submit(c *gin.Context) {
	var req struct {
		Content string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "反馈内容不能为空")
		return
	}
	if err := h.svc.Submit(c, c.GetInt64("uid"), req.Content); err != nil {
		if errors.Is(err, service.ErrFrequent) {
			httpx.Fail(c, code.ErrTooFrequent)
			return
		}
		var ve *service.ValidationError
		if errors.As(err, &ve) {
			httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"submitted": true})
}
