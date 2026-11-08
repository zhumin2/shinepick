package admin

import (
	"errors"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/config"
	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 运营接口（S8-01/S8-05；v0.6.0 扩展治理/运营/公告）。X-Admin-Token 鉴权。
type Handler struct {
	svc   *service.AdminService
	feed  *service.FeedService
	token string
	rdb   *redis.Client
}

func NewHandler(svc *service.AdminService, feed *service.FeedService, cfg *config.Config, rdb *redis.Client) *Handler {
	return &Handler{svc: svc, feed: feed, token: cfg.AdminToken, rdb: rdb}
}

func (h *Handler) Register(e *gin.Engine) {
	g := e.Group("/admin", h.auth())
	g.GET("/stats", h.Stats)
	g.PUT("/feed/selected", h.SetSelected)
	g.POST("/feed/rebuild", h.Rebuild)
	g.GET("/reports", h.Reports)
	g.POST("/reports/:id/handle", h.HandleReport)
	g.GET("/users", h.Users)
	g.GET("/users/:id", h.UserDetail)
	g.PUT("/users/:id/status", h.SetUserStatus)
	g.GET("/checkins", h.Checkins)
	g.DELETE("/checkins/:id", h.DeleteCheckin)
	g.GET("/comments", h.Comments)
	g.DELETE("/comments/:id", h.DeleteComment)
	g.POST("/announcements", h.Announce)
	g.GET("/stats/trend", h.Trend)
	g.GET("/feedback", h.FeedbackList)
	g.POST("/feedback/:id/done", h.FeedbackDone)
	g.GET("/actions", h.Actions)
	// 面板页（页面本身不含敏感数据，fetch 时带 token）
	e.GET("/admin", h.page)
}

// 防爆破阈值：同 IP 10 分钟内错 10 次锁定（v0.6.0 T1——token 一旦用于封人删内容，
// 默认弱 token + 无限重试就是公网上的显式洞）。
const failWindow = 10 * time.Minute

func (h *Handler) auth() gin.HandlerFunc {
	return func(c *gin.Context) {
		if h.token == "" || c.GetHeader("X-Admin-Token") != h.token {
			h.countFail(c)
			c.AbortWithStatusJSON(200, gin.H{
				"code": code.ErrForbidden, "message": "需要 X-Admin-Token", "data": nil,
			})
			return
		}
		// token 正确但已触发锁定：仍拒绝（防「先爆破后猜中」窗口），成功不重置计数
		if n := h.failCount(c); n > adminFailMax {
			c.AbortWithStatusJSON(200, gin.H{
				"code": code.ErrTooFrequent, "message": "尝试过于频繁，请稍后再试", "data": nil,
			})
			return
		}
		c.Next()
	}
}

const adminFailMax = 10

func (h *Handler) failCount(c *gin.Context) int64 {
	if h.rdb == nil {
		return 0
	}
	n, _ := h.rdb.Get(c, "admin:fail:"+c.ClientIP()).Int64()
	return n
}

func (h *Handler) countFail(c *gin.Context) {
	if h.rdb == nil {
		return
	}
	key := "admin:fail:" + c.ClientIP()
	n, err := h.rdb.Incr(c, key).Result()
	if err == nil && n == 1 {
		h.rdb.Expire(c, key, failWindow)
	}
}

// Stats GET /admin/stats。
func (h *Handler) Stats(c *gin.Context) {
	vo, err := h.svc.Stats(c)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, vo)
}

// SetSelected PUT /admin/feed/selected {checkin_ids:[...]}。
func (h *Handler) SetSelected(c *gin.Context) {
	var req struct {
		IDs []int64 `json:"checkin_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	items, err := h.feed.SetDailySelected(c, req.IDs)
	if err != nil {
		var ve *service.ValidationError
		if errors.As(err, &ve) {
			httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"items": items})
}

// Rebuild POST /admin/feed/rebuild —— 立即按规则模型重建精选。
func (h *Handler) Rebuild(c *gin.Context) {
	if err := h.feed.RebuildDailySelected(c, time.Now().In(service.CstZone()).Format("2006-01-02")); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"rebuilt": true})
}

// Reports GET /admin/reports?status=&page=&page_size= —— 举报列表（status 缺省 0 待处理，all=全部）。
func (h *Handler) Reports(c *gin.Context) {
	var status = int8(0)
	if s := c.Query("status"); s != "" && s != "all" {
		v, err := strconv.Atoi(s)
		if err != nil || v < 0 || v > 2 {
			httpx.FailMsg(c, code.ErrBadRequest, "status 取值不合法")
			return
		}
		status = int8(v)
	} else if s == "all" {
		status = -1
	}
	page, pageSize := pageParams(c)
	list, total, err := h.svc.Reports(c, status, page, pageSize)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list, "total": total, "page": page, "page_size": pageSize})
}

// HandleReport POST /admin/reports/:id/handle {action: delete_content|ban_user|dismiss, note?}。
func (h *Handler) HandleReport(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "id 不合法")
		return
	}
	var req struct {
		Action string `json:"action" binding:"required"`
		Note   string `json:"note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	if err := h.svc.HandleReport(c, id, req.Action, req.Note); err != nil {
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
	h.svc.LogAction(c, "handle_report", "report", id, req.Action+" "+req.Note)
	httpx.OK(c, gin.H{"handled": true})
}

// pageParams 管理端分页参数（page/page_size，上限 50——运营低频，不必沿用客户端游标）。
func pageParams(c *gin.Context) (int, int) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	size, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if size < 1 {
		size = 20
	}
	if size > 50 {
		size = 50
	}
	return page, size
}

// ---------- 用户管理（v0.6.0 T4） ----------

// Users GET /admin/users?keyword=&page=&page_size=。
func (h *Handler) Users(c *gin.Context) {
	page, pageSize := pageParams(c)
	list, total, err := h.svc.AdminUsers(c, c.Query("keyword"), page, pageSize)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list, "total": total, "page": page, "page_size": pageSize})
}

// UserDetail GET /admin/users/:id —— 资料 + 统计 + 最近 10 条打卡。
func (h *Handler) UserDetail(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "id 不合法")
		return
	}
	vo, checkins, err := h.svc.AdminUserDetail(c, id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			httpx.Fail(c, code.ErrNotFound)
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"user": vo, "recent_checkins": checkins})
}

// SetUserStatus PUT /admin/users/:id/status {status: 0|1}。
func (h *Handler) SetUserStatus(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "id 不合法")
		return
	}
	var req struct {
		Status int8 `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	if err := h.svc.SetUserStatus(c, id, req.Status); err != nil {
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
	act := "unban_user"
	if req.Status == 1 {
		act = "ban_user"
	}
	h.svc.LogAction(c, act, "user", id, "")
	httpx.OK(c, gin.H{"status": req.Status})
}

// ---------- 内容巡检（v0.6.0 T5） ----------

// Checkins GET /admin/checkins?keyword=&category=&page=&page_size=。
func (h *Handler) Checkins(c *gin.Context) {
	page, pageSize := pageParams(c)
	var category int8
	if v, err := strconv.Atoi(c.Query("category")); err == nil && v > 0 && v <= 6 {
		category = int8(v)
	}
	list, total, err := h.svc.AdminCheckins(c, c.Query("keyword"), category, page, pageSize)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list, "total": total, "page": page, "page_size": pageSize})
}

// DeleteCheckin DELETE /admin/checkins/:id —— 软删 + 重建今日微光。
func (h *Handler) DeleteCheckin(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "id 不合法")
		return
	}
	if err := h.svc.AdminDeleteCheckin(c, id); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	h.svc.LogAction(c, "delete_checkin", "checkin", id, "")
	httpx.OK(c, gin.H{"deleted": true})
}

// Comments GET /admin/comments?keyword=&page=&page_size=。
func (h *Handler) Comments(c *gin.Context) {
	page, pageSize := pageParams(c)
	list, total, err := h.svc.AdminComments(c, c.Query("keyword"), page, pageSize)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list, "total": total, "page": page, "page_size": pageSize})
}

// DeleteComment DELETE /admin/comments/:id。
func (h *Handler) DeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "id 不合法")
		return
	}
	if err := h.svc.AdminDeleteComment(c, id); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	h.svc.LogAction(c, "delete_comment", "comment", id, "")
	httpx.OK(c, gin.H{"deleted": true})
}

// ---------- 公告与趋势（v0.6.0 T6/T7） ----------

// Announce POST /admin/announcements {user_ids: null(全员)|[...], content}。
func (h *Handler) Announce(c *gin.Context) {
	var req struct {
		UserIDs []int64 `json:"user_ids"`
		Content string  `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "请求体格式不正确")
		return
	}
	n, err := h.svc.Announce(c, req.UserIDs, req.Content)
	if err != nil {
		var ve *service.ValidationError
		if errors.As(err, &ve) {
			httpx.FailMsg(c, code.ErrBadRequest, ve.Error())
			return
		}
		httpx.Fail(c, code.ErrInternal)
		return
	}
	scope := "全员"
	if len(req.UserIDs) > 0 {
		scope = "定向 " + strconv.Itoa(len(req.UserIDs)) + " 人"
	}
	h.svc.LogAction(c, "announce", "notification", 0, scope+"："+req.Content)
	httpx.OK(c, gin.H{"sent": n})
}

// Trend GET /admin/stats/trend?days=14 —— 逐日 DAU/打卡数/新增用户。
func (h *Handler) Trend(c *gin.Context) {
	days, _ := strconv.Atoi(c.DefaultQuery("days", "14"))
	list, err := h.svc.Trend(c, days)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list})
}

// ---------- 反馈与操作日志（v0.6.0 T8/T9） ----------

// FeedbackList GET /admin/feedback?status=&page=&page_size=（status 缺省 0，all=全部）。
func (h *Handler) FeedbackList(c *gin.Context) {
	var status = int8(0)
	if s := c.Query("status"); s == "all" {
		status = -1
	} else if s != "" {
		v, err := strconv.Atoi(s)
		if err != nil || v < 0 || v > 1 {
			httpx.FailMsg(c, code.ErrBadRequest, "status 取值不合法")
			return
		}
		status = int8(v)
	}
	page, pageSize := pageParams(c)
	list, total, err := h.svc.AdminFeedback(c, status, page, pageSize)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list, "total": total, "page": page, "page_size": pageSize})
}

// FeedbackDone POST /admin/feedback/:id/done —— 标记已处理。
func (h *Handler) FeedbackDone(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "id 不合法")
		return
	}
	if err := h.svc.MarkFeedbackDone(c, id); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	h.svc.LogAction(c, "feedback_done", "feedback", id, "")
	httpx.OK(c, gin.H{"done": true})
}

// Actions GET /admin/actions?page=&page_size= —— 操作留底查询。
func (h *Handler) Actions(c *gin.Context) {
	page, pageSize := pageParams(c)
	list, total, err := h.svc.Actions(c, page, pageSize)
	if err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	httpx.OK(c, gin.H{"list": list, "total": total, "page": page, "page_size": pageSize})
}
