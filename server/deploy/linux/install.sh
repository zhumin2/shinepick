#!/usr/bin/env bash
# 拾光 ShinePick · Linux 服务端安装
# 支持: Ubuntu/Debian (apt) + OpenCloudOS/CentOS/RHEL (dnf/yum)
# 用法: sudo ./install.sh
set -euo pipefail

BASE=/opt/shinepick
SRC="$(cd "$(dirname "$0")" && pwd)"
DB_PASS="${DB_PASS:-CHANGE_ME}"

if [ "$(id -u)" -ne 0 ]; then echo "请用 sudo 运行"; exit 1; fi

# ---- 检测包管理器 ----
if command -v apt-get &>/dev/null; then
  PKG_MGR=apt
elif command -v dnf &>/dev/null; then
  PKG_MGR=dnf
elif command -v yum &>/dev/null; then
  PKG_MGR=yum
else
  echo "不支持的发行版：未找到 apt-get / dnf / yum"
  exit 1
fi
echo "包管理器: $PKG_MGR"

echo "==== 1/6 系统依赖 (MySQL + Redis) ===="
if [ "$PKG_MGR" = "apt" ]; then
  apt-get update -qq
  apt-get install -y -qq mysql-server redis-server curl >/dev/null
  systemctl enable --now mysql redis-server
else
  # OpenCloudOS / CentOS / RHEL
  $PKG_MGR install -y -q mysql-server redis curl >/dev/null 2>&1 ||     $PKG_MGR install -y -q mysql-community-server redis curl >/dev/null 2>&1 ||     { echo "请手动安装 MySQL 和 Redis 后重跑（跳过此步）"; }
  systemctl enable --now mysqld 2>/dev/null || systemctl enable --now mysql 2>/dev/null || true
  systemctl enable --now redis 2>/dev/null || systemctl enable --now redis-server 2>/dev/null || true
  # 等待 MySQL 就绪
  for i in $(seq 1 30); do
    mysqladmin ping &>/dev/null && break
    sleep 1
  done
fi

echo "==== 2/6 数据库（建库/授权） ===="
# MySQL root 密码处理：apt 装=免密；yum 装=可能需要临时密码或已有密码
if [ "$PKG_MGR" = "apt" ]; then
  mysql -e "CREATE DATABASE IF NOT EXISTS shinepick CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mysql -e "CREATE USER IF NOT EXISTS 'shinepick'@'localhost' IDENTIFIED BY '${DB_PASS}';"
  mysql -e "GRANT ALL PRIVILEGES ON shinepick.* TO 'shinepick'@'localhost'; FLUSH PRIVILEGES;"
else
  # RHEL 系：root 可能有临时密码或已有密码
  if mysql -u root -e "SELECT 1" &>/dev/null; then
    mysql -e "CREATE DATABASE IF NOT EXISTS shinepick CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER IF NOT EXISTS 'shinepick'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON shinepick.* TO 'shinepick'@'localhost'; FLUSH PRIVILEGES;"
  else
    echo "  MySQL root 需要密码（请设置 DB_ROOT_PASS 环境变量）"
    echo "  手动执行:"
    echo "    mysql -u root -p -e \"CREATE DATABASE IF NOT EXISTS shinepick CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\""
    echo "    mysql -u root -p -e \"CREATE USER IF NOT EXISTS 'shinepick'@'localhost' IDENTIFIED BY '${DB_PASS}';\""
    echo "    mysql -u root -p -e \"GRANT ALL PRIVILEGES ON shinepick.* TO 'shinepick'@'localhost'; FLUSH PRIVILEGES;\""
    echo "  然后重跑本脚本。"
    exit 1
  fi
fi

echo "==== 3/6 迁移（跳过 rollback 脚本） ===="
MYSQL_CMD="mysql"
if [ "$PKG_MGR" != "apt" ]; then
  MYSQL_CMD="mysql -u shinepick -p${DB_PASS}"
fi
for f in "${SRC}"/migrations/0*.sql; do
  case "$f" in *rollback*) echo "  - $(basename "$f") skipped"; continue;; esac
  echo "  - $(basename "$f")"
  $MYSQL_CMD --default-character-set=utf8mb4 -D shinepick < "$f"
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
  sed "s/CHANGE_ME@/${DB_PASS}@/; s|UPLOAD_DIR=.*|UPLOAD_DIR=${BASE}/uploads|"     "${SRC}/shinepick.env" > "$BASE/shinepick.env"
  chmod 600 "$BASE/shinepick.env"
  echo "  已生成 $BASE/shinepick.env —— 请手工改 JWT_SECRET / PUBLIC_BASE_URL / ADMIN_TOKEN"
fi

echo "==== 6/6 systemd 服务 ===="
sed "s|WorkingDirectory=.*|WorkingDirectory=${BASE}|" "${SRC}/shinepick-api.service" > /etc/systemd/system/shinepick-api.service
systemctl daemon-reload
systemctl enable --now shinepick-api
sleep 2
systemctl --no-pager status shinepick-api | head -5

# 安装管理脚本到系统路径
if [ -f "${SRC}/shinepick.sh" ]; then
  install -m 0755 "${SRC}/shinepick.sh" /usr/local/bin/shinepick
  echo "  管理脚本已安装: shinepick <start|stop|status|health|logs|backup|update>"
fi

echo
echo "==== 安装完成 ===="
echo "健康检查: curl http://127.0.0.1:8080/ping"
echo "Web:      http://127.0.0.1:8080/static/web/"
echo "日志:     journalctl -u shinepick-api -f"
