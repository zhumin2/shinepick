package user

import (
	"errors"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 用户模块路由与处理器（S2：资料 + 头像）。
type Handler struct {
	svc *service.UserService
}

func NewHandler(svc *service.UserService) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(r *gin.RouterGroup) {
	g := r.Group("/users")
	g.GET("/me", h.Profile)
	g.PATCH("/me", h.UpdateProfile)
	g.POST("/me/avatar", h.UploadAvatar)
	g.GET("/:id", h.OtherProfile)
	g.GET("/:id/companions", h.Companions)
}

// Companions GET /users/:id/companions —— 同路人列表（公开信息）。
func (h *Handler) Companions(c *gin.Context) {
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || targetID <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "用户 id 不合法")
		return
	}
	items, err := h.svc.Companions(c, targetID)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"items": items})
}

// OtherProfile GET /users/:id —— 他人公开主页（无手机号/未成年标记）。
func (h *Handler) OtherProfile(c *gin.Context) {
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || targetID <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "用户 id 不合法")
		return
	}
	vo, notFound, err := h.svc.OtherProfile(c, c.GetInt64("uid"), targetID)
	if err != nil {
		h.render(c, vo, err)
		return
	}
	if notFound {
		httpx.Fail(c, code.ErrNotFound)
		return
	}
	httpx.OK(c, vo)
}

// Profile GET /users/me —— 我的资料（含统计骨架）。
func (h *Handler) Profile(c *gin.Context) {
	vo, err := h.svc.Profile(c, c.GetInt64("uid"))
	h.render(c, vo, err)
}

// UpdateProfile PATCH /users/me —— 局部更新资料。
func (h *Handler) UpdateProfile(c *gin.Context) {
	var patch service.ProfilePatch
	if err := c.ShouldBindJSON(&patch); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	vo, err := h.svc.UpdateProfile(c, c.GetInt64("uid"), &patch)
	h.render(c, vo, err)
}

// UploadAvatar POST /users/me/avatar —— multipart 字段 file，≤2MB。
func (h *Handler) UploadAvatar(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "缺少头像文件（multipart 字段名 file）")
		return
	}
	url, err := h.svc.SaveAvatar(c, c.GetInt64("uid"), fh)
	if err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, err.Error())
		return
	}
	httpx.OK(c, gin.H{"avatar_url": url})
}

func (h *Handler) render(c *gin.Context, vo *service.ProfileVO, err error) {
	if err != nil {
		var ve *service.ValidationError
		switch {
		case errors.As(err, &ve):
			httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
		case errors.Is(err, gorm.ErrRecordNotFound):
			httpx.Fail(c, code.ErrNotFound)
		default:
			httpx.Fail(c, code.ErrInternal)
		}
		return
	}
	httpx.OK(c, vo)
}
