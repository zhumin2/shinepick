package router

import (
	"context"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/config"
	"shinepick/internal/middleware"
	"shinepick/internal/module/auth"
	"shinepick/internal/module/checkin"
	"shinepick/internal/module/feed"
	"shinepick/internal/module/interaction"
	"shinepick/internal/module/social"
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
	socialSvc := service.NewSocialService(
		repository.NewSocialRepo(db), interRepo, checkinRepo)
	interSvc := service.NewInteractionService(checkinRepo, interRepo, rdb, aud, socialSvc)
	checkinH := checkin.NewHandler(checkinSvc, interSvc, socialSvc)
	checkinH.Register(authed)
	// 某人的打卡列表（挂在 /users/:id 下）
	authed.GET("/users/:id/checkins", checkinH.ListByUser)

	interaction.NewHandler(interSvc).Register(authed)
	social.NewHandler(socialSvc).Register(authed)

	feedSvc := service.NewFeedService(checkinRepo, rdb)
	feed.NewHandler(feedSvc, interSvc, socialSvc).Register(authed)
	service.StartDailyCron(ctx, feedSvc)

	upload.NewHandler(cfg.UploadDir, cfg.PublicBaseURL).Register(authed)

	// 静态资源（dev 本地驱动上传的文件；生产换 OSS + CDN）
	e.Static("/static", cfg.UploadDir)
}
