# 拾光 ShinePick · Linux 服务端部署

两种路线任选其一。

## 路线 A：二进制 + systemd（推荐单机）

包内容：`shinepick-api-linux-amd64`（或 arm64）、`migrations/`、`web/`（Web 前端构建产物，随仓库分发）、`shinepick-api.service`、`shinepick.env`、`install.sh`

> Web 前端更新流程：Windows 上 `flutter build web --release --base-href /static/web/` 后，把 `app/build/web` 覆盖到本目录 `web/` 并提交；服务器 `git pull` 后重跑 `sudo ./install.sh`（或手工 cp 到 /opt/shinepick/uploads/web）。

```bash
# 1. 上传整个 linux/ 目录到服务器，解压后：
sudo DB_PASS='你的数据库密码' ./install.sh

# 2. 改配置（JWT_SECRET / PUBLIC_BASE_URL / ADMIN_TOKEN 三项必改）
sudo vi /opt/shinepick/shinepick.env
sudo systemctl restart shinepick-api

# 3. 验证
curl http://127.0.0.1:8080/ping
```

- 二进制为 CGO_ENABLED=0 静态编译，无 glibc 依赖，任意发行版可用
- 服务以 `shinepick` 系统用户运行，systemd 沙箱加固（ProtectSystem=strict）
- 数据备份：`mysqldump shinepick` + `/opt/shinepick/uploads/` 目录
- 日志：`journalctl -u shinepick-api -f`

## 路线 B：Docker Compose（已有 `server/deploy/docker-compose.yml`）

```bash
cd server/deploy
docker compose up -d        # MySQL + Redis + API 三容器
```

## 交叉编译（在 Windows 上产出 Linux 二进制）

```bash
cd server
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/shinepick-api-linux-amd64 ./cmd/api
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/shinepick-api-linux-arm64 ./cmd/api
```

## 生产清单

- [ ] `JWT_SECRET` / `ADMIN_TOKEN` / 数据库密码全部改掉
- [ ] `PUBLIC_BASE_URL` 指向公网域名（Nginx 反代 8080 + HTTPS）
- [ ] `SMS_TYPE=aliyun` / `AUDIT_TYPE=remote` 接入真实通道
- [ ] MySQL 只监听 127.0.0.1，定期 `mysqldump` 备份
