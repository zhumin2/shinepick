package sms

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// Sender 短信发送。mock = 打印日志；tencent = 腾讯云短信 SMS API。
type Sender struct {
	smsType    string
	secretID   string
	secretKey  string
	appID      string
	signName   string
	templateID string
}

// SMSConfig 短信服务配置。
type SMSConfig struct {
	Type       string // mock / tencent
	SecretID   string // 腾讯云 API SecretId
	SecretKey  string // 腾讯云 API SecretKey
	AppID      string // 短信 SmsSdkAppId
	SignName   string // 短信签名名称
	TemplateID string // 短信模板 ID
}

func NewSender(cfg SMSConfig) *Sender {
	return &Sender{
		smsType:    cfg.Type,
		secretID:   cfg.SecretID,
		secretKey:  cfg.SecretKey,
		appID:      cfg.AppID,
		signName:   cfg.SignName,
		templateID: cfg.TemplateID,
	}
}

// IsMock 是否 mock 通道（dev 固定验证码，见 S1 计划 §3.1）。
func (s *Sender) IsMock() bool {
	return s.smsType != "tencent" ||
		s.secretID == "" || s.secretKey == "" ||
		s.appID == "" || s.signName == "" || s.templateID == ""
}

// Send 发送验证码短信。
func (s *Sender) Send(phone, code string) error {
	if s.IsMock() {
		log.Printf("[sms:mock] phone=%s code=%s", phone, code)
		return nil
	}
	switch s.smsType {
	case "tencent":
		return s.sendTencent(phone, code)
	default:
		log.Printf("[sms:unknown] phone=%s type=%s", phone, s.smsType)
		return nil
	}
}

// ---- 腾讯云短信 API（TC3-HMAC-SHA256 签名，无外部 SDK 依赖）----

const (
	tencentSMSAPI     = "https://sms.tencentcloudapi.com"
	tencentSMSService = "sms"
	tencentSMSVersion = "2021-01-11"
)

func (s *Sender) sendTencent(phone, code string) error {
	reqBody, _ := json.Marshal(map[string]interface{}{
		"PhoneNumberSet":   []string{"+86" + phone},
		"SmsSdkAppId":      s.appID,
		"SignName":         s.signName,
		"TemplateId":       s.templateID,
		"TemplateParamSet": []string{code},
	})

	timestamp := time.Now().Unix()
	date := time.Unix(timestamp, 0).UTC().Format("2006-01-02")

	signature := s.signTC3(reqBody, timestamp, date)

	req, err := http.NewRequest("POST", tencentSMSAPI, bytes.NewReader(reqBody))
	if err != nil {
		return fmt.Errorf("tencent sms new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("Host", "sms.tencentcloudapi.com")
	req.Header.Set("X-TC-Action", "SendSms")
	req.Header.Set("X-TC-Version", tencentSMSVersion)
	req.Header.Set("X-TC-Timestamp", fmt.Sprintf("%d", timestamp))
	req.Header.Set("X-TC-Region", "")
	req.Header.Set("Authorization",
		fmt.Sprintf("TC3-HMAC-SHA256 Credential=%s/%s/%s/tc3_request, SignedHeaders=content-type;host, Signature=%s",
			s.secretID, date, tencentSMSService, signature))

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("tencent sms request: %w", err)
	}
	defer resp.Body.Close()

	result, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("tencent sms read body: %w", err)
	}

	var out struct {
		Response struct {
			SendStatusSet []struct {
				Code    string `json:"Code"`
				Message string `json:"Message"`
			} `json:"SendStatusSet"`
			Error *struct {
				Code    string `json:"Code"`
				Message string `json:"Message"`
			} `json:"Error"`
		} `json:"Response"`
	}
	if err := json.Unmarshal(result, &out); err != nil {
		return fmt.Errorf("tencent sms parse: %w", err)
	}
	if out.Response.Error != nil {
		return fmt.Errorf("tencent sms error: %s %s", out.Response.Error.Code, out.Response.Error.Message)
	}
	for _, st := range out.Response.SendStatusSet {
		if st.Code != "Ok" {
			return fmt.Errorf("tencent sms send status: %s %s", st.Code, st.Message)
		}
	}

	log.Printf("[sms:tencent] phone=%s sent OK", phone)
	return nil
}

// signTC3 腾讯云 API 3.0 签名（TC3-HMAC-SHA256）。
func (s *Sender) signTC3(body []byte, timestamp int64, date string) string {
	hashedBody := sha256Hex(body)
	canonicalRequest := "POST\n/\n\ncontent-type:application/json; charset=utf-8\nhost:sms.tencentcloudapi.com\n\ncontent-type;host\n" + hashedBody

	hashedCanonical := sha256Hex([]byte(canonicalRequest))
	stringToSign := fmt.Sprintf("TC3-HMAC-SHA256\n%d\n%s\n%s/tc3_request\n%s",
		timestamp, date, tencentSMSService, hashedCanonical)

	kDate := hmacSHA256([]byte("TC3"+s.secretKey), date)
	kService := hmacSHA256(kDate, tencentSMSService)
	kSigning := hmacSHA256(kService, "tc3_request")

	return hex.EncodeToString(hmacSHA256(kSigning, stringToSign))
}

// ---- 工具 ----

func sha256Hex(b []byte) string {
	h := sha256.New()
	h.Write(b)
	return hex.EncodeToString(h.Sum(nil))
}

func hmacSHA256(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(data))
	return h.Sum(nil)
}
