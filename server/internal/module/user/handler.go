package user

import (
	"errors"

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
