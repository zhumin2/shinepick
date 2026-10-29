package router

import (
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/config"
	"shinepick/internal/middleware"
	"shinepick/internal/module/auth"
	"shinepick/internal/module/checkin"
	"shinepick/internal/module/upload"
	"shinepick/internal/module/user"
	"shinepick/internal/pkg/audit"
	"shinepick/internal/pkg/jwt"
	"shinepick/internal/pkg/sms"
	"shinepick/internal/repository"
	"shinepick/internal/service"
)

// Register 注册全部业务路由。
func Register(e *gin.Engine, db *gorm.DB, rdb *redis.Client, cfg *config.Config) {
	api := e.Group("/api/v1")

	jm := jwt.NewManager(cfg.JWTSecret)
	repo := repository.NewUserRepo(db)
	authSvc := service.NewAuthService(db, rdb, jm, sms.NewSender(cfg.SMSType), repo)
	auth.NewHandler(authSvc).Register(api)

	// 登录态接口
	authed := api.Group("", middleware.Auth(jm))
	userSvc := service.NewUserService(repo, cfg.UploadDir, cfg.PublicBaseURL)
	user.NewHandler(userSvc).Register(authed)

	checkinRepo := repository.NewCheckinRepo(db)
	checkinSvc := service.NewCheckinService(
		checkinRepo, repo, rdb,
		audit.New(cfg.AuditType, cfg.AuditRemoteURL, nil),
	)
	checkinH := checkin.NewHandler(checkinSvc)
	checkinH.Register(authed)
	// 某人的打卡列表（挂在 /users/:id 下）
	authed.GET("/users/:id/checkins", checkinH.ListByUser)

	upload.NewHandler(cfg.UploadDir, cfg.PublicBaseURL).Register(authed)

	// 静态资源（dev 本地驱动上传的文件；生产换 OSS + CDN）
	e.Static("/static", cfg.UploadDir)
}
