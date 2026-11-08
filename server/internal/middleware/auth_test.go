package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"shinepick/internal/pkg/jwt"
)

// v0.6.0 T2：Auth 中间件接线测试（db/rdb 为 nil 的可测路径——
// 封禁 DB 查询路径需真库，由 T11 服务器冒烟覆盖）。
func newAuthProbe(t *testing.T) (*gin.Engine, *jwt.Manager) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	jm := jwt.NewManager("test-secret")
	r := gin.New()
	r.GET("/probe", Auth(jm, nil, nil), func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"uid": c.GetInt64("uid")})
	})
	return r, jm
}

func do(r *gin.Engine, token string) (int, map[string]any) {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/probe", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	r.ServeHTTP(w, req)
	var body map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	return w.Code, body
}

func TestAuthValidTokenPasses(t *testing.T) {
	r, jm := newAuthProbe(t)
	token, err := jm.Generate(42, time.Minute)
	if err != nil {
		t.Fatalf("生成 token 失败: %v", err)
	}
	status, body := do(r, token)
	if status != http.StatusOK {
		t.Fatalf("合法 token 应放行，got %d: %v", status, body)
	}
	if body["uid"].(float64) != 42 {
		t.Fatalf("uid 应注入上下文，got %v", body["uid"])
	}
}

func TestAuthMissingTokenRejected(t *testing.T) {
	r, _ := newAuthProbe(t)
	status, body := do(r, "")
	if status != http.StatusUnauthorized || int(body["code"].(float64)) != 2001 {
		t.Fatalf("无 token 应 401/2001，got %d/%v", status, body["code"])
	}
}

func TestAuthBadTokenRejected(t *testing.T) {
	r, _ := newAuthProbe(t)
	status, body := do(r, "not-a-jwt")
	if status != http.StatusUnauthorized || int(body["code"].(float64)) != 2001 {
		t.Fatalf("坏 token 应 401/2001，got %d/%v", status, body["code"])
	}
}
