package code

// 错误码（对齐技术设计文档 §5.4）
const (
	OK              = 0
	ErrBadRequest   = 1001 // 参数错误
	ErrUnauthorized = 2001 // 未登录 / Token 过期
	ErrSmsInvalid   = 3001 // 验证码错误或过期
	ErrTooFrequent  = 4001 // 操作过于频繁
	ErrNotFound     = 5001 // 目标不存在或已删除
	ErrForbidden    = 5002 // 无权限
	ErrAuditReject  = 4101 // 内容未通过审核
	ErrInternal     = 9000 // 服务内部错误
)

// Message 返回错误码对应文案（客户端可展示）。
func Message(code int) string {
	switch code {
	case OK:
		return "ok"
	case ErrBadRequest:
		return "参数错误"
	case ErrUnauthorized:
		return "未登录或登录已过期"
	case ErrSmsInvalid:
		return "验证码错误或已过期"
	case ErrTooFrequent:
		return "操作过于频繁，请稍后再试"
	case ErrNotFound:
		return "目标不存在或已删除"
	case ErrForbidden:
		return "没有权限"
	case ErrAuditReject:
		return "内容未通过审核"
	default:
		return "服务开小差了，请稍后重试"
	}
}
