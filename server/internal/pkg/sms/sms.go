package sms

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

// Sender 短信发送。mock = 打印日志；aliyun = 阿里云短信 Dysmsapi API。
type Sender struct {
	smsType         string
	accessKeyID     string
	accessKeySecret string
	signName        string
	templateCode    string
}

// SMSConfig 短信服务配置。
type SMSConfig struct {
	Type            string // mock / aliyun
	AccessKeyID     string
	AccessKeySecret string
	SignName        string
	TemplateCode    string
}

func NewSender(cfg SMSConfig) *Sender {
	return &Sender{
		smsType:         cfg.Type,
		accessKeyID:     cfg.AccessKeyID,
		accessKeySecret: cfg.AccessKeySecret,
		signName:        cfg.SignName,
		templateCode:    cfg.TemplateCode,
	}
}

// IsMock 是否 mock 通道（dev 固定验证码，见 S1 计划 §3.1）。
func (s *Sender) IsMock() bool {
	return s.smsType != "aliyun" ||
		s.accessKeyID == "" || s.accessKeySecret == "" ||
		s.signName == "" || s.templateCode == ""
}

// Send 发送验证码短信。
func (s *Sender) Send(phone, code string) error {
	if s.IsMock() {
		log.Printf("[sms:mock] phone=%s code=%s", phone, code)
		return nil
	}
	switch s.smsType {
	case "aliyun":
		return s.sendAliyun(phone, code)
	default:
		log.Printf("[sms:unknown-type] phone=%s code=%s type=%s", phone, code, s.smsType)
		return nil
	}
}

// ---- 阿里云短信 Dysmsapi（RPC + HMAC-SHA1 签名，无外部 SDK 依赖）----

const aliyunSMSAPI = "https://dysmsapi.aliyuncs.com/"

func (s *Sender) sendAliyun(phone, code string) error {
	if s.accessKeyID == "" || s.accessKeySecret == "" || s.signName == "" || s.templateCode == "" {
		log.Printf("[sms:aliyun] 凭据缺失，回退 mock。请配置 SMS_ACCESS_KEY_ID / SMS_ACCESS_KEY_SECRET / SMS_SIGN_NAME / SMS_TEMPLATE_CODE")
		log.Printf("[sms:mock-fallback] phone=%s code=%s", phone, code)
		return nil
	}

	templateParam, _ := json.Marshal(map[string]string{"code": code})

	params := map[string]string{
		"AccessKeyId":      s.accessKeyID,
		"Action":           "SendSms",
		"Format":           "JSON",
		"PhoneNumbers":     phone,
		"RegionId":         "cn-hangzhou",
		"SignName":         s.signName,
		"SignatureMethod":  "HMAC-SHA1",
		"SignatureNonce":   fmt.Sprintf("%d", time.Now().UnixNano()),
		"SignatureVersion": "1.0",
		"TemplateCode":     s.templateCode,
		"TemplateParam":    string(templateParam),
		"Timestamp":        time.Now().UTC().Format("2006-01-02T15:04:05Z"),
		"Version":          "2017-05-25",
	}

	// 签名
	params["Signature"] = s.signRPC(params, s.accessKeySecret)

	// 构建请求 URL
	values := url.Values{}
	for k, v := range params {
		values.Set(k, v)
	}
	apiURL := aliyunSMSAPI + "?" + values.Encode()

	resp, err := http.Get(apiURL)
	if err != nil {
		return fmt.Errorf("aliyun sms request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("aliyun sms read body: %w", err)
	}

	var result struct {
		Code      string `json:"Code"`
		Message   string `json:"Message"`
		RequestID string `json:"RequestId"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("aliyun sms parse response: %w", err)
	}
	if result.Code != "OK" {
		return fmt.Errorf("aliyun sms error: code=%s message=%s", result.Code, result.Message)
	}

	log.Printf("[sms:aliyun] phone=%s sent OK", phone)
	return nil
}

// signRPC 阿里云 RPC 签名（HMAC-SHA1 + Base64）。
func (s *Sender) signRPC(params map[string]string, secret string) string {
	// 1. 按 key 排序
	keys := make([]string, 0, len(params))
	for k := range params {
		if k == "Signature" {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)

	// 2. 构建 canonical query string（特殊 URL 编码）
	pairs := make([]string, 0, len(keys))
	for _, k := range keys {
		pairs = append(pairs, aliyunEncode(k)+"="+aliyunEncode(params[k]))
	}
	queryString := strings.Join(pairs, "&")

	// 3. string to sign: GET&%2F&<encoded query>
	stringToSign := "GET&" + aliyunEncode("/") + "&" + aliyunEncode(queryString)

	// 4. HMAC-SHA1
	mac := hmac.New(sha1.New, []byte(secret+"&"))
	mac.Write([]byte(stringToSign))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

// aliyunEncode 阿里云特殊 URL 编码（RFC 3986：空格→%20，*→%2A，~不编码）。
func aliyunEncode(s string) string {
	encoded := url.QueryEscape(s)
	// QueryEscape 用 + 代替空格，阿里云要求 %20
	encoded = strings.ReplaceAll(encoded, "+", "%20")
	// QueryEscape 不编码 *，阿里云要求 %2A
	encoded = strings.ReplaceAll(encoded, "*", "%2A")
	// QueryEscape 编码 ~，阿里云要求不编码
	encoded = strings.ReplaceAll(encoded, "%7E", "~")
	return encoded
}
