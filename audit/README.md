# audit 审核服务（独立 Python 服务）

## 职责
- 文本/图片内容安全审核（阿里云内容安全 SDK）
- 语气规则引擎 + LLM 抽检（讽刺/说教/优越感识别）
- 与主服务 Go 解耦，独立部署

## 接口（S3 实现）
- POST /audit/text   入参 {"content": "..."} → {"pass": bool, "risk": "..."}
- POST /audit/image  入参 {"url": "..."} → {"pass": bool, "risk": "..."}

## 目录（S3 填充）
- app/main.py
- app/services/
- requirements.txt
