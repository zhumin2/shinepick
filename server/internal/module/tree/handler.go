package tree

import (
	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 拾光树与徽章（S7）。
type Handler struct {
	svc *service.TreeService
}

func NewHandler(svc *service.TreeService) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup) {
	r.GET("/tree", h.Tree)
	r.GET("/badges", h.Badges)
	r.POST("/badges/evaluate", h.Evaluate)
}

// Tree GET /tree —— 树状态 + 季节 + 光点历史。
func (h *Handler) Tree(c *gin.Context) {
	vo, err := h.svc.Tree(c, c.GetInt64("uid"))
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, vo)
}

// Badges GET /badges —— 徽章列表（已得/未得）。
func (h *Handler) Badges(c *gin.Context) {
	items, err := h.svc.ListBadges(c, c.GetInt64("uid"))
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"items": items})
}

// Evaluate POST /badges/evaluate —— 幂等评估并补发徽章
// （自愈入口：功能上线前的历史打卡也能补齐；树页加载时调用）。
func (h *Handler) Evaluate(c *gin.Context) {
	items, err := h.svc.EvaluateBadges(c, c.GetInt64("uid"), nil)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"items": items})
}
