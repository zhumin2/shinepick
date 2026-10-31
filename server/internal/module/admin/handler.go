package admin

import (
	"errors"
	"time"

	"github.com/gin-gonic/gin"

	"shinepick/internal/config"
	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/service"
)

// Handler 运营接口（S8-01/S8-05）。X-Admin-Token 鉴权。
type Handler struct {
	svc   *service.AdminService
	feed  *service.FeedService
	token string
}

func NewHandler(svc *service.AdminService, feed *service.FeedService, cfg *config.Config) *Handler {
	return &Handler{svc: svc, feed: feed, token: cfg.AdminToken}
}

func (h *Handler) Register(e *gin.Engine) {
	g := e.Group("/admin", h.auth())
	g.GET("/stats", h.Stats)
	g.PUT("/feed/selected", h.SetSelected)
	g.POST("/feed/rebuild", h.Rebuild)
	// 面板页（页面本身不含敏感数据，fetch 时带 token）
	e.GET("/admin", h.page)
}

func (h *Handler) auth() gin.HandlerFunc {
	return func(c *gin.Context) {
		if h.token == "" || c.GetHeader("X-Admin-Token") != h.token {
			c.AbortWithStatusJSON(200, gin.H{
				"code": code.ErrForbidden, "message": "需要 X-Admin-Token", "data": nil,
			})
			return
		}
		c.Next()
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

// page GET /admin —— 极简运营面板（输入 token 后取数）。
func (h *Handler) page(c *gin.Context) {
	const page = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>拾光 · 运营面板</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui;background:#FAF8F3;color:#3A3A3A;max-width:680px;margin:40px auto;padding:0 20px}
h1{font-size:20px}input,button{padding:10px 14px;border-radius:10px;border:1px solid #ECE6D8;font-size:14px}
button{background:#E89B3C;color:#fff;border:none;cursor:pointer;font-weight:600}
table{width:100%%;border-collapse:collapse;margin-top:16px;background:#fff;border-radius:12px;overflow:hidden}
td,th{padding:10px 14px;border-bottom:1px solid #ECE6D8;text-align:left;font-size:14px}
th{background:#F7E3C4;color:#C97F22}#out{margin-top:16px;font-size:13px;color:#8A8578;white-space:pre-wrap}</style></head><body>
<h1>拾光 · 运营面板</h1>
<p><input id="tk" placeholder="X-Admin-Token" size="28" value="dev-admin-token"> <button onclick="load()">刷新指标</button></p>
<table id="tbl"></table><div id="out"></div>
<script>
async function load(){
  const tk=document.getElementById('tk').value;
  const r=await fetch('/admin/stats',{headers:{'X-Admin-Token':tk}});
  const j=await r.json();
  if(j.code!==0){document.getElementById('out').textContent='加载失败：'+j.message;return}
  const d=j.data;
  document.getElementById('tbl').innerHTML=
   '<tr><th>指标</th><th>值</th></tr>'+
   '<tr><td>累计用户</td><td>'+d.users_total+'</td></tr>'+
   '<tr><td>近 7 天新增</td><td>'+d.users_new_7d+'</td></tr>'+
   '<tr><td>今日打卡</td><td>'+d.checkins_today+'</td></tr>'+
   '<tr><td>近 7 天打卡</td><td>'+d.checkins_7d+'</td></tr>'+
   '<tr><td>周活（WAU）</td><td>'+d.wau+'</td></tr>'+
   '<tr><td>北极星 · 周打卡≥3天占比</td><td>'+d.polar_star_pct.toFixed(1)+'%</td></tr>';
}
</script></body></html>`
	c.Data(200, "text/html; charset=utf-8", []byte(page))
}
