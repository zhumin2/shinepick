package router

import (
	"context"
	"strings"

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
	authSvc := service.NewAuthService(db, rdb, jm, sms.NewSender(cfg.SMSType), repo)
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

	// 静态资源（dev 本地驱动上传的文件；生产换 OSS + CDN）
	e.Static("/static", cfg.UploadDir)
}
