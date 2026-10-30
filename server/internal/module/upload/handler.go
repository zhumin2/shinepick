package upload

import (
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/code"
	"shinepick/internal/pkg/httpx"
)

// Handler 通用图片上传（S3-06 客户端配图；dev 本地驱动，生产 OSS 直传）。
type Handler struct {
	uploadDir  string
	publicBase string
}

func NewHandler(uploadDir, publicBase string) *Handler {
	return &Handler{uploadDir: uploadDir, publicBase: publicBase}
}

func (h *Handler) Register(r *gin.RouterGroup) {
	r.POST("/uploads/images", h.Images)
}

const (
	imageMaxSize  = 5 << 20 // 单张 5MB
	imageMaxCount = 9       // 单次最多 9 张
)

var imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true}

// Images POST /uploads/images —— multipart 字段 files（可多张）。
func (h *Handler) Images(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		httpx.FailMsg(c, code.ErrBadRequest, "multipart 表单不正确")
		return
	}
	files := form.File["files"]
	if len(files) == 0 {
		httpx.FailMsg(c, code.ErrBadRequest, "缺少图片文件（multipart 字段名 files）")
		return
	}
	if len(files) > imageMaxCount {
		httpx.FailMsg(c, code.ErrBadRequest, fmt.Sprintf("单次最多 %d 张", imageMaxCount))
		return
	}
	dir := filepath.Join(h.uploadDir, "images")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		httpx.Fail(c, code.ErrInternal)
		return
	}
	uid := c.GetInt64("uid")
	urls := make([]string, 0, len(files))
	for _, fh := range files {
		url, err := h.saveOne(uid, fh, dir)
		if err != nil {
			httpx.FailMsg(c, code.ErrBadRequest, err.Error())
			return
		}
		urls = append(urls, url)
	}
	httpx.OK(c, gin.H{"urls": urls})
}

func (h *Handler) saveOne(uid int64, fh *multipart.FileHeader, dir string) (string, error) {
	if fh.Size <= 0 || fh.Size > imageMaxSize {
		return "", fmt.Errorf("图片 %s 需在 5MB 以内", fh.Filename)
	}
	ext := strings.ToLower(filepath.Ext(fh.Filename))
	if !imageExts[ext] {
		return "", fmt.Errorf("图片 %s 仅支持 jpg/png/webp/gif", fh.Filename)
	}
	src, err := fh.Open()
	if err != nil {
		return "", err
	}
	defer src.Close()

	name := fmt.Sprintf("u%d_%d_%d%s", uid, time.Now().UnixMilli(), len(fh.Filename), ext)
	dst, err := os.Create(filepath.Join(dir, name))
	if err != nil {
		return "", err
	}
	defer dst.Close()
	if _, err := io.Copy(dst, src); err != nil {
		return "", err
	}
	return strings.TrimRight(h.publicBase, "/") + "/static/images/" + name, nil
}
