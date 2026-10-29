package config

import "os"

// Config 服务配置，全部来自环境变量，密钥不入仓库。
type Config struct {
	AppEnv        string // dev / staging / prod
	Port          string
	DBDSN         string
	RedisAddr     string
	RedisPassword string
	JWTSecret     string
	RefreshTTL    string // 如 720h
	SMSType       string // mock / aliyun
	UploadDir     string // 上传文件根目录（dev 本地驱动）
	PublicBaseURL string // 对外基础 URL（拼接静态资源链接）
}

func Load() *Config {
	return &Config{
		AppEnv:        getenv("APP_ENV", "dev"),
		Port:          getenv("PORT", "8080"),
		DBDSN:         getenv("DB_DSN", "root:123456@tcp(127.0.0.1:3306)/shinepick?charset=utf8mb4&parseTime=True&loc=Local"),
		RedisAddr:     getenv("REDIS_ADDR", "127.0.0.1:6379"),
		RedisPassword: getenv("REDIS_PASSWORD", ""),
		JWTSecret:     getenv("JWT_SECRET", "dev-secret-change-me"),
		RefreshTTL:    getenv("REFRESH_TTL", "720h"),
		SMSType:       getenv("SMS_TYPE", "mock"),
		UploadDir:     getenv("UPLOAD_DIR", "./uploads"),
		PublicBaseURL: getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8080"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
