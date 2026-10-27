package main

import (
	"context"
	"log"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"

	"shinepick/internal/config"
	"shinepick/internal/middleware"
	"shinepick/internal/pkg/httpx"
	"shinepick/internal/router"
)

func main() {
	cfg := config.Load()

	db, err := connectDB(cfg)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	rdb := connectRedis(cfg)

	gin.SetMode(ginMode(cfg.AppEnv))
	e := gin.New()
	e.Use(middleware.RequestID(), middleware.Logger(), gin.Recovery())
	e.GET("/ping", func(c *gin.Context) {
		httpx.OK(c, gin.H{"pong": true, "env": cfg.AppEnv})
	})

	router.Register(e, db, rdb, cfg)

	log.Printf("shinepick api listening on :%s (env=%s)", cfg.Port, cfg.AppEnv)
	if err := e.Run(":" + cfg.Port); err != nil {
		log.Fatalf("run server: %v", err)
	}
}

func connectDB(cfg *config.Config) (*gorm.DB, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	db, err := gorm.Open(mysql.Open(cfg.DBDSN), &gorm.Config{
		Logger: gormlogger.Default.LogMode(gormlogger.Warn),
	})
	if err != nil {
		return nil, err
	}
	if cfg.AppEnv != "prod" {
		// 非生产环境自动迁移（仅建表，不动数据）
		_ = db.AutoMigrate()
	}
	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}
	sqlDB.SetMaxOpenConns(20)
	sqlDB.SetMaxIdleConns(5)
	sqlDB.SetConnMaxLifetime(time.Hour)
	if err := sqlDB.PingContext(ctx); err != nil {
		return nil, err
	}
	return db, nil
}

func connectRedis(cfg *config.Config) *redis.Client {
	return redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
		DB:       0,
	})
}

func ginMode(env string) string {
	if env == "prod" || env == "staging" {
		return gin.ReleaseMode
	}
	return gin.DebugMode
}
