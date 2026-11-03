package router

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/config"
	"shinepick/internal/middleware"
	"shinepick/internal/module/admin"
	"shinepick/internal/module/auth"
	"shinepick/internal/module/checkin"
	"shinepick/internal/module/feed"
	"shinepick/internal/module/interaction"
	"shinepick/internal/module/social"
	"shinepick/internal/module/tree"
	"shinepick/internal/module/upload"
	"shinepick/internal/module/user"
	"shinepick/internal/pkg/audit"
	"shinepick/internal/pkg/jwt"
	"shinepick/internal/pkg/sms"
	"shinepick/internal/repository"
	"shinepick/internal/service"
)

// Register 注册全部业务路由。ctx 供后台任务（每日精选 cron）使用。
func Register(ctx context.Context, e *gin.Engine, db *gorm.DB, rdb *redis.Client, cfg *config.Config) {
	api := e.Group("/api/v1")

	jm := jwt.NewManager(cfg.JWTSecret)
	repo := repository.NewUserRepo(db)
	authSvc := service.NewAuthService(db, rdb, jm, sms.NewSender(sms.SMSConfig{
		Type:       cfg.SMSType,
		SecretID:   cfg.SMSSecretID,
		SecretKey:  cfg.SMSSecretKey,
		AppID:      cfg.SMSAppID,
		SignName:   cfg.SMSSignName,
		TemplateID: cfg.SMSTemplateID,
	}), repo)
	auth.NewHandler(authSvc).Register(api)

	// 登录态接口
	authed := api.Group("", middleware.Auth(jm))
	checkinRepo := repository.NewCheckinRepo(db)
	interRepo := repository.NewInteractionRepo(db)
	aud := audit.New(cfg.AuditType, cfg.AuditRemoteURL, nil)

	userSvc := service.NewUserService(repo, checkinRepo, interRepo, cfg.UploadDir, cfg.PublicBaseURL)
	user.NewHandler(userSvc).Register(authed)

	checkinSvc := service.NewCheckinService(checkinRepo, repo, rdb, aud)
	socialRepo := repository.NewSocialRepo(db)
	socialSvc := service.NewSocialService(socialRepo, interRepo, checkinRepo)
	badgeRepo := repository.NewBadgeRepo(db)
	treeSvc := service.NewTreeService(checkinRepo, badgeRepo, db, socialSvc)
	checkinSvc.SetOnPublished(func(ctx context.Context, uid, checkinID int64) {
		_, _ = treeSvc.EvaluateBadges(ctx, uid, &checkinID) // S7：发布后评估徽章
	})
	interSvc := service.NewInteractionService(checkinRepo, interRepo, rdb, aud, socialSvc)
	checkinH := checkin.NewHandler(checkinSvc, interSvc, socialSvc)
	checkinH.Register(authed)
	// 某人的打卡列表（挂在 /users/:id 下）
	authed.GET("/users/:id/checkins", checkinH.ListByUser)

	interaction.NewHandler(interSvc).Register(authed)
	social.NewHandler(socialSvc).Register(authed)
	tree.NewHandler(treeSvc).Register(authed)

	feedSvc := service.NewFeedService(checkinRepo, rdb)
	feed.NewHandler(feedSvc, interSvc, socialSvc).Register(authed)
	service.StartDailyCron(ctx, feedSvc)
	// 打卡被删除/隐藏后重建今日微光缓存，避免公开流残留不可见内容
	checkinSvc.SetOnModified(func(ctx context.Context) {
		today := time.Now().In(service.CstZone()).Format("2006-01-02")
		_ = feedSvc.RebuildDailySelected(ctx, today)
	})

	// 运营接口（S8-01/05：精选管理 + 数据面板，X-Admin-Token 鉴权）
	adminSvc := service.NewAdminService(db, feedSvc)
	admin.NewHandler(adminSvc, feedSvc, cfg).Register(e)

	upload.NewHandler(cfg.UploadDir, cfg.PublicBaseURL).Register(authed)

	// Web 客户端禁缓存：每次都向服务器校验新鲜度，
	// 避免发版后浏览器继续用旧的 main.dart.js（用户反馈过看不到新功能）
	e.Use(func(c *gin.Context) {
		if strings.HasPrefix(c.Request.URL.Path, "/static/web") {
			c.Header("Cache-Control", "no-cache, must-revalidate")
		}
		c.Next()
	})

	// 检查更新（公开）：代理 apkserver 的 /api/latest 并重写下载 URL 为公网地址。
	// APK_LATEST_BASE 为空时返回空版本，客户端视为已是最新。
	api.GET("/app/latest", func(c *gin.Context) {
		missing := gin.H{"version": "", "url": ""}
		if cfg.APKLatestBase == "" {
			c.JSON(200, missing)
			return
		}
		client := &http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get(strings.TrimRight(cfg.APKLatestBase, "/") + "/api/latest")
		if err != nil {
			c.JSON(200, missing) // apkserver 不可用不阻塞客户端
			return
		}
		defer resp.Body.Close()
		var latest struct {
			Found   bool   `json:"found"`
			Version string `json:"version"`
			URL     string `json:"url"` // apkserver 返回相对路径 /files/xxx
		}
		if err := json.NewDecoder(resp.Body).Decode(&latest); err != nil || !latest.Found {
			c.JSON(200, missing)
			return
		}
		c.JSON(200, gin.H{
			"version": latest.Version,
			"url":     strings.TrimRight(cfg.APKLatestBase, "/") + latest.URL,
		})
	})

	// 静态资源（dev 本地驱动上传的文件；生产换 OSS + CDN）
	e.Static("/static", cfg.UploadDir)
}
