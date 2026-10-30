package feed

import (
	"strconv"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler Feed 与发现页（S4-01/S4-05）。
type Handler struct {
	svc   *service.FeedService
	inter *service.InteractionService // 回填 my_reactions（S5）
}

func NewHandler(svc *service.FeedService, inter *service.InteractionService) *Handler {
	return &Handler{svc: svc, inter: inter}
}

func (h *Handler) Register(r *gin.RouterGroup) {
	r.GET("/feed", h.Today)
	r.GET("/explore", h.Explore)
}

// Today GET /feed —— 今日微光 + 同品类打卡的陌生人。
func (h *Handler) Today(c *gin.Context) {
	vo, err := h.svc.Today(c, c.GetInt64("uid"))
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	uid := c.GetInt64("uid")
	daily := make([]*service.CheckinVO, 0, len(vo.DailySelected))
	for _, it := range vo.DailySelected {
		daily = append(daily, &it.CheckinVO)
	}
	doing := make([]*service.CheckinVO, 0, len(vo.Doing))
	for _, it := range vo.Doing {
		doing = append(doing, &it.CheckinVO)
	}
	h.inter.FillMyReactions(c, uid, daily)
	h.inter.FillMyReactions(c, uid, doing)
	httpx.OK(c, vo)
}

// Explore GET /explore?category=&cursor= —— 按品类浏览（0=全部）。
func (h *Handler) Explore(c *gin.Context) {
	category, _ := strconv.Atoi(c.Query("category"))
	if category < 0 || category > 6 {
		httpx.FailMsg(c, code.ErrBadRequest, "品类不合法")
		return
	}
	cursor, _ := strconv.ParseInt(c.Query("cursor"), 10, 64)
	items, next, err := h.svc.Explore(c, int8(category), cursor)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	vos := make([]*service.CheckinVO, 0, len(items))
	for _, it := range items {
		vos = append(vos, &it.CheckinVO)
	}
	h.inter.FillMyReactions(c, c.GetInt64("uid"), vos)
	httpx.OK(c, gin.H{"items": items, "next_cursor": next})
}
