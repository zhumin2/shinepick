package router

import (
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"

	"shinepick/internal/config"
	"shinepick/internal/middleware"
	"shinepick/internal/module/auth"
	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
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

	// 需要登录的接口示例（S2 起扩展）：GET /api/v1/me
	authed := api.Group("", middleware.Auth(jm))
	authed.GET("/me", func(c *gin.Context) {
		uid := c.GetInt64("uid")
		u, err := repo.ByID(c, uid)
		if err != nil {
			httpx.Fail(c, code.ErrNotFound)
			return
		}
		httpx.OK(c, gin.H{"id": u.ID, "nickname": u.Nickname, "avatar_url": u.AvatarURL})
	})
}
