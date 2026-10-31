#!/usr/bin/env bash
# 拾光 · 服务器端数据导入
# 用法: sudo ./import_remote.sh /tmp/shinepick-data.sql
# 语义: REPLACE INTO —— 服务器同主键数据会被本机导出数据覆盖（以导出端为准）
set -euo pipefail

FILE="${1:-}"
DB_NAME=shinepick

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "用法: sudo ./import_remote.sh <sql文件路径>"
  exit 1
fi

echo "导入 $FILE 到 $DB_NAME ..."
if sudo mysql "$DB_NAME" < "$FILE"; then
  echo "导入完成。行数统计："
  for t in users checkins comments reactions companion_relations notifications blocks reports badges user_badges tree_progress user_secure; do
    n=$(mysql -N -D "$DB_NAME" -e "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo '?')
    printf '  %-20s %s\n' "$t" "$n"
  done
else
  echo "导入失败：检查文件与 MySQL 权限。"
  exit 1
fi
