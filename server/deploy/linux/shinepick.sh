#!/usr/bin/env bash
# 拾光 ShinePick · 服务端统一管理脚本
# 用法: shinepick.sh <命令>
#   start    启动全部服务（MySQL → Redis → API）
#   stop     停止全部服务（API → Redis → MySQL）
#   restart  重启全部服务
#   status   查看各服务运行状态
#   health   健康检查（API /ping + DB 连通 + Redis 连通）
#   logs     查看 API 日志（实时，Ctrl+C 退出）
#   backup   备份数据库到 /opt/shinepick/backups/
#   update   git pull + 前端 + API 二进制 + 重启
#   help     显示帮助
set -uo pipefail

BASE=/opt/shinepick
ENVF=$BASE/shinepick.env
API_PORT=8080
MYSQL_SERVICE=mysqld
REDIS_SERVICE=redis
BACKUP_DIR=$BASE/backups
KEEP_BACKUPS=7

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${YELLOW}●${NC} $1"; }

# ---- 从 env 文件读取数据库密码 ----
db_creds() {
  if [ -f "$ENVF" ]; then
    DB_USER=$(sed -n 's/^DB_DSN=\([^:]*\):.*@tcp.*/\1/p' "$ENVF")
    DB_PASS=$(sed -n 's/^DB_DSN=[^:]*:\([^@]*\)@tcp.*/\1/p' "$ENVF")
    DB_PORT=$(sed -n 's/^DB_DSN=[^@]*@tcp([^:]*):\([0-9]*\)).*/\1/p' "$ENVF")
  fi
  DB_USER="${DB_USER:-root}"
  DB_PASS="${DB_PASS:-}"
  DB_PORT="${DB_PORT:-3306}"
}

# ---- 命令实现 ----

do_start() {
  echo "启动拾光服务..."
  for svc in $MYSQL_SERVICE $REDIS_SERVICE shinepick-api; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      ok "$svc 已在运行"
    else
      systemctl start "$svc" 2>/dev/null
      sleep 1
      if systemctl is-active --quiet "$svc" 2>/dev/null; then
        ok "$svc 已启动"
      else
        fail "$svc 启动失败"
      fi
    fi
  done
  health_check
}

do_stop() {
  echo "停止拾光服务..."
  for svc in shinepick-api $REDIS_SERVICE $MYSQL_SERVICE; do
    systemctl stop "$svc" 2>/dev/null
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      fail "$svc 停止失败"
    else
      ok "$svc 已停止"
    fi
  done
}

do_restart() {
  echo "重启拾光服务..."
  do_stop
  sleep 2
  do_start
}

do_status() {
  echo "拾光服务状态："
  for svc in $MYSQL_SERVICE $REDIS_SERVICE shinepick-api; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      ok "$svc: 运行中"
    else
      fail "$svc: 已停止"
    fi
  done
  echo ""
  echo "开机自启："
  for svc in $MYSQL_SERVICE $REDIS_SERVICE shinepick-api; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      ok "$svc: 已启用"
    else
      info "$svc: 未启用"
    fi
  done
}

health_check() {
  echo ""
  echo "健康检查："
  sleep 1
  # API
  resp=$(curl -s -m 5 http://127.0.0.1:$API_PORT/ping 2>/dev/null)
  if echo "$resp" | grep -q '"pong":true'; then
    ok "API: 正常 ($resp)"
  else
    fail "API: 无响应"
  fi
  # MySQL
  db_creds
  if mysql -h 127.0.0.1 -P "$DB_PORT" --protocol=tcp -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" &>/dev/null; then
    ok "MySQL: 连通"
  else
    fail "MySQL: 无法连接"
  fi
  # Redis
  if redis-cli ping 2>/dev/null | grep -q PONG; then
    ok "Redis: PONG"
  else
    fail "Redis: 无响应"
  fi
}

do_logs() {
  journalctl -u shinepick-api -f --no-pager
}

do_backup() {
  mkdir -p "$BACKUP_DIR"
  db_creds
  local FILE="$BACKUP_DIR/shinepick-$(date +%Y%m%d_%H%M%S).sql.gz"
  echo "备份数据库..."
  mysqldump -h 127.0.0.1 -P "$DB_PORT" --protocol=tcp \
    -u "$DB_USER" -p"$DB_PASS" \
    --single-transaction --routines --triggers \
    --default-character-set=utf8mb4 \
    shinepick | gzip > "$FILE"
  if [ -s "$FILE" ]; then
    ok "备份完成: $FILE ($(du -h "$FILE" | cut -f1))"
  else
    fail "备份失败"
    return 1
  fi
  # 清理旧备份
  local old_count=$(ls -1 "$BACKUP_DIR"/shinepick-*.sql.gz 2>/dev/null | wc -l)
  if [ "$old_count" -gt "$KEEP_BACKUPS" ]; then
    ls -1t "$BACKUP_DIR"/shinepick-*.sql.gz | tail -n +$((KEEP_BACKUPS + 1)) | while read f; do
      rm "$f"; info "清理旧备份: $(basename "$f")"
    done
  fi
}

do_update() {
  echo "更新拾光服务..."
  # 从当前目录向上找 git 仓库根（脚本装在 /usr/local/bin，自身无仓库上下文；
  # 须在仓库内或其子目录执行）
  local REPO_DIR
  REPO_DIR=$(pwd)
  while [ "$REPO_DIR" != "/" ] && [ ! -d "$REPO_DIR/.git" ]; do
    REPO_DIR=$(dirname "$REPO_DIR")
  done
  if [ ! -d "$REPO_DIR/.git" ]; then
    fail "未找到 git 仓库（请先 cd 到 shinepick 仓库目录后执行）"
    return 1
  fi
  cd "$REPO_DIR"
  info "git pull..."
  git pull origin main || { fail "git pull 失败"; return 1; }
  # 重新部署前端
  if [ -d "server/deploy/linux/web" ]; then
    info "更新 Web 前端..."
    rm -rf "$BASE/uploads/web"
    cp -r server/deploy/linux/web "$BASE/uploads/web"
    chown -R shinepick:shinepick "$BASE/uploads"
  fi
  # 替换 API 二进制：优先本机 go 编译；无 go 则用仓库内预编译产物
  info "更新 API 二进制..."
  local BUILT=0
  if command -v go >/dev/null 2>&1; then
    # 服务器在国内：未显式配置 GOPROXY 时走 goproxy.cn，避免官方源被墙卡死
    if (cd server && CGO_ENABLED=0 GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" go build -o "$BASE/shinepick-api.new" ./cmd/api); then
      BUILT=1
      ok "go 编译成功"
    else
      fail "go 编译失败，回退到仓库预编译二进制"
    fi
  fi
  if [ "$BUILT" != "1" ]; then
    local ARCH PRE
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64)  PRE=shinepick-api-linux-amd64 ;;
      aarch64) PRE=shinepick-api-linux-arm64 ;;
      *) fail "不支持的架构 $ARCH（预编译二进制仅 amd64/arm64）"; return 1 ;;
    esac
    if [ ! -f "server/deploy/linux/bin/$PRE" ]; then
      fail "仓库内无预编译二进制 server/deploy/linux/bin/$PRE；请在有 go 的机器上编译后上传"
      return 1
    fi
    cp "server/deploy/linux/bin/$PRE" "$BASE/shinepick-api.new"
    ok "使用仓库预编译二进制（$PRE）"
  fi
  # mv 替换 inode，运行中的旧进程不受影响（重启后切换到新二进制）
  chmod 755 "$BASE/shinepick-api.new"
  mv -f "$BASE/shinepick-api.new" "$BASE/shinepick-api"
  chown shinepick:shinepick "$BASE/shinepick-api" 2>/dev/null || true
  # 重启 API
  systemctl restart shinepick-api
  sleep 2
  health_check
}

do_help() {
  echo "拾光 ShinePick 服务端管理"
  echo ""
  echo "用法: shinepick.sh <命令>"
  echo ""
  echo "  start     启动全部服务"
  echo "  stop      停止全部服务"
  echo "  restart   重启全部服务"
  echo "  status    查看服务状态"
  echo "  health    健康检查"
  echo "  logs      查看 API 实时日志"
  echo "  backup    备份数据库（保留最近 $KEEP_BACKUPS 份）"
  echo "  update    从 git 更新代码/前端/API 二进制并重启"
  echo "  help      显示本帮助"
}

# ---- 入口 ----
case "${1:-help}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_restart ;;
  status)  do_status ;;
  health)  health_check ;;
  logs)    do_logs ;;
  backup)  do_backup ;;
  update)  do_update ;;
  help|*)  do_help ;;
esac
