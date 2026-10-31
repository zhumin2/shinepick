#!/usr/bin/env bash
# 拾光 ShinePick · Linux 服务端安装（Ubuntu 22.04+/Debian 12）
# 用法: sudo ./install.sh
set -euo pipefail

BASE=/opt/shinepick
SRC="$(cd "$(dirname "$0")" && pwd)"
DB_PASS="${DB_PASS:-CHANGE_ME}"

if [ "$(id -u)" -ne 0 ]; then echo "请用 sudo 运行"; exit 1; fi

echo "==== 1/6 系统依赖 (MySQL8 + Redis) ===="
apt-get update -qq
apt-get install -y -qq mysql-server redis-server curl >/dev/null
systemctl enable --now mysql redis-server

echo "==== 2/6 数据库（用户/密码/建库） ===="
mysql -e "CREATE DATABASE IF NOT EXISTS shinepick CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'shinepick'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON shinepick.* TO 'shinepick'@'localhost'; FLUSH PRIVILEGES;"

echo "==== 3/6 迁移（跳过 rollback 脚本） ===="
for f in "${SRC}"/migrations/0*.sql; do
  case "$f" in *rollback*) echo "  - $(basename "$f") skipped"; continue;; esac
  echo "  - $(basename "$f")"
  mysql --default-character-set=utf8mb4 -D shinepick < "$f"
done

echo "==== 4/6 程序与目录 ===="
id -u shinepick >/dev/null 2>&1 || useradd --system --home "$BASE" --shell /usr/sbin/nologin shinepick
mkdir -p "$BASE"/uploads/{avatars,images,web} "$BASE"/migrations
install -m 0755 "${SRC}/shinepick-api-linux-amd64" "$BASE/shinepick-api"
cp -r "${SRC}"/migrations/* "$BASE/migrations/" 2>/dev/null || true
[ -d "${SRC}/web" ] && cp -r "${SRC}/web" "$BASE/uploads/"
[ -d "${SRC}/uploads/avatars" ] && cp -r "${SRC}/uploads/avatars" "$BASE/uploads/" 2>/dev/null || true
[ -d "${SRC}/uploads/images" ] && cp -r "${SRC}/uploads/images" "$BASE/uploads/" 2>/dev/null || true
chown -R shinepick:shinepick "$BASE"

echo "==== 5/6 环境配置 ===="
if [ ! -f "$BASE/shinepick.env" ]; then
  sed "s/CHANGE_ME@/${DB_PASS}@/; s|UPLOAD_DIR=.*|UPLOAD_DIR=${BASE}/uploads|" \
    "${SRC}/shinepick.env" > "$BASE/shinepick.env"
  chmod 600 "$BASE/shinepick.env"
  echo "  已生成 $BASE/shinepick.env —— 请手工改 JWT_SECRET / PUBLIC_BASE_URL / ADMIN_TOKEN"
fi

echo "==== 6/6 systemd 服务 ===="
sed "s|WorkingDirectory=.*|WorkingDirectory=${BASE}|" "${SRC}/shinepick-api.service" > /etc/systemd/system/shinepick-api.service
systemctl daemon-reload
systemctl enable --now shinepick-api
sleep 2
systemctl --no-pager status shinepick-api | head -5

echo
echo "==== 安装完成 ===="
echo "健康检查: curl http://127.0.0.1:8080/ping"
echo "Web:      http://127.0.0.1:8080/static/web/"
echo "日志:     journalctl -u shinepick-api -f"
