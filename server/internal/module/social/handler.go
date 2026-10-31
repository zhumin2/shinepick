package social

import (
	"errors"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 通知 / 拉黑 / 举报（S6）。
type Handler struct {
	svc *service.SocialService
}

func NewHandler(svc *service.SocialService) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup) {
	r.GET("/notifications", h.List)
	r.POST("/notifications/read", h.MarkAllRead)
	r.POST("/blocks", h.Block)
	r.GET("/blocks", h.ListBlocked)
	r.DELETE("/blocks/:userId", h.Unblock)
	r.POST("/reports", h.Report)
}

// List GET /notifications?cursor= —— 通知列表 + 未读数。
func (h *Handler) List(c *gin.Context) {
	cursor, _ := strconv.ParseInt(c.Query("cursor"), 10, 64)
	items, next, unread, err := h.svc.List(c, c.GetInt64("uid"), cursor)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"items": items, "next_cursor": next, "unread_count": unread})
}

// MarkAllRead POST /notifications/read。
func (h *Handler) MarkAllRead(c *gin.Context) {
	if err := h.svc.MarkAllRead(c, c.GetInt64("uid")); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"read": true})
}

type blockReq struct {
	UserID int64 `json:"user_id" binding:"required"`
}

// Block POST /blocks {user_id}。
func (h *Handler) Block(c *gin.Context) {
	var req blockReq
	if err := c.ShouldBindJSON(&req); err != nil || req.UserID <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "缺少 user_id")
		return
	}
	if err := h.svc.Block(c, c.GetInt64("uid"), req.UserID); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"blocked": true})
}

// ListBlocked GET /blocks —— 我拉黑的用户。
func (h *Handler) ListBlocked(c *gin.Context) {
	rows, err := h.svc.BlockedUsers(c, c.GetInt64("uid"))
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"items": rows})
}

// Unblock DELETE /blocks/:userId。
func (h *Handler) Unblock(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("userId"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "用户 id 不合法")
		return
	}
	if err := h.svc.Unblock(c, c.GetInt64("uid"), id); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"blocked": false})
}

type reportReq struct {
	TargetType int8   `json:"target_type" binding:"required"`
	TargetID   int64  `json:"target_id" binding:"required"`
	Reason     int8   `json:"reason"`
	Detail     string `json:"detail"`
}

// Report POST /reports。
func (h *Handler) Report(c *gin.Context) {
	var req reportReq
	if err := c.ShouldBindJSON(&req); err != nil || req.TargetID <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "举报参数不正确")
		return
	}
	if err := h.svc.Report(c, c.GetInt64("uid"), req.TargetType, req.TargetID, req.Reason, req.Detail); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"reported": true})
}

func (h *Handler) fail(c *gin.Context, err error) {
	var ve *service.ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
	case errors.Is(err, gorm.ErrRecordNotFound):
		httpx.Fail(c, code.ErrNotFound)
	default:
		httpx.Fail(c, code.ErrInternal)
	}
}
