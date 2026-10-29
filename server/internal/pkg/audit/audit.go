package audit

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

// Verdict 审核结论。
type Verdict struct {
	Pass bool
	Risk string // 命中的风险说明（拒绝时可展示给日志）
}

// Auditor 内容审核接口。
// dev：mock 关键词规则；生产：remote 调独立 Python 审核服务（阿里云内容安全，见技术文档 6.2）。
type Auditor interface {
	Text(ctx context.Context, content string) Verdict
}

// ---- mock：本地关键词规则 ----

type mockAuditor struct {
	words []string
}

// NewMock 敏感词来自配置注入（默认内置最小集，dev 联调用）。
func NewMock(extraWords []string) Auditor {
	words := append([]string{
		"赌博", "代开发票", "刷单", "洗钱", "色情", "枪支",
	}, extraWords...)
	return &mockAuditor{words: words}
}

func (m *mockAuditor) Text(_ context.Context, content string) Verdict {
	for _, w := range m.words {
		if strings.Contains(content, w) {
			return Verdict{Pass: false, Risk: "hit:" + w}
		}
	}
	return Verdict{Pass: true}
}

// ---- remote：独立 Python 审核服务 ----

type remoteAuditor struct {
	baseURL string
	client  *http.Client
}

// NewRemote 独立审核服务（POST {base}/audit/text）。
func NewRemote(baseURL string) Auditor {
	return &remoteAuditor{
		baseURL: strings.TrimRight(baseURL, "/"),
		client:  &http.Client{Timeout: 800 * time.Millisecond}, // 技术文档 6.2：同步审核超时 800ms
	}
}

func (r *remoteAuditor) Text(ctx context.Context, content string) Verdict {
	body, _ := json.Marshal(map[string]string{"content": content})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.baseURL+"/audit/text", bytes.NewReader(body))
	if err != nil {
		return Verdict{Pass: true} // 服务异常放行（降级策略：不阻塞主链路）
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := r.client.Do(req)
	if err != nil {
		return Verdict{Pass: true} // 超时/不可达：放行，异步复核兜底
	}
	defer resp.Body.Close()
	var out struct {
		Pass bool   `json:"pass"`
		Risk string `json:"risk"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return Verdict{Pass: true}
	}
	return Verdict{Pass: out.Pass, Risk: out.Risk}
}

// New 按类型构造：mock / remote（AUDIT_REMOTE_URL 为空时兜底 mock）。
func New(auditType, remoteURL string, extraWords []string) Auditor {
	if auditType == "remote" && remoteURL != "" {
		return NewRemote(remoteURL)
	}
	return NewMock(extraWords)
}
