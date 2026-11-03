#!/usr/bin/env bash
# 拾光 ShinePick · 旧服务器备份打包
# 迁移目标: 129.226.159.168（旧，腾讯云） → 8.134.144.35（新，阿里云）
#
# 在【旧服务器】以 root 运行:
#   sudo ./backup-old.sh
#   sudo ./backup-old.sh --push root@8.134.144.35
#   sudo ./backup-old.sh --out /data/migrate --with-redis
#
# 产出（默认 /root/shinepick-migrate/）:
#   shinepick-migrate-<时间戳>.tar.gz         迁移包
#   shinepick-migrate-<时间戳>.tar.gz.sha256  整包校验值
#
# 包内包含: MySQL 逻辑备份、/opt/shinepick（含 uploads）、环境变量、
# systemd 单元、Nginx/证书（若存在）、apkserver、主机清单、restore-new.sh。
#
# 停机窗口: 仅“导出数据库 + 同步 uploads”期间停止 shinepick-api，
# 其余收集/打包步骤均在服务恢复后执行；脚本异常退出会自动拉起 API。
set -Eeuo pipefail

APP_NAME="shinepick"
APP_BASE="${APP_BASE:-/opt/shinepick}"
APK_BASE="${APK_BASE:-/opt/apkserver}"
APP_BASE="${APP_BASE%/}"
APK_BASE="${APK_BASE%/}"
OUT_ROOT="${OUT_ROOT:-/root/shinepick-migrate}"

STAMP="$(date +%Y%m%d_%H%M%S)"
BUNDLE_NAME="shinepick-migrate-$STAMP"

STOP_API=1
WITH_NGINX=1
WITH_CERTS=1
WITH_APK=1
WITH_REDIS=0
KEEP_BUNDLE=0
COMPRESS="gzip"
PUSH_TARGET=""

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; NC=""
fi
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
die()  { printf '  %s✗%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
step() { printf '\n==== %s ====\n' "$*"; }

usage() {
  cat <<'EOF'
用法: sudo ./backup-old.sh [选项]

选项:
  -o, --out DIR       输出目录（默认 /root/shinepick-migrate）
      --no-stop       备份期间不停止 API（数据库可能不是严格一致快照）
      --no-nginx      不收集 /etc/nginx
      --no-certs      不收集 /etc/letsencrypt、/root/.acme.sh
      --no-apk        不收集 /opt/apkserver
      --with-redis    额外备份 /var/lib/redis（缓存通常无需迁移）
      --zstd          用 zstd 压缩（需已安装 zstd，产出 .tar.zst）
      --keep-bundle   打包后保留解包目录
      --push DEST     打包后推送到新服务器，DEST 形如 root@8.134.144.35
                      或 root@8.134.144.35:/root
  -h, --help          显示帮助
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)
      [ $# -ge 2 ] || die "$1 需要目录参数"
      OUT_ROOT="$2"; shift 2 ;;
    --no-stop)    STOP_API=0; shift ;;
    --no-nginx)   WITH_NGINX=0; shift ;;
    --no-certs)   WITH_CERTS=0; shift ;;
    --no-apk)     WITH_APK=0; shift ;;
    --with-redis) WITH_REDIS=1; shift ;;
    --zstd)       COMPRESS="zstd"; shift ;;
    --keep-bundle) KEEP_BUNDLE=1; shift ;;
    --push)
      [ $# -ge 2 ] || die "$1 需要目标，如 root@8.134.144.35"
      PUSH_TARGET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（-h 查看用法）" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "请用 root 运行: sudo $0"
[ -n "$OUT_ROOT" ] || die "--out 不能为空"

case "$APP_BASE" in
  /opt/*|/srv/*|/data/*|/home/*|/var/www/*) ;;
  *) die "APP_BASE 不在允许的部署根目录（/opt、/srv、/data、/home、/var/www）: $APP_BASE" ;;
esac
case "$APK_BASE" in
  /opt/*|/srv/*|/data/*|/home/*|/var/www/*) ;;
  *) die "APK_BASE 不在允许的部署根目录（/opt、/srv、/data、/home、/var/www）: $APK_BASE" ;;
esac
if [[ "$APP_BASE" == *".."* ]] || [[ "$APK_BASE" == *".."* ]]; then
  die "APP_BASE / APK_BASE 不能包含 .."
fi

BUNDLE="$OUT_ROOT/$BUNDLE_NAME"
if [ "$COMPRESS" = "zstd" ]; then
  ARCHIVE="$OUT_ROOT/$BUNDLE_NAME.tar.zst"
else
  ARCHIVE="$OUT_ROOT/$BUNDLE_NAME.tar.gz"
fi

# ---- 异常退出时恢复 API ----
STOPPED_API=0
cleanup() {
  local rc=$?
  if [ "$STOPPED_API" = "1" ]; then
    printf '\n  %s!%s 流程退出，重新启动 shinepick-api ...\n' "$YELLOW" "$NC"
    if systemctl start shinepick-api 2>/dev/null; then
      sleep 2
      if ! command -v curl >/dev/null 2>&1; then
        warn "shinepick-api 已启动；未安装 curl，跳过健康检查"
      elif curl -fsS -m 5 http://127.0.0.1:8080/ping 2>/dev/null | grep -q '"pong":true'; then
        ok "shinepick-api 已恢复"
      else
        warn "shinepick-api 已启动，但健康检查未通过；请查看 journalctl -u shinepick-api -n 50"
      fi
    else
      warn "shinepick-api 启动失败，请手动执行: systemctl start shinepick-api"
    fi
  fi
  unset MYSQL_PWD 2>/dev/null || true
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ======================================================================
step "0/7 环境检查"
# ======================================================================
for c in tar gzip sha256sum od du df awk sed grep; do
  command -v "$c" >/dev/null 2>&1 || die "缺少命令: $c"
done
tar --version 2>/dev/null | grep -q 'GNU tar' || die "需要 GNU tar"
if [ "$COMPRESS" = "zstd" ]; then
  command -v zstd >/dev/null 2>&1 || die "指定了 --zstd，但未安装 zstd"
fi

[ -d "$APP_BASE" ] || die "未找到应用目录 $APP_BASE；本脚本按二进制 + systemd 部署（路线 A）编写，Docker 部署请先手工处理"
[ -f "$APP_BASE/shinepick-api" ] || die "未找到 $APP_BASE/shinepick-api，迁移包会缺少可执行文件"
ENV_FILE="$APP_BASE/shinepick.env"
[ -f "$ENV_FILE" ] || die "未找到 $ENV_FILE"

if command -v mysqldump >/dev/null 2>&1; then
  DUMP_BIN="$(command -v mysqldump)"
elif command -v mariadb-dump >/dev/null 2>&1; then
  DUMP_BIN="$(command -v mariadb-dump)"
else
  die "缺少 mysqldump / mariadb-dump"
fi
if command -v mysql >/dev/null 2>&1; then
  MYSQL_BIN="$(command -v mysql)"
elif command -v mariadb >/dev/null 2>&1; then
  MYSQL_BIN="$(command -v mariadb)"
else
  die "缺少 mysql / mariadb 客户端"
fi

# ---- 解析 DSN ----
dsn_line="$(grep -E '^[[:space:]]*DB_DSN=' "$ENV_FILE" | tail -1 || true)"
[ -n "$dsn_line" ] || die "$ENV_FILE 中没有 DB_DSN"
DB_DSN="${dsn_line#*=}"
DB_DSN="${DB_DSN%\"}"; DB_DSN="${DB_DSN#\"}"
DB_DSN="${DB_DSN%\'}"; DB_DSN="${DB_DSN#\'}"
[[ "$DB_DSN" == *"@tcp("* ]] || die "无法解析 DB_DSN（仅支持 tcp 形式）: $DB_DSN"

creds="${DB_DSN%%@tcp(*}"
rest="${DB_DSN#*@tcp(}"
DB_HOSTPORT="${rest%%)*}"
DB_NAME="${rest#*)/}"
DB_NAME="${DB_NAME%%\?*}"
DB_USER="${creds%%:*}"
if [[ "$creds" == *:* ]]; then
  DB_PASS="${creds#*:}"
else
  DB_PASS=""
fi
DB_HOST="${DB_HOSTPORT%%:*}"
if [ "$DB_HOSTPORT" = "$DB_HOST" ]; then
  DB_PORT=3306
else
  DB_PORT="${DB_HOSTPORT##*:}"
fi
[ -n "$DB_NAME" ] || die "DB_DSN 中没有数据库名"
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || die "数据库名包含不支持的字符: $DB_NAME"

# ---- 对外地址 ----
PUBLIC_BASE_URL="$(grep -E '^[[:space:]]*PUBLIC_BASE_URL=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%\"}"; PUBLIC_BASE_URL="${PUBLIC_BASE_URL#\"}"
if [ -n "$PUBLIC_BASE_URL" ]; then
  SOURCE_IP="${PUBLIC_BASE_URL#*://}"
  SOURCE_IP="${SOURCE_IP%%[:/]*}"
else
  SOURCE_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  warn "shinepick.env 未配置 PUBLIC_BASE_URL，将使用本机地址 $SOURCE_IP"
fi

# ---- 数据库连通性（DSN 失败时回退 root socket）----
USE_SOCKET=0
mysql_tcp() {
  MYSQL_PWD="$DB_PASS" "$MYSQL_BIN" --protocol=tcp -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$@"
}
if ! mysql_tcp -e 'SELECT 1' >/dev/null 2>&1; then
  if [ "$DB_HOST" = "127.0.0.1" ] || [ "$DB_HOST" = "localhost" ]; then
    if "$MYSQL_BIN" -u root -e 'SELECT 1' >/dev/null 2>&1; then
      warn "DB_DSN 账号连接失败，改用 root socket 认证备份"
      USE_SOCKET=1
      DB_USER="root"
      DB_PASS=""
    else
      die "数据库连接失败: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    fi
  else
    die "数据库不在本机（$DB_HOST），请先确认远程库的备份方式"
  fi
fi
mysql_q() {
  if [ "$USE_SOCKET" = "1" ]; then
    "$MYSQL_BIN" -u root "$@"
  else
    mysql_tcp "$@"
  fi
}
MYSQL_VERSION="$(mysql_q -N -e 'SELECT VERSION()' 2>/dev/null | head -1 || true)"
[ -n "$MYSQL_VERSION" ] || die "无法读取 MySQL 版本"
if "$DUMP_BIN" --version 2>/dev/null | grep -qi 'mariadb'; then
  DB_FLAVOR="MariaDB"
else
  DB_FLAVOR="MySQL"
fi
ok "应用目录 $APP_BASE"
ok "数据库 $DB_NAME @ ${DB_HOST}:${DB_PORT}（$DB_FLAVOR $MYSQL_VERSION，用户 $DB_USER）"
ok "对外地址 ${PUBLIC_BASE_URL:-未配置}（IP $SOURCE_IP）"

# ---- 磁盘空间 ----
mkdir -p "$OUT_ROOT"
chmod 700 "$OUT_ROOT"
HAS_UPLOADS=1
if [ ! -d "$APP_BASE/uploads" ]; then
  HAS_UPLOADS=0
  warn "$APP_BASE/uploads 不存在，将只迁移数据库与程序文件"
fi
uploads_kb="$(du -sk "$APP_BASE/uploads" 2>/dev/null | awk '{print $1}' || true)"
uploads_kb="${uploads_kb:-0}"
free_kb="$(df -Pk "$OUT_ROOT" | awk 'NR==2 {print $4}')"
need_kb=$(( uploads_kb * 2 + uploads_kb / 5 + 512 * 1024 ))
if [ -n "$free_kb" ] && [ "$free_kb" -lt "$need_kb" ]; then
  die "磁盘空间不足: 需要约 $((need_kb/1024)) MB，$OUT_ROOT 仅剩 $((free_kb/1024)) MB"
fi
ok "磁盘空间充足（uploads $(awk -v k="$uploads_kb" 'BEGIN{printf "%.1f", k/1024}') MB）"

mkdir -p "$BUNDLE"/{db,files,config,inventory,nginx}
chmod 700 "$BUNDLE"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- 拷贝目录（保留属主/权限/硬链接）----
copy_tree() {
  local rel="$1"; shift
  tar -C / --numeric-owner --warning=no-file-changed -cf - "$@" "$rel" \
    | tar -C "$BUNDLE/files" --numeric-owner -xf -
}
read_elf_arch() {
  local f="$1" bytes
  [ -f "$f" ] || { printf 'unknown'; return 0; }
  bytes="$(od -An -t x1 -j 18 -N 2 "$f" 2>/dev/null | tr -d ' \n' || true)"
  case "$bytes" in
    3e00) printf 'x86_64' ;;
    b700) printf 'aarch64' ;;
    *)    printf 'unknown' ;;
  esac
}
BINARY_ARCH="$(read_elf_arch "$APP_BASE/shinepick-api")"
HOST_ARCH="$(uname -m)"

# ======================================================================
step "1/7 预拷贝程序文件（服务保持运行）"
# ======================================================================
copy_tree "${APP_BASE#/}" \
  --exclude="${APP_BASE#/}/uploads" \
  --exclude="${APP_BASE#/}/backups" \
  --exclude="${APP_BASE#/}/*.log"
ok "已复制 $APP_BASE（不含 uploads / backups / 日志）"

APK_INCLUDED=0
if [ "$WITH_APK" = "1" ] && [ -d "$APK_BASE" ]; then
  # APK 目录可能正在增删，复制失败只告警，不影响核心数据
  copy_tree "${APK_BASE#/}" --exclude="${APK_BASE#/}/*.log" \
    || warn "复制 $APK_BASE 时有文件变化，请恢复后核对 apks/ 目录"
  APK_INCLUDED=1
  ok "已复制 $APK_BASE"
fi

# uploads 先粗同步一次，停机后只需增量，缩短写停顿
sync_uploads_prepare() {
  local dest="$BUNDLE/files${APP_BASE}/uploads"
  mkdir -p "$dest"
  [ "$HAS_UPLOADS" = "1" ] || return 0
  if command -v rsync >/dev/null 2>&1; then
    if ! rsync -aHAX --numeric-ids --delete "$APP_BASE/uploads/" "$dest/"; then
      warn "uploads 预同步有文件变化，停机后会再次同步"
    fi
  fi
}
sync_uploads_prepare
if [ "$HAS_UPLOADS" = "1" ] && command -v rsync >/dev/null 2>&1; then
  ok "uploads 已预同步（$(du -sh "$APP_BASE/uploads" 2>/dev/null | cut -f1)）"
fi

# ======================================================================
step "2/7 停止写入并导出数据库"
# ======================================================================
port_8080_busy() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -qE '[:.]8080[[:space:]]'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -qE '[:.]8080[[:space:]]'
  else
    return 1
  fi
}
if [ "$STOP_API" = "1" ]; then
  if systemctl is-active --quiet shinepick-api 2>/dev/null; then
    # 先置位：即使 stop 命令返回异常，退出时也会尝试拉起
    STOPPED_API=1
    systemctl stop shinepick-api
    ok "shinepick-api 已停止"
  elif port_8080_busy; then
    die "8080 正在监听，但 shinepick-api 不是 systemd 服务；请手动停止后加 --no-stop 重跑"
  else
    warn "shinepick-api 未在运行，跳过停止"
  fi
else
  warn "--no-stop：数据库导出期间可能有写入，快照不保证严格一致"
fi

DB_DUMP="$BUNDLE/db/database.sql.gz"
dump_opts=(--single-transaction --quick --routines --triggers --events
           --default-character-set=utf8mb4)
if "$DUMP_BIN" --help 2>/dev/null | grep -q -- '--no-tablespaces'; then
  dump_opts+=(--no-tablespaces)
fi
if [ "$DB_FLAVOR" = "MySQL" ] && "$DUMP_BIN" --help 2>/dev/null | grep -q -- '--set-gtid-purged'; then
  dump_opts+=(--set-gtid-purged=OFF)
fi

printf '  导出中: %s ...\n' "$DB_NAME"
if [ "$USE_SOCKET" = "1" ]; then
  "$DUMP_BIN" -u root "${dump_opts[@]}" "$DB_NAME" | gzip -1 > "$DB_DUMP"
else
  MYSQL_PWD="$DB_PASS" "$DUMP_BIN" --protocol=tcp -h "$DB_HOST" -P "$DB_PORT" \
    -u "$DB_USER" "${dump_opts[@]}" "$DB_NAME" | gzip -1 > "$DB_DUMP"
fi
gzip -t "$DB_DUMP" || die "数据库备份文件损坏"
[ "$(stat -c%s "$DB_DUMP")" -gt 100 ] || die "数据库备份文件异常（过小）"
zgrep -q 'Dump completed' "$DB_DUMP" || warn "备份文件中未找到 Dump completed 标记"
ok "数据库已导出: $(du -h "$DB_DUMP" | cut -f1)"

# ---- 表清单 / 行数（恢复后核对）----
mysql_q -N -B -e \
  "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME" \
  > "$BUNDLE/db/tables.txt"
: > "$BUNDLE/db/rowcounts.tsv"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  c="$(mysql_q -N -e "SELECT COUNT(*) FROM \`$DB_NAME\`.\`$t\`")"
  printf '%s\t%s\n' "$t" "$c" >> "$BUNDLE/db/rowcounts.tsv"
done < "$BUNDLE/db/tables.txt"
ok "已记录 $(wc -l < "$BUNDLE/db/tables.txt") 张表的行数"

{
  printf 'flavor: %s\nversion: %s\n' "$DB_FLAVOR" "$MYSQL_VERSION"
  mysql_q -N -e "SELECT @@sql_mode, @@character_set_server, @@collation_server, @@time_zone, @@system_time_zone" || true
} > "$BUNDLE/db/info.txt"
mysql_q -N -e "SHOW CREATE DATABASE \`$DB_NAME\`" > "$BUNDLE/db/database-create.sql" 2>/dev/null || true

user_sql="$(printf '%s' "$DB_USER" | sed "s/'/''/g")"
for h in localhost 127.0.0.1 '%'; do
  mysql_q -N -e "SHOW GRANTS FOR '${user_sql}'@'${h}'" 2>/dev/null || true
done > "$BUNDLE/db/grants.txt"

# ======================================================================
step "3/7 同步 uploads 并恢复服务"
# ======================================================================
sync_uploads() {
  local dest="$BUNDLE/files${APP_BASE}/uploads"
  mkdir -p "$dest"
  [ "$HAS_UPLOADS" = "1" ] || return 0
  if command -v rsync >/dev/null 2>&1; then
    if rsync -aHAX --numeric-ids --delete "$APP_BASE/uploads/" "$dest/"; then
      return 0
    fi
    warn "rsync 同步失败，改用 tar 全量复制"
  fi
  copy_tree "${APP_BASE#/}/uploads"
}
sync_uploads
if [ "$HAS_UPLOADS" = "1" ]; then
  ok "uploads 已同步: $(du -sh "$APP_BASE/uploads" 2>/dev/null | cut -f1)"
fi

if [ "$STOPPED_API" = "1" ]; then
  systemctl start shinepick-api
  STOPPED_API=0
  sleep 2
  if ! command -v curl >/dev/null 2>&1; then
    warn "shinepick-api 已启动；未安装 curl，跳过健康检查"
  elif curl -fsS -m 5 http://127.0.0.1:8080/ping 2>/dev/null | grep -q '"pong":true'; then
    ok "shinepick-api 已恢复运行"
  else
    warn "shinepick-api 已启动，但健康检查未通过；请查看 journalctl -u shinepick-api -n 50"
  fi
fi

# ======================================================================
step "4/7 收集系统配置"
# ======================================================================
mkdir -p "$BUNDLE/files/etc/systemd/system"
for u in shinepick-api.service apkserver.service; do
  for d in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
    if [ -f "$d/$u" ]; then
      install -D -m 0644 "$d/$u" "$BUNDLE/files/etc/systemd/system/$u"
      break
    fi
  done
done
for d in /etc/systemd/system/shinepick-api.service.d /etc/systemd/system/apkserver.service.d; do
  if [ -d "$d" ]; then
    cp -a "$d" "$BUNDLE/files/etc/systemd/system/"
  fi
done
ok "已收集 systemd 单元"

if [ -f /usr/local/bin/shinepick ]; then
  install -D -m 0755 /usr/local/bin/shinepick "$BUNDLE/files/usr/local/bin/shinepick"
  ok "已收集管理脚本 /usr/local/bin/shinepick"
fi

NGINX_INCLUDED=0
if [ "$WITH_NGINX" = "1" ] && [ -d /etc/nginx ]; then
  tar -C / --numeric-owner -cf - etc/nginx | tar -C "$BUNDLE/files" -xf -
  NGINX_INCLUDED=1
  if command -v nginx >/dev/null 2>&1; then
    nginx -T > "$BUNDLE/nginx/nginx-T.conf" 2>&1 || true
  fi
  ok "已收集 /etc/nginx"
fi

CERTS_INCLUDED=0
if [ "$WITH_CERTS" = "1" ]; then
  for p in etc/letsencrypt root/.acme.sh; do
    if [ -d "/$p" ]; then
      tar -C / --numeric-owner -cf - "$p" | tar -C "$BUNDLE/files" -xf -
      CERTS_INCLUDED=1
      ok "已收集 /$p"
    fi
  done
fi

crontab -l > "$BUNDLE/config/root.crontab" 2>/dev/null || true
if [ ! -s "$BUNDLE/config/root.crontab" ]; then
  rm -f "$BUNDLE/config/root.crontab"
fi
if [ -d /etc/cron.d ]; then
  cp -a /etc/cron.d "$BUNDLE/config/"
fi
if [ -f /etc/crontab ]; then
  cp -a /etc/crontab "$BUNDLE/config/"
fi

if [ "$WITH_REDIS" = "1" ]; then
  if [ -d /var/lib/redis ]; then
    copy_tree var/lib/redis
    ok "已收集 /var/lib/redis"
  fi
  if command -v redis-cli >/dev/null 2>&1; then
    redis-cli INFO > "$BUNDLE/inventory/redis-info.txt" 2>/dev/null || true
  fi
fi

# ---- 主机清单（用于新机对照，不自动应用）----
{
  printf 'hostname=%s\n' "$(hostname)"
  printf 'backup_time=%s\n' "$(date -Is)"
  printf 'uname=%s\n' "$(uname -a)"
  printf 'arch=%s\n' "$HOST_ARCH"
  cat /etc/os-release 2>/dev/null || true
} > "$BUNDLE/inventory/host.txt"

if command -v dpkg >/dev/null 2>&1; then
  dpkg -l 2>/dev/null | awk '/mysql|maria|redis|nginx/{print}' > "$BUNDLE/inventory/packages.txt" || true
elif command -v rpm >/dev/null 2>&1; then
  rpm -qa 2>/dev/null | grep -Ei 'mysql|maria|redis|nginx' > "$BUNDLE/inventory/packages.txt" || true
fi

if command -v ss >/dev/null 2>&1; then
  ss -tlnp > "$BUNDLE/inventory/ports.txt" 2>&1 || true
else
  netstat -tlnp > "$BUNDLE/inventory/ports.txt" 2>&1 || true
fi
systemctl list-units --type=service --state=running --no-pager \
  > "$BUNDLE/inventory/services.txt" 2>&1 || true
systemctl list-unit-files --state=enabled --no-pager \
  > "$BUNDLE/inventory/enabled-units.txt" 2>&1 || true
timedatectl > "$BUNDLE/inventory/timedatectl.txt" 2>&1 || true
{
  ip addr 2>/dev/null || true
  echo '--- route ---'
  ip route 2>/dev/null || true
} > "$BUNDLE/inventory/network.txt"
cat /etc/hosts > "$BUNDLE/inventory/hosts" 2>/dev/null || true
cat /etc/resolv.conf > "$BUNDLE/inventory/resolv.conf" 2>/dev/null || true

{
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --list-all 2>&1 || true
  fi
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose 2>&1 || true
  fi
  if command -v nft >/dev/null 2>&1; then
    nft list ruleset 2>&1 | head -200 || true
  fi
  if command -v iptables-save >/dev/null 2>&1; then
    iptables-save 2>&1 | head -200 || true
  fi
} > "$BUNDLE/inventory/firewall.txt"

if command -v docker >/dev/null 2>&1; then
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' \
    > "$BUNDLE/inventory/docker.txt" 2>&1 || true
fi

# ======================================================================
step "5/7 生成清单与说明"
# ======================================================================
APK_BINARY_ARCH="unknown"
if [ "$APK_INCLUDED" = "1" ]; then
  APK_BINARY_ARCH="$(read_elf_arch "$APK_BASE/apkserver")"
fi

cat > "$BUNDLE/MANIFEST" <<EOF
FORMAT=1
CREATED=$(date -Is)
SOURCE_HOST=$(hostname)
SOURCE_IP=$SOURCE_IP
SOURCE_PUBLIC_BASE_URL=$PUBLIC_BASE_URL
APP_NAME=$APP_NAME
APP_BASE=$APP_BASE
APK_BASE=$APK_BASE
APP_USER=shinepick
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_DUMP=db/database.sql.gz
DB_FLAVOR=$DB_FLAVOR
MYSQL_VERSION=$MYSQL_VERSION
HOST_ARCH=$HOST_ARCH
BINARY_ARCH=$BINARY_ARCH
APK_INCLUDED=$APK_INCLUDED
APK_BINARY_ARCH=$APK_BINARY_ARCH
NGINX_INCLUDED=$NGINX_INCLUDED
CERTS_INCLUDED=$CERTS_INCLUDED
REDIS_INCLUDED=$WITH_REDIS
UPLOADS_KB=$uploads_kb
RESTORE_SCRIPT=restore-new.sh
EOF

cat > "$BUNDLE/README.txt" <<'EOF'
拾光 ShinePick 迁移包
=====================

【警告】本包含有数据库密码、JWT_SECRET、ADMIN_TOKEN 和 Let's Encrypt 私钥，
权限已设为 600，请勿放到 Web 目录或公共网盘；恢复完成后及时删除。

新服务器恢复（先解压，再执行包内的脚本）:

  tar -xzf shinepick-migrate-*.tar.gz
  cd shinepick-migrate-*/
  sudo ./restore-new.sh --public-url http://8.134.144.35:8080 --install-deps

（若包名是 .tar.zst，改用 tar --zstd -xf shinepick-migrate-*.tar.zst）

如果新机已自行安装 MySQL 8.0 / Redis / Nginx，可去掉 --install-deps。
恢复脚本会校验 SHA256SUMS、导入数据库、恢复 /opt 与 systemd，并把
旧地址 http://129.226.159.168:8080 的图片链接改写为 --public-url。

迁移后仍需手工确认:
  1. 云控制台安全组放行 8080（以及 apkserver 的 8082），如需域名再加 80/443
  2. DNS 指向新机；Let's Encrypt 证书执行 certbot renew --dry-run
  3. 旧机保留 3-7 天，确认无误后再释放
  4. 已安装 APK 内置旧 API 地址，需重新打包，或在旧机保留 8080 转发
EOF

if [ -f "$SCRIPT_DIR/restore-new.sh" ]; then
  install -m 0755 "$SCRIPT_DIR/restore-new.sh" "$BUNDLE/restore-new.sh"
else
  warn "未找到同目录的 restore-new.sh，迁移包内将不含恢复脚本"
fi

# ======================================================================
step "6/7 生成校验值并打包"
# ======================================================================
(
  cd "$BUNDLE"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
chmod 600 "$BUNDLE/SHA256SUMS"
ok "SHA256SUMS 已生成（$(wc -l < "$BUNDLE/SHA256SUMS") 个文件）"

printf '  压缩中（%s）...\n' "$COMPRESS"
case "$COMPRESS" in
  zstd)
    tar -C "$OUT_ROOT" --numeric-owner -cf - "$BUNDLE_NAME" | zstd -q -T0 -3 -o "$ARCHIVE"
    zstd -t "$ARCHIVE" >/dev/null 2>&1 || die "压缩包校验失败"
    ;;
  *)
    tar -C "$OUT_ROOT" --numeric-owner -cf - "$BUNDLE_NAME" | gzip -1 > "$ARCHIVE"
    gzip -t "$ARCHIVE" || die "压缩包校验失败"
    ;;
esac
chmod 600 "$ARCHIVE"
(
  cd "$OUT_ROOT"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)
chmod 600 "$ARCHIVE.sha256"
DB_DUMP_SIZE="$(du -h "$DB_DUMP" | cut -f1)"
ok "压缩包: $ARCHIVE（$(du -h "$ARCHIVE" | cut -f1)）"

if [ "$PUSH_TARGET" != "" ]; then
  step "推送迁移包到新服务器"
  if [[ "$PUSH_TARGET" == *:* ]]; then
    PUSH_HOST="${PUSH_TARGET%%:*}"
    PUSH_PATH="${PUSH_TARGET#*:}"
  else
    PUSH_HOST="$PUSH_TARGET"
    PUSH_PATH="/root"
  fi
  [ -n "$PUSH_HOST" ] || die "推送目标为空"
  [ -n "$PUSH_PATH" ] || PUSH_PATH="/root"
  ssh "$PUSH_HOST" "mkdir -p '$PUSH_PATH'" || die "SSH 到 $PUSH_HOST 失败（请先配置免密登录）"
  if command -v rsync >/dev/null 2>&1; then
    rsync -avP --partial "$ARCHIVE" "$ARCHIVE.sha256" "$PUSH_HOST:$PUSH_PATH/" || die "rsync 推送失败"
  else
    scp "$ARCHIVE" "$ARCHIVE.sha256" "$PUSH_HOST:$PUSH_PATH/" || die "scp 推送失败"
  fi
  ssh "$PUSH_HOST" "cd '$PUSH_PATH' && sha256sum -c '$(basename "$ARCHIVE").sha256'" \
    || die "远端校验失败"
  ok "已推送到 $PUSH_HOST:$PUSH_PATH"
fi

if [ "$KEEP_BUNDLE" = "1" ]; then
  ok "保留解包目录: $BUNDLE"
else
  rm -rf "$BUNDLE"
fi

# ======================================================================
step "7/7 完成"
# ======================================================================
cat <<EOF

迁移包 : $ARCHIVE（$(du -h "$ARCHIVE" | cut -f1)）
校验值 : $ARCHIVE.sha256
数据库 : $DB_NAME（$DB_FLAVOR $MYSQL_VERSION，$DB_DUMP_SIZE）
上传目录: $(awk -v k="$uploads_kb" 'BEGIN{printf "%.1f MB", k/1024}')

新服务器上执行:
EOF
if [ "$COMPRESS" = "zstd" ]; then
  cat <<EOF
  tar --zstd -xf $(basename "$ARCHIVE")
  cd ${BUNDLE_NAME}
  sudo ./restore-new.sh --public-url http://8.134.144.35:8080
EOF
else
  cat <<EOF
  tar -xzf $(basename "$ARCHIVE")
  cd ${BUNDLE_NAME}
  sudo ./restore-new.sh --public-url http://8.134.144.35:8080
EOF
fi
if [ "$PUSH_TARGET" != "" ]; then
  printf '  （包已推送到 %s，可直接登录新机解压）\n' "$PUSH_HOST:$PUSH_PATH"
fi
cat <<'EOF'

提醒:
  - 迁移包含密钥，权限 600；恢复验证后请删除。
  - 新云安全组需放行 8080、8082（apkserver），域名再加 80/443。
  - 正式切换前可再跑一次本脚本，缩短新旧数据差距。
EOF
