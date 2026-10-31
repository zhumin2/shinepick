#!/usr/bin/env bash
# 从本机导入测试数据后，修复图片引用与上传目录（一次性）
# 用法: sudo ./fix_after_import.sh <服务器对外IP或域名>
# 例:   sudo ./fix_after_import.sh 129.226.159.168
set -euo pipefail

SERVER_ADDR="${1:-}"
if [ -z "$SERVER_ADDR" ]; then
  echo "用法: sudo ./fix_after_import.sh <服务器对外IP或域名>"
  exit 1
fi

echo "==== 0/3 复制随仓库分发的图片文件 ===="
SRC="$(cd "$(dirname "$0")" && pwd)"
if [ -d "${SRC}/uploads" ]; then
  mkdir -p /opt/shinepick/uploads
  cp -r "${SRC}/uploads/avatars" "${SRC}/uploads/images" /opt/shinepick/uploads/ 2>/dev/null || true
  chown -R shinepick:shinepick /opt/shinepick/uploads 2>/dev/null || true
  echo "  已复制 avatars/images"
fi

echo "==== 1/3 数据库图片 URL 改为 http://${SERVER_ADDR}:8080 ===="
mysql -D shinepick -e "
UPDATE users SET avatar_url = REPLACE(avatar_url, 'http://127.0.0.1:8080', 'http://${SERVER_ADDR}:8080') WHERE avatar_url LIKE '%127.0.0.1:8080%';
UPDATE checkins SET image_urls = REPLACE(image_urls, 'http://127.0.0.1:8080', 'http://${SERVER_ADDR}:8080') WHERE image_urls LIKE '%127.0.0.1:8080%';
"
echo "  剩余 127.0.0.1 引用（应为 0）："
mysql -N -D shinepick -e "
  SELECT (SELECT COUNT(*) FROM users WHERE avatar_url LIKE '%127.0.0.1%')
       + (SELECT COUNT(*) FROM checkins WHERE image_urls LIKE '%127.0.0.1%');"

echo "==== 2/3 环境变量 PUBLIC_BASE_URL 指向对外地址（未来上传用）===="
ENVF=/opt/shinepick/shinepick.env
if [ -f "$ENVF" ]; then
  sed -i "s|^PUBLIC_BASE_URL=.*|PUBLIC_BASE_URL=http://${SERVER_ADDR}:8080|" "$ENVF"
  grep PUBLIC_BASE_URL "$ENVF"
fi

echo "==== 3/3 重启服务 ===="
systemctl restart shinepick-api 2>/dev/null || true
sleep 2
curl -s -m 5 http://127.0.0.1:8080/ping && echo

echo
echo "注意：图片的物理文件仍需从开发机上传："
echo "  开发机执行: scp -r 开发机uploads\\avatars 开发机uploads\\images 用户@${SERVER_ADDR}:/opt/shinepick/uploads/"
