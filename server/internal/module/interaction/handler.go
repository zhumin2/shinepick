package interaction

import (
	"errors"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 互动与留言（S5）。
type Handler struct {
	svc *service.InteractionService
}

func NewHandler(svc *service.InteractionService) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup) {
	g := r.Group("/checkins")
	g.POST("/:id/reactions", h.React)
	g.DELETE("/:id/reactions", h.Unreact)
	g.GET("/:id/comments", h.ListComments)
	g.POST("/:id/comments", h.AddComment)
	r.DELETE("/comments/:id", h.DeleteComment)
	r.PATCH("/comments/:id/feature", h.SetFeatured)
}

type reactReq struct {
	Type int8 `json:"type" binding:"required"`
}

// React POST /checkins/:id/reactions {type:1|2|3}。
func (h *Handler) React(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "打卡 id 不合法")
		return
	}
	var req reactReq
	if err := c.ShouldBindJSON(&req); err != nil || req.Type < 1 || req.Type > 3 {
		httpx.FailMsg(c, code.ErrBadRequest, "互动类型不合法（1点亮 2拥抱 3同路）")
		return
	}
	if err := h.svc.React(c, c.GetInt64("uid"), id, req.Type); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"reacted": true})
}

// Unreact DELETE /checkins/:id/reactions?type=。
func (h *Handler) Unreact(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "打卡 id 不合法")
		return
	}
	typ, err := strconv.ParseInt(c.Query("type"), 10, 64)
	if err != nil || typ < 1 || typ > 3 {
		httpx.FailMsg(c, code.ErrBadRequest, "互动类型不合法")
		return
	}
	if err := h.svc.Unreact(c, c.GetInt64("uid"), id, int8(typ)); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"reacted": false})
}

// ListComments GET /checkins/:id/comments?cursor=（无 total）。
func (h *Handler) ListComments(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "打卡 id 不合法")
		return
	}
	cursor, _ := strconv.ParseInt(c.Query("cursor"), 10, 64)
	items, next, err := h.svc.ListComments(c, c.GetInt64("uid"), id, cursor)
	if err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"items": items, "next_cursor": next})
}

type commentReq struct {
	Content     string `json:"content"`
	ClientToken string `json:"client_token"`
}

// AddComment POST /checkins/:id/comments（≤80 字）。
func (h *Handler) AddComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "打卡 id 不合法")
		return
	}
	var req commentReq
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	vo, err := h.svc.AddComment(c, c.GetInt64("uid"), id, req.Content, req.ClientToken)
	if err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, vo)
}

// DeleteComment DELETE /comments/:id（本人或打卡作者）。
func (h *Handler) DeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "留言 id 不合法")
		return
	}
	if err := h.svc.DeleteComment(c, c.GetInt64("uid"), id); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"deleted": true})
}

// SetFeatured PATCH /comments/:id/feature {featured:true|false} —— 仅打卡作者。
func (h *Handler) SetFeatured(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "留言 id 不合法")
		return
	}
	var req struct {
		Featured *bool `json:"featured"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Featured == nil {
		httpx.FailMsg(c, code.ErrBadRequest, "缺少 featured 参数")
		return
	}
	if err := h.svc.SetFeatured(c, c.GetInt64("uid"), id, *req.Featured); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"featured": *req.Featured})
}

func (h *Handler) fail(c *gin.Context, err error) {
	var ve *service.ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
	case errors.Is(err, service.ErrCheckinReject):
		httpx.Fail(c, code.ErrAuditReject)
	case errors.Is(err, service.ErrCommentFrequent):
		httpx.Fail(c, code.ErrTooFrequent)
	case errors.Is(err, service.ErrForbidden):
		httpx.Fail(c, code.ErrForbidden)
	case errors.Is(err, gorm.ErrRecordNotFound):
		httpx.Fail(c, code.ErrNotFound)
	default:
		httpx.Fail(c, code.ErrInternal)
	}
}
