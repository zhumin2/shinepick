#!/usr/bin/env bash
# 拾光 ShinePick · 新服务器恢复
# 在【新服务器 8.134.144.35】以 root 运行，读取 backup-old.sh 产出的迁移包。
#
#   tar -xzf shinepick-migrate-*.tar.gz
#   cd shinepick-migrate-*/
#   sudo ./restore-new.sh --public-url http://8.134.144.35:8080 --install-deps
#
# 做四件事:
#   1. 校验并恢复 /opt/shinepick（含 uploads）、systemd、Nginx、证书、apkserver
#   2. 建库建账号并导入 MySQL 备份
#   3. 改写 shinepick.env（数据库 DSN / PUBLIC_BASE_URL / UPLOAD_DIR）
#   4. 把数据库中指向旧 IP 的图片/视频 URL 改写为新地址
#
# 破坏性操作只发生在显式传入 --force 时（覆盖已有目录 / 删除重建数据库）。
set -Eeuo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
KNOWN_OLD_IP="129.226.159.168"
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-}"
PUBLIC_BASE_URL=""
NEW_IP=""
DB_USER_OPT=""
DB_PASS_OPT=""
FORCE=0
INSTALL_DEPS=0
SKIP_NGINX=0
SKIP_CERTS=0
SKIP_APK=0
WITH_CRON=0
IGNORE_ARCH=0
KEEP_EXTRACT=0
EXTRACT_DIR=""
SUCCESS=0

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
用法: sudo ./restore-new.sh <迁移包.tar.gz|解包目录> [选项]

选项:
  --public-url URL    新对外地址，如 http://8.134.144.35:8080
                      会写入 PUBLIC_BASE_URL，并改写数据库里的旧图片 URL
  --new-ip IP         只给新机 IP，自动拼成 http://IP:8080
  --db-user USER      应用数据库账号（默认沿用旧账号；旧账号是 root 时改为 shinepick）
  --db-pass PASS      应用数据库密码（默认沿用旧密码；为空则随机生成）
  --mysql-root-pass P MySQL root 密码（默认走 socket / ~/.my.cnf）
  --install-deps      缺少 MySQL/Redis/Nginx 时用 apt/dnf 安装
  --force             覆盖已有 /opt 目录、删除并重建同名数据库
  --skip-nginx        不恢复 /etc/nginx
  --skip-certs        不恢复 /etc/letsencrypt、/root/.acme.sh
  --skip-apk          不恢复 /opt/apkserver
  --with-cron         恢复全部 cron 文件与 root crontab（默认只恢复含 shinepick/apk/backup 的）
  --ignore-arch       忽略新旧服务器 CPU 架构不一致
  --keep-extract      恢复成功后保留解包目录（默认删除）
  -h, --help          显示帮助
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
[ $# -ge 1 ] || { usage; exit 1; }
BUNDLE_ARG="$1"; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --public-url)
      [ $# -ge 2 ] || die "$1 需要 URL"
      PUBLIC_BASE_URL="$2"; shift 2 ;;
    --new-ip)
      [ $# -ge 2 ] || die "$1 需要 IP"
      NEW_IP="$2"
      if [[ "$NEW_IP" == *:* ]]; then
        die "--new-ip 只填 IP，不要带端口；完整地址请用 --public-url"
      fi
      shift 2 ;;
    --db-user)
      [ $# -ge 2 ] || die "$1 需要用户名"
      DB_USER_OPT="$2"; shift 2 ;;
    --db-pass)
      [ $# -ge 2 ] || die "$1 需要密码"
      DB_PASS_OPT="$2"; shift 2 ;;
    --mysql-root-pass)
      [ $# -ge 2 ] || die "$1 需要密码"
      MYSQL_ROOT_PASS="$2"; shift 2 ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --force)        FORCE=1; shift ;;
    --skip-nginx)   SKIP_NGINX=1; shift ;;
    --skip-certs)   SKIP_CERTS=1; shift ;;
    --skip-apk)     SKIP_APK=1; shift ;;
    --with-cron)    WITH_CRON=1; shift ;;
    --ignore-arch)  IGNORE_ARCH=1; shift ;;
    --keep-extract) KEEP_EXTRACT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（-h 查看用法）" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "请用 root 运行: sudo $0"

if [ -z "$PUBLIC_BASE_URL" ] && [ -n "$NEW_IP" ]; then
  PUBLIC_BASE_URL="http://$NEW_IP:8080"
fi
if [ -n "$PUBLIC_BASE_URL" ]; then
  PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
  case "$PUBLIC_BASE_URL" in
    http://*|https://*) ;;
    *) die "--public-url 必须以 http:// 或 https:// 开头" ;;
  esac
  NEW_IP="${PUBLIC_BASE_URL#*://}"
  NEW_IP="${NEW_IP%%[:/]*}"
fi

cleanup() {
  local rc=$?
  if [ "$SUCCESS" = "1" ] && [ "$KEEP_EXTRACT" != "1" ] && [ -n "$EXTRACT_DIR" ]; then
    rm -rf "$EXTRACT_DIR" || true
  fi
  exit "$rc"
}
trap cleanup EXIT

# ======================================================================
step "1/9 解包并校验"
# ======================================================================
if [ -d "$BUNDLE_ARG" ]; then
  BUNDLE="$(cd "$BUNDLE_ARG" && pwd)"
else
  [ -f "$BUNDLE_ARG" ] || die "找不到迁移包: $BUNDLE_ARG"
  if [ -f "$BUNDLE_ARG.sha256" ]; then
    ( cd "$(dirname "$BUNDLE_ARG")" && sha256sum -c "$(basename "$BUNDLE_ARG").sha256" ) \
      || die "迁移包 SHA256 校验失败"
    ok "整包 SHA256 校验通过"
  else
    warn "未找到 $BUNDLE_ARG.sha256，跳过整包校验"
  fi

  EXTRACT_DIR="/root/shinepick-restore-$STAMP"
  mkdir -p "$EXTRACT_DIR"
  case "$BUNDLE_ARG" in
    *.tar.gz|*.tgz)
      tar -xzf "$BUNDLE_ARG" -C "$EXTRACT_DIR" ;;
    *.tar.zst)
      command -v zstd >/dev/null 2>&1 || die "解压 .tar.zst 需要 zstd"
      zstd -dc "$BUNDLE_ARG" | tar -C "$EXTRACT_DIR" -xf - ;;
    *)
      die "不支持的包格式: $BUNDLE_ARG" ;;
  esac
  MANIFEST_PATH="$(find "$EXTRACT_DIR" -maxdepth 4 -type f -name MANIFEST -print -quit)"
  [ -n "$MANIFEST_PATH" ] || die "包内找不到 MANIFEST"
  BUNDLE="$(dirname "$MANIFEST_PATH")"
fi

[ -f "$BUNDLE/MANIFEST" ] || die "找不到 $BUNDLE/MANIFEST"
[ -f "$BUNDLE/SHA256SUMS" ] || die "找不到 $BUNDLE/SHA256SUMS"
( cd "$BUNDLE" && sha256sum --quiet -c SHA256SUMS ) || die "包内文件校验失败"
ok "包内文件校验通过（$BUNDLE）"

m() { sed -n "s/^$1=//p" "$BUNDLE/MANIFEST" | head -1; }

[ "$(m FORMAT)" = "1" ] || die "不支持的迁移包格式"
APP_BASE="$(m APP_BASE)"; APP_BASE="${APP_BASE:-/opt/shinepick}"
APK_BASE="$(m APK_BASE)"; APK_BASE="${APK_BASE:-/opt/apkserver}"
APP_USER="$(m APP_USER)"; APP_USER="${APP_USER:-shinepick}"
DB_NAME="$(m DB_NAME)"
DB_DUMP="$(m DB_DUMP)"; DB_DUMP="${DB_DUMP:-db/database.sql.gz}"
DB_FLAVOR="$(m DB_FLAVOR)"
OLD_MYSQL_VERSION="$(m MYSQL_VERSION)"
SOURCE_IP="$(m SOURCE_IP)"
SOURCE_PUBLIC_BASE_URL="$(m SOURCE_PUBLIC_BASE_URL)"
BINARY_ARCH="$(m BINARY_ARCH)"
APK_INCLUDED="$(m APK_INCLUDED)"; APK_INCLUDED="${APK_INCLUDED:-0}"
NGINX_INCLUDED="$(m NGINX_INCLUDED)"; NGINX_INCLUDED="${NGINX_INCLUDED:-0}"
CERTS_INCLUDED="$(m CERTS_INCLUDED)"; CERTS_INCLUDED="${CERTS_INCLUDED:-0}"
REDIS_INCLUDED="$(m REDIS_INCLUDED)"; REDIS_INCLUDED="${REDIS_INCLUDED:-0}"

case "$APP_BASE" in
  /?*) ;;
  *) die "MANIFEST 中 APP_BASE 非法: $APP_BASE" ;;
esac
[ "$APP_BASE" != "/" ] || die "APP_BASE 不能为 /"
path_ok() {
  local p="$1"
  [[ "$p" == *".."* ]] && return 1
  [[ "$p" =~ ^/[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+$ ]] || return 1
  case "$p" in
    /opt/*|/srv/*|/data/*|/home/*|/var/www/*) return 0 ;;
    *) return 1 ;;
  esac
}
path_ok "$APP_BASE" || die "APP_BASE 不在允许的部署根目录（/opt、/srv、/data、/home、/var/www）: $APP_BASE"
path_ok "$APK_BASE" || die "APK_BASE 不在允许的部署根目录（/opt、/srv、/data、/home、/var/www）: $APK_BASE"
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || die "MANIFEST 中数据库名非法: $DB_NAME"
[ -d "$BUNDLE/files$APP_BASE" ] || die "包内缺少程序目录 files$APP_BASE"
[ -f "$BUNDLE/$DB_DUMP" ] || die "包内缺少数据库备份 $DB_DUMP"

# ======================================================================
step "2/9 环境检查"
# ======================================================================
for c in tar gzip sha256sum awk sed grep find df; do
  command -v "$c" >/dev/null 2>&1 || die "缺少命令: $c"
done

NEW_ARCH="$(uname -m)"
if [ "$BINARY_ARCH" != "unknown" ] && [ "$BINARY_ARCH" != "$NEW_ARCH" ] && [ "$IGNORE_ARCH" != "1" ]; then
  die "旧机二进制架构 $BINARY_ARCH 与新机 $NEW_ARCH 不一致；请在开发机交叉编译后替换包内文件，或加 --ignore-arch"
fi
APK_BINARY_ARCH="$(m APK_BINARY_ARCH)"
if [ "$APK_INCLUDED" = "1" ] && [ "$APK_BINARY_ARCH" != "unknown" ] \
   && [ "$APK_BINARY_ARCH" != "$NEW_ARCH" ]; then
  warn "apkserver 二进制架构为 $APK_BINARY_ARCH，与新机 $NEW_ARCH 不一致，启动会失败；请重新交叉编译"
fi
ok "架构 $NEW_ARCH"

need_kb="$(m UPLOADS_KB)"
need_kb="${need_kb:-0}"
need_kb=$(( need_kb + need_kb / 5 + 1024 * 1024 ))
free_kb="$(df -Pk "$(dirname "$APP_BASE")" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
free_kb="${free_kb:-0}"
if [ "$free_kb" -lt "$need_kb" ]; then
  die "磁盘空间不足: 需要约 $((need_kb/1024)) MB，$(dirname "$APP_BASE") 仅剩 $((free_kb/1024)) MB"
fi

if [ -e "$APP_BASE" ] && [ "$FORCE" != "1" ]; then
  die "$APP_BASE 已存在；确认覆盖请加 --force（会先改名备份）"
fi

# ======================================================================
step "3/9 安装依赖并启动 MySQL / Redis"
# ======================================================================
if ! command -v mysql >/dev/null 2>&1 && ! command -v mariadb >/dev/null 2>&1; then
  if [ "$INSTALL_DEPS" != "1" ]; then
    die "未安装 MySQL 客户端；请安装后重跑，或加 --install-deps"
  fi
fi

install_deps() {
  step "安装系统依赖（apt / dnf / yum）"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server redis-server nginx curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y mysql-server || dnf install -y mariadb-server
    dnf install -y redis nginx curl || warn "Redis/Nginx 安装失败，请手工处理"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y mysql-server || yum install -y mariadb-server
    yum install -y redis nginx curl || warn "Redis/Nginx 安装失败，请手工处理"
  else
    die "未找到 apt-get / dnf / yum，请手工安装依赖"
  fi
}

if [ "$INSTALL_DEPS" = "1" ]; then
  install_deps
fi
command -v curl >/dev/null 2>&1 || die "缺少 curl，无法验证 API；请安装 curl 后重跑，或加 --install-deps"

if command -v mysql >/dev/null 2>&1; then
  MYSQL_BIN="$(command -v mysql)"
elif command -v mariadb >/dev/null 2>&1; then
  MYSQL_BIN="$(command -v mariadb)"
else
  die "未安装 MySQL 客户端"
fi

detect_unit() {
  local s
  for s in "$@"; do
    if systemctl cat "$s.service" >/dev/null 2>&1; then
      printf '%s' "$s"
      return 0
    fi
  done
  return 1
}
MYSQL_SVC="$(detect_unit mysql mysqld mariadb || true)"
[ -n "$MYSQL_SVC" ] || die "未找到 MySQL systemd 服务（mysql/mysqld/mariadb）"
REDIS_SVC="$(detect_unit redis-server redis || true)"
ok "MySQL 服务: $MYSQL_SVC；Redis 服务: ${REDIS_SVC:-未找到}"

systemctl enable --now "$MYSQL_SVC" >/dev/null 2>&1 || true
if [ -n "$REDIS_SVC" ]; then
  systemctl enable --now "$REDIS_SVC" >/dev/null 2>&1 || warn "Redis 启动失败"
else
  warn "未找到 Redis 服务，API 可能无法启动"
fi

mysql_root() {
  if [ -n "$MYSQL_ROOT_PASS" ]; then
    MYSQL_PWD="$MYSQL_ROOT_PASS" "$MYSQL_BIN" -u root "$@"
  else
    "$MYSQL_BIN" -u root "$@"
  fi
}

ready=0
for _ in $(seq 1 60); do
  if mysql_root -e 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" != "1" ]; then
  warn "RHEL 系首次安装的 MySQL root 临时密码通常在 /var/log/mysqld.log"
  die "MySQL 60 秒内未就绪，或 root 认证失败；请用 --mysql-root-pass 重跑"
fi
NEW_MYSQL_VERSION="$(mysql_root -N -e 'SELECT VERSION()' | head -1)"
NEW_FLAVOR="MySQL"
if [[ "$NEW_MYSQL_VERSION" == *MariaDB* ]]; then
  NEW_FLAVOR="MariaDB"
fi
ok "MySQL 就绪: $NEW_FLAVOR $NEW_MYSQL_VERSION（旧库: $DB_FLAVOR $OLD_MYSQL_VERSION）"

if [ "$DB_FLAVOR" = "MySQL" ] && [ "$NEW_FLAVOR" = "MariaDB" ]; then
  if zgrep -q 'utf8mb4_0900' "$BUNDLE/$DB_DUMP"; then
    die "旧库使用了 MySQL 8 的 utf8mb4_0900 排序规则，MariaDB 不兼容；请安装 MySQL 8.0 后重跑"
  fi
  warn "旧库是 MySQL、新库是 MariaDB，可能存在兼容差异（本包未发现 0900 排序规则）"
fi

if [ "$REDIS_INCLUDED" = "1" ] && [ -d "$BUNDLE/files/var/lib/redis" ]; then
  if [ -n "$REDIS_SVC" ]; then
    systemctl stop "$REDIS_SVC" 2>/dev/null || true
  fi
  if [ -d /var/lib/redis ]; then
    mv /var/lib/redis "/var/lib/redis.bak-$STAMP"
  fi
  cp -a "$BUNDLE/files/var/lib/redis" /var/lib/redis
  if id -u redis >/dev/null 2>&1; then
    chown -R redis:redis /var/lib/redis 2>/dev/null || true
  else
    warn "未找到 redis 用户，请手工调整 /var/lib/redis 属主"
  fi
  if [ -n "$REDIS_SVC" ]; then
    systemctl start "$REDIS_SVC" 2>/dev/null || warn "Redis 恢复数据后启动失败"
  fi
  ok "已恢复 /var/lib/redis"
fi

# ======================================================================
step "4/9 恢复程序文件"
# ======================================================================
# 重跑/覆盖时先停掉旧进程，避免边写 uploads 边替换目录
systemctl stop shinepick-api 2>/dev/null || true
systemctl stop apkserver 2>/dev/null || true

if ! id -u "$APP_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_BASE" --shell /usr/sbin/nologin "$APP_USER"
  ok "已创建系统用户 $APP_USER"
fi

if [ -e "$APP_BASE" ]; then
  mv "$APP_BASE" "$APP_BASE.bak-$STAMP"
  warn "原目录已改名备份: $APP_BASE.bak-$STAMP"
fi
mkdir -p "$(dirname "$APP_BASE")"
cp -a "$BUNDLE/files$APP_BASE" "$APP_BASE"
APP_GROUP="$(id -gn "$APP_USER" 2>/dev/null || echo "$APP_USER")"
chown -R "$APP_USER:$APP_GROUP" "$APP_BASE" 2>/dev/null || chown -R "$APP_USER" "$APP_BASE" 2>/dev/null || true
if [ -f "$APP_BASE/shinepick-api" ]; then
  chmod 0755 "$APP_BASE/shinepick-api"
fi
[ -f "$APP_BASE/shinepick.env" ] && chmod 0600 "$APP_BASE/shinepick.env"
[ -f "$APP_BASE/shinepick-api" ] || die "包内缺少 $APP_BASE/shinepick-api 可执行文件"
ok "已恢复 $APP_BASE"

if [ "$SKIP_APK" != "1" ] && [ "$APK_INCLUDED" = "1" ] && [ -d "$BUNDLE/files$APK_BASE" ]; then
  if [ -e "$APK_BASE" ]; then
    mv "$APK_BASE" "$APK_BASE.bak-$STAMP"
    warn "原目录已改名备份: $APK_BASE.bak-$STAMP"
  fi
  mkdir -p "$(dirname "$APK_BASE")"
  cp -a "$BUNDLE/files$APK_BASE" "$APK_BASE"
  [ -f "$APK_BASE/apkserver" ] && chmod 0755 "$APK_BASE/apkserver"
  ok "已恢复 $APK_BASE"
fi

if [ -f "$BUNDLE/files/usr/local/bin/shinepick" ]; then
  install -D -m 0755 "$BUNDLE/files/usr/local/bin/shinepick" /usr/local/bin/shinepick
  ok "已恢复管理脚本 /usr/local/bin/shinepick"
fi

# ======================================================================
step "5/9 建库、建账号并导入"
# ======================================================================
ENVF="$APP_BASE/shinepick.env"
[ -f "$ENVF" ] || die "找不到 $ENVF"

OLD_DSN="$(grep -E '^DB_DSN=' "$ENVF" | tail -1 | cut -d= -f2- || true)"
OLD_DSN="${OLD_DSN%\"}"; OLD_DSN="${OLD_DSN#\"}"
OLD_DSN="${OLD_DSN%\'}"; OLD_DSN="${OLD_DSN#\'}"
if [[ "$OLD_DSN" != *"@tcp("* ]]; then
  die "shinepick.env 中 DB_DSN 无法解析: $OLD_DSN"
fi
creds="${OLD_DSN%%@tcp(*}"
OLD_USER="${creds%%:*}"
if [[ "$creds" == *:* ]]; then
  OLD_PASS="${creds#*:}"
else
  OLD_PASS=""
fi

NEW_USER="${DB_USER_OPT:-$OLD_USER}"
if [ -z "$NEW_USER" ] || [ "$NEW_USER" = "root" ]; then
  NEW_USER="shinepick"
fi
[[ "$NEW_USER" =~ ^[A-Za-z0-9_.-]+$ ]] || die "数据库用户名非法: $NEW_USER"

NEW_PASS="${DB_PASS_OPT:-$OLD_PASS}"
if [ -z "$NEW_PASS" ]; then
  NEW_PASS="$(openssl rand -hex 16 2>/dev/null || true)"
  if [ -z "$NEW_PASS" ]; then
    NEW_PASS="$(date +%s%N | sha256sum | cut -c1-32)"
  fi
  warn "旧 DSN 没有密码，已生成新密码（保存在 shinepick.env，权限 600）"
fi
if [[ "$NEW_PASS" == *"@tcp("* ]]; then
  die "数据库密码包含 @tcp(，会破坏 DSN，请用 --db-pass 指定其他密码"
fi
if [[ "$NEW_PASS" == *[[:space:]#]* ]]; then
  warn "数据库密码含空白或 #，systemd EnvironmentFile 可能截断；建议用 --db-pass 指定无空格密码"
fi

sql_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\'\'}"
  printf '%s' "$s"
}

EXISTING_TABLES="$(mysql_root -N -B -e \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$(sql_escape "$DB_NAME")'")"
if [ "$EXISTING_TABLES" -gt 0 ]; then
  if [ "$FORCE" = "1" ]; then
    warn "--force：删除并重建数据库 $DB_NAME（$EXISTING_TABLES 个表/视图）"
    mysql_root -e "DROP DATABASE \`$DB_NAME\`"
  else
    die "数据库 $DB_NAME 已有 $EXISTING_TABLES 个表/视图；确认覆盖请加 --force"
  fi
fi
mysql_root -e \
  "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

U="$(sql_escape "$NEW_USER")"
P="$(sql_escape "$NEW_PASS")"
mysql_root <<SQL
CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$P';
ALTER USER '$U'@'localhost' IDENTIFIED BY '$P';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$U'@'localhost';
CREATE USER IF NOT EXISTS '$U'@'127.0.0.1' IDENTIFIED BY '$P';
ALTER USER '$U'@'127.0.0.1' IDENTIFIED BY '$P';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$U'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
ok "数据库账号 $NEW_USER 已就绪（localhost + 127.0.0.1）"

printf '  导入中: %s ...\n' "$DB_DUMP"
if ! gzip -dc "$BUNDLE/$DB_DUMP" | mysql_root --default-character-set=utf8mb4 "$DB_NAME"; then
  die "数据库导入失败（可用 --force 重跑，或手工检查 $BUNDLE/$DB_DUMP）"
fi
ok "数据库导入完成"

if [ -f "$BUNDLE/db/rowcounts.tsv" ]; then
  mismatch=0
  while IFS=$'\t' read -r t expected; do
    [ -n "$t" ] || continue
    actual="$(mysql_root -N -B -e "SELECT COUNT(*) FROM \`$DB_NAME\`.\`$t\`" 2>/dev/null || echo "ERR")"
    if [ "$actual" != "$expected" ]; then
      warn "行数不一致 $t: 旧 $expected / 新 $actual"
      mismatch=1
    fi
  done < "$BUNDLE/db/rowcounts.tsv"
  if [ "$mismatch" = "0" ]; then
    ok "各表行数与旧库一致"
  else
    warn "存在行数差异，请人工核对"
  fi
fi

# ======================================================================
step "6/9 改写配置与数据库中的旧地址"
# ======================================================================
set_env_kv() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  K="$key" V="$value" awk '
    BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"]; found = 0 }
    $0 ~ "^[[:space:]]*" k "=" { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

PARAMS=""
if [[ "$OLD_DSN" == *\?* ]]; then
  PARAMS="?${OLD_DSN#*\?}"
fi
NEW_DSN="${NEW_USER}:${NEW_PASS}@tcp(127.0.0.1:3306)/${DB_NAME}${PARAMS}"
set_env_kv "$ENVF" "DB_DSN" "$NEW_DSN"
set_env_kv "$ENVF" "UPLOAD_DIR" "$APP_BASE/uploads"
if [ -n "$PUBLIC_BASE_URL" ]; then
  set_env_kv "$ENVF" "PUBLIC_BASE_URL" "$PUBLIC_BASE_URL"
fi
chmod 0600 "$ENVF"
ok "shinepick.env 已更新（DSN 指向 127.0.0.1:3306）"

if [ -n "$PUBLIC_BASE_URL" ]; then
  rewrite_urls() {
    local old="$1" new="$2" o n uc cc vc
    [ "$old" = "$new" ] && return 0
    o="$(sql_escape "$old")"
    n="$(sql_escape "$new")"
    uc="$(mysql_root -N -B -e "SELECT COUNT(*) FROM \`$DB_NAME\`.users WHERE avatar_url LIKE '%$o%'" 2>/dev/null || echo 0)"
    cc="$(mysql_root -N -B -e "SELECT COUNT(*) FROM \`$DB_NAME\`.checkins WHERE image_urls LIKE '%$o%'" 2>/dev/null || echo 0)"
    vc="$(mysql_root -N -B -e "SELECT COUNT(*) FROM \`$DB_NAME\`.checkins WHERE video_url LIKE '%$o%'" 2>/dev/null || echo 0)"
    mysql_root "$DB_NAME" <<SQL
UPDATE users SET avatar_url = REPLACE(avatar_url, '$o', '$n') WHERE avatar_url LIKE '%$o%';
UPDATE checkins SET image_urls = REPLACE(image_urls, '$o', '$n') WHERE image_urls LIKE '%$o%';
UPDATE checkins SET video_url = REPLACE(video_url, '$o', '$n') WHERE video_url LIKE '%$o%';
SQL
    ok "URL 改写 $old → $new（users $uc / checkins $cc / video $vc）"
  }

  seen=" "
  OLD_BASES=("$SOURCE_PUBLIC_BASE_URL" "http://127.0.0.1:8080" \
             "http://$KNOWN_OLD_IP:8080" "http://$KNOWN_OLD_IP")
  if [ -n "$SOURCE_IP" ]; then
    OLD_BASES+=("http://$SOURCE_IP:8080" "http://$SOURCE_IP")
  fi
  for old in "${OLD_BASES[@]}"; do
    [ -n "$old" ] || continue
    old="${old%/}"
    case "$seen" in
      *" $old "*) continue ;;
    esac
    seen="$seen$old "
    rewrite_urls "$old" "$PUBLIC_BASE_URL"
  done

  if [ -n "$SOURCE_IP" ]; then
    left="$(mysql_root -N -B -e "
      SELECT (SELECT COUNT(*) FROM \`$DB_NAME\`.users WHERE avatar_url LIKE '%$SOURCE_IP%')
           + (SELECT COUNT(*) FROM \`$DB_NAME\`.checkins WHERE image_urls LIKE '%$SOURCE_IP%')
           + (SELECT COUNT(*) FROM \`$DB_NAME\`.checkins WHERE video_url LIKE '%$SOURCE_IP%')
           + (SELECT COUNT(*) FROM \`$DB_NAME\`.users WHERE avatar_url LIKE '%$KNOWN_OLD_IP%')
           + (SELECT COUNT(*) FROM \`$DB_NAME\`.checkins WHERE image_urls LIKE '%$KNOWN_OLD_IP%')
           + (SELECT COUNT(*) FROM \`$DB_NAME\`.checkins WHERE video_url LIKE '%$KNOWN_OLD_IP%')" 2>/dev/null || echo '?')"
    if [ "$left" = "0" ]; then
      ok "数据库中已无旧 IP（$SOURCE_IP / $KNOWN_OLD_IP）的资源链接"
    else
      warn "数据库中仍有 $left 条记录包含旧 IP，请人工检查"
    fi
  fi
else
  warn "未指定 --public-url：PUBLIC_BASE_URL 与数据库图片链接保持旧值，客户端可能无法加载"
fi

if grep -q 'CHANGE_ME' "$ENVF"; then
  warn "shinepick.env 中仍有 CHANGE_ME 占位符，请检查 JWT_SECRET / ADMIN_TOKEN"
fi

# ======================================================================
step "7/9 恢复 systemd / Nginx / 证书 / cron"
# ======================================================================
UNITS_SRC="$BUNDLE/files/etc/systemd/system"
UNIT_DIR="/etc/systemd/system"
UNIT="$UNIT_DIR/shinepick-api.service"
if [ -d "$UNITS_SRC" ]; then
  mkdir -p "$UNIT_DIR"
  for u in "$UNITS_SRC"/*.service; do
    [ -f "$u" ] || continue
    cp -a "$u" "$UNIT_DIR/"
  done
  for d in "$UNITS_SRC"/*.service.d; do
    [ -d "$d" ] || continue
    cp -a "$d" "$UNIT_DIR/"
  done

  if [ -f "$UNIT" ]; then
    [ -f "$UNIT.orig" ] || cp -a "$UNIT" "$UNIT.orig"
    sed -i "s|/opt/shinepick|$APP_BASE|g" "$UNIT"
    sed -i "s/mysql\.service/${MYSQL_SVC}.service/g; s/mysqld\.service/${MYSQL_SVC}.service/g; s/mariadb\.service/${MYSQL_SVC}.service/g" "$UNIT"
    if [ -n "$REDIS_SVC" ]; then
      sed -i "s/redis-server\.service/${REDIS_SVC}.service/g; s/redis\.service/${REDIS_SVC}.service/g" "$UNIT"
    fi
  fi
fi

# 旧机没有可收集的单元时补一个，保证新机能启动
if [ ! -f "$UNIT" ]; then
  mkdir -p "$UNIT_DIR"
  AFTER="network.target ${MYSQL_SVC}.service"
  WANTS="${MYSQL_SVC}.service"
  if [ -n "$REDIS_SVC" ]; then
    AFTER="$AFTER ${REDIS_SVC}.service"
    WANTS="$WANTS ${REDIS_SVC}.service"
  fi
  cat > "$UNIT" <<EOF
[Unit]
Description=ShinePick API Server (Go)
After=$AFTER
Wants=$WANTS

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_BASE
EnvironmentFile=$APP_BASE/shinepick.env
ExecStart=$APP_BASE/shinepick-api
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$APP_BASE/uploads
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  ok "已生成默认 shinepick-api.service"
fi

# 旧机 apkserver 若用 nohup 启动、没有单元，这里补一个
if [ "$SKIP_APK" != "1" ] && [ "$APK_INCLUDED" = "1" ] && [ ! -f "$UNIT_DIR/apkserver.service" ]; then
  cat > "$UNIT_DIR/apkserver.service" <<EOF
[Unit]
Description=APK distribution server
After=network.target

[Service]
WorkingDirectory=$APK_BASE
ExecStart=$APK_BASE/apkserver -port 8082 -dir $APK_BASE/apks
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
fi

if [ -f "$UNIT" ] || [ -f "$UNIT_DIR/apkserver.service" ]; then
  systemctl daemon-reload
  ok "systemd 单元已安装（MySQL 依赖改为 $MYSQL_SVC）"
fi

if [ "$SKIP_CERTS" != "1" ] && [ "$CERTS_INCLUDED" = "1" ]; then
  for p in etc/letsencrypt root/.acme.sh; do
    if [ -d "$BUNDLE/files/$p" ]; then
      target="/$p"
      if [ -e "$target" ]; then
        mv "$target" "$target.bak-$STAMP"
      fi
      mkdir -p "$(dirname "$target")"
      cp -a "$BUNDLE/files/$p" "$target"
      ok "已恢复 /$p"
    fi
  done
fi

if [ "$SKIP_NGINX" != "1" ] && [ "$NGINX_INCLUDED" = "1" ] && [ -d "$BUNDLE/files/etc/nginx" ]; then
  if ! command -v nginx >/dev/null 2>&1; then
    warn "新机未安装 Nginx，已跳过；配置在 $BUNDLE/files/etc/nginx"
  else
    if [ -d /etc/nginx ]; then
      mv /etc/nginx "/etc/nginx.bak-$STAMP"
    fi
    cp -a "$BUNDLE/files/etc/nginx" /etc/nginx
    if [ -n "$NEW_IP" ] && [[ "$NEW_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      seen_ips=" "
      for oldip in "$SOURCE_IP" "$KNOWN_OLD_IP"; do
        [ -n "$oldip" ] || continue
        [ "$oldip" = "$NEW_IP" ] && continue
        [ "$oldip" = "127.0.0.1" ] && continue
        [ "$oldip" = "localhost" ] && continue
        [[ "$oldip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || continue
        case "$seen_ips" in
          *" $oldip "*) continue ;;
        esac
        seen_ips="$seen_ips$oldip "
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          sed -i "s/${oldip//./\\.}/$NEW_IP/g" "$f"
        done < <(grep -rlF "$oldip" /etc/nginx 2>/dev/null || true)
        ok "Nginx 配置中的旧 IP $oldip 已替换为 $NEW_IP"
      done
    fi
    if nginx -t >/dev/null 2>&1; then
      systemctl enable nginx >/dev/null 2>&1 || true
      systemctl reload nginx 2>/dev/null || systemctl start nginx || true
      ok "Nginx 配置已恢复并加载"
    else
      nginx -t 2>&1 || true
      warn "nginx -t 未通过，回滚原配置（新配置在 /etc/nginx，备份见 .bak-$STAMP）"
      rm -rf /etc/nginx
      if [ -d "/etc/nginx.bak-$STAMP" ]; then
        mv "/etc/nginx.bak-$STAMP" /etc/nginx
      fi
      systemctl reload nginx 2>/dev/null || true
    fi
  fi
fi

if [ -d "$BUNDLE/config/cron.d" ]; then
  mkdir -p /etc/cron.d
  for f in "$BUNDLE"/config/cron.d/*; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    if [ "$WITH_CRON" = "1" ] || [[ "$b" == *shinepick* || "$b" == *apk* || "$b" == *backup* ]]; then
      cp -a "$f" /etc/cron.d/
      ok "已恢复 cron: $b"
    else
      warn "跳过无关 cron: $b（--with-cron 可全部恢复）"
    fi
  done
fi
if [ "$WITH_CRON" = "1" ] && [ -s "$BUNDLE/config/root.crontab" ]; then
  if command -v crontab >/dev/null 2>&1; then
    crontab "$BUNDLE/config/root.crontab"
    ok "root crontab 已恢复"
  else
    warn "未安装 crontab，跳过 root crontab；内容见 $BUNDLE/config/root.crontab"
  fi
fi
systemctl reload crond 2>/dev/null || systemctl reload cron 2>/dev/null || true

# ======================================================================
step "8/9 启动服务并验证"
# ======================================================================
if [ -f "$BUNDLE/inventory/timedatectl.txt" ]; then
  OLD_TZ="$(awk -F': ' '/Time zone:/{print $2; exit}' "$BUNDLE/inventory/timedatectl.txt" 2>/dev/null | awk '{print $1}' || true)"
  NEW_TZ="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  if [ -n "$OLD_TZ" ] && [ -n "$NEW_TZ" ] && [ "$OLD_TZ" != "$NEW_TZ" ]; then
    warn "时区不一致: 旧机 $OLD_TZ / 新机 $NEW_TZ"
    warn "如业务依赖本地时间，请执行: timedatectl set-timezone $OLD_TZ"
  fi
fi

systemctl enable shinepick-api >/dev/null 2>&1 || true
systemctl restart shinepick-api || true

api_ok=0
for _ in $(seq 1 15); do
  if curl -fsS -m 5 http://127.0.0.1:8080/ping 2>/dev/null | grep -q '"pong":true'; then
    api_ok=1
    break
  fi
  sleep 1
done
if [ "$api_ok" = "1" ]; then
  ok "API /ping 正常"
else
  journalctl -u shinepick-api -n 40 --no-pager 2>/dev/null || true
  die "API 健康检查失败；请查看 journalctl -u shinepick-api -f"
fi

if MYSQL_PWD="$NEW_PASS" "$MYSQL_BIN" -h 127.0.0.1 --protocol=tcp \
     -u "$NEW_USER" -e "SELECT 1" "$DB_NAME" >/dev/null 2>&1; then
  ok "应用账号 TCP 连接数据库正常"
else
  warn "应用账号 $NEW_USER 通过 TCP 连接失败，请检查 MySQL 用户/防火墙"
fi

if command -v redis-cli >/dev/null 2>&1; then
  if redis-cli ping 2>/dev/null | grep -q PONG; then
    ok "Redis PONG"
  else
    warn "Redis 无响应，验证码/限流等功能可能异常"
  fi
fi

if [ "$SKIP_APK" != "1" ] && [ "$APK_INCLUDED" = "1" ]; then
  systemctl enable apkserver >/dev/null 2>&1 || true
  if systemctl restart apkserver 2>/dev/null; then
    sleep 1
    if curl -fsS -m 5 http://127.0.0.1:8082/ping >/dev/null 2>&1; then
      ok "apkserver /ping 正常"
    else
      warn "apkserver 已启动但 /ping 无响应"
    fi
  else
    warn "apkserver 启动失败；可手工运行: $APK_BASE/apkserver -port 8082 -dir $APK_BASE/apks"
  fi
fi

SUCCESS=1

# ======================================================================
step "9/9 完成"
# ======================================================================
NEW_BASE="${PUBLIC_BASE_URL:-http://<新机公网IP>:8080}"
cat <<EOF

恢复完成:
  应用目录 : $APP_BASE
  数据库   : $DB_NAME（账号 $NEW_USER）
  对外地址 : $NEW_BASE
  服务状态 : systemctl status shinepick-api
  日志     : journalctl -u shinepick-api -f

仍需手工确认:
  1. 云安全组放行 TCP 8080（apkserver 为 8082），使用域名再放行 80/443
  2. 本机防火墙也要放行: firewall-cmd --add-port=8080/tcp --permanent（或 ufw allow 8080/tcp）
  3. DNS 解析切到 8.134.144.35；切换后验证手机 App / Web
  4. HTTPS 证书: certbot renew --dry-run（若使用 Let's Encrypt）
  5. 旧服务器保留 3-7 天，确认数据无误后再释放
  6. 已安装 APK 内置旧 API 地址，需重新打包，或在旧机保留 8080 转发
  7. 删除迁移包（含密钥）: $BUNDLE_ARG
EOF
if [ -n "$EXTRACT_DIR" ] && [ "$KEEP_EXTRACT" = "1" ]; then
  printf '  解包目录: %s\n' "$EXTRACT_DIR"
fi
