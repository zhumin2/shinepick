package sms

import "log"

// Sender 短信发送。dev 环境使用 mock（打印验证码到日志），prod 接阿里云短信。
type Sender struct {
	smsType string
}

func NewSender(smsType string) *Sender {
	return &Sender{smsType: smsType}
}

// IsMock 是否 mock 通道（dev 固定验证码，见 S1 计划 §3.1）。
func (s *Sender) IsMock() bool { return s.smsType != "aliyun" }

func (s *Sender) Send(phone, code string) error {
	switch s.smsType {
	case "aliyun":
		// TODO(S2 前接入): 阿里云短信服务 Dysmsapi
		// return aliyunSend(phone, code)
		log.Printf("[sms:aliyun-pending] phone=%s code=%s", phone, code)
		return nil
	default:
		log.Printf("[sms:mock] phone=%s code=%s", phone, code)
		return nil
	}
}
