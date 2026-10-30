package checkin

import (
	"errors"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 打卡模块（S3）。
type Handler struct {
	svc   *service.CheckinService
	inter *service.InteractionService // 回填 my_reactions（S5）
}

func NewHandler(svc *service.CheckinService, inter *service.InteractionService) *Handler {
	return &Handler{svc: svc, inter: inter}
}

func (h *Handler) Register(r *gin.RouterGroup) {
	g := r.Group("/checkins")
	g.POST("", h.Create)
	g.GET("/:id", h.Detail)
	g.DELETE("/:id", h.Delete)
}

// Create POST /checkins —— 发布打卡（审核+频控+幂等+树联动）。
func (h *Handler) Create(c *gin.Context) {
	var req service.CreateCheckinReq
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	res, err := h.svc.Create(c, c.GetInt64("uid"), &req)
	if err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, res)
} // Detail GET /checkins/:id —— 打卡详情。
func (h *Handler) Detail(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "打卡 id 不合法")
		return
	}
	vo, err := h.svc.Detail(c, c.GetInt64("uid"), id)
	if err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, vo)
}

// Delete DELETE /checkins/:id —— 软删除自己的打卡。
func (h *Handler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "打卡 id 不合法")
		return
	}
	if err := h.svc.Delete(c, c.GetInt64("uid"), id); err != nil {
		h.fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"deleted": true})
}

// ListByUser GET /users/:id/checkins —— 某人的打卡（自己=全部，他人=同路人可见）。
func (h *Handler) ListByUser(c *gin.Context) {
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || targetID <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "用户 id 不合法")
		return
	}
	cursor, _ := strconv.ParseInt(c.Query("cursor"), 10, 64)
	viewer := c.GetInt64("uid")
	me := viewer == targetID

	items, next, err := h.svc.List(c, viewer, targetID, cursor, me)
	if err != nil {
		h.fail(c, err)
		return
	}
	h.inter.FillMyReactions(c, viewer, items)
	httpx.OK(c, gin.H{"items": items, "next_cursor": next})
}

func (h *Handler) fail(c *gin.Context, err error) {
	var ve *service.ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
	case errors.Is(err, service.ErrCheckinReject):
		httpx.Fail(c, code.ErrAuditReject)
	case errors.Is(err, service.ErrCheckinFrequent):
		httpx.Fail(c, code.ErrTooFrequent)
	case errors.Is(err, gorm.ErrRecordNotFound):
		httpx.Fail(c, code.ErrNotFound)
	default:
		httpx.Fail(c, code.ErrInternal)
	}
}
