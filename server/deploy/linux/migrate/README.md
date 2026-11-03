# 服务器迁移：129.226.159.168 → 8.134.144.35

两个脚本，分别在新旧服务器上执行：

| 脚本 | 运行位置 | 作用 |
|------|----------|------|
| `backup-old.sh` | 旧机 129.226.159.168 | 停止写入 → 导出 MySQL + uploads → 收集配置 → 打包并校验 |
| `restore-new.sh` | 新机 8.134.144.35 | 校验迁移包 → 恢复文件/database/systemd → 改写地址 → 启动验证 |

迁移包会自动带上同目录的 `restore-new.sh`。建议把整个 `migrate/` 目录上传到旧机；只上传 `backup-old.sh` 也能打包，但新机恢复时需要另外传 `restore-new.sh`。

## 迁移前

1. 新机装好 Linux，确认能 SSH 登录，记录 CPU 架构（`uname -m`）。旧机二进制是 `x86_64`；新机若为 `aarch64`，需要先在开发机交叉编译 `shinepick-api` 和 `apkserver`。
2. 新机云控制台安全组放行：`8080`（API/Web）、`8082`（apkserver）；用域名再加 `80/443`。
3. 如使用域名，先把 DNS TTL 调小（如 60s），切换当天再改 A 记录。
4. 旧机确认是 **二进制 + systemd** 部署（`/opt/shinepick`、`/opt/apkserver`）。Docker Compose 部署不在本脚本覆盖范围内。
5. 建议在新机先手动装好 MySQL 8.0（与旧库同大版本最稳），避免 `--install-deps` 装成 MariaDB 后遇到 `utf8mb4_0900` 排序规则不兼容。

## 一、旧机备份

把脚本传到旧机（任选其一）：

```bash
# 开发机：建议整个目录一起传，打包时会自动放入 restore-new.sh
scp -r shinepick/server/deploy/linux/migrate root@129.226.159.168:/root/

# 只传备份脚本（新机需另传 restore-new.sh）
scp shinepick/server/deploy/linux/migrate/backup-old.sh root@129.226.159.168:/root/
```

在旧机执行：

```bash
ssh root@129.226.159.168
chmod +x /root/migrate/backup-old.sh
sudo /root/migrate/backup-old.sh --push root@8.134.144.35
```

> 只上传了单文件时，路径改为 `/root/backup-old.sh`；迁移包里不会包含 `restore-new.sh`。

脚本会：

- 预拷贝 `/opt/shinepick`（不含 uploads/backups/日志）与 `/opt/apkserver`
- 停止 `shinepick-api` → `mysqldump --single-transaction` → 增量同步 uploads → 立即拉起 API
- 收集 `shinepick.env`、systemd 单元、`/etc/nginx`、Let's Encrypt/acme.sh、cron、主机清单
- 生成 `MANIFEST`、`SHA256SUMS`，打包为 `/root/shinepick-migrate/shinepick-migrate-<时间戳>.tar.gz`
- `--push` 时用 rsync/scp 推到新机 `/root`，并在新机做一次 SHA256 校验

停机时间约为「数据库导出 + uploads 增量同步」，通常几秒到一两分钟。脚本异常退出会自动重新启动 API。

常用参数：

```bash
--no-stop        不停 API（快照不保证严格一致，仅应急）
--no-apk         不迁移 /opt/apkserver
--no-nginx       不收集 Nginx
--no-certs       不收集证书
--with-redis     额外备份 /var/lib/redis（缓存一般不需要；恢复时会一并还原）
--out DIR        输出到其他磁盘（如 /data/migrate）
--zstd           使用 zstd 压缩（产出 .tar.zst）
--keep-bundle    保留解包目录
```

> 磁盘要求：脚本会同时保留「bundle 目录 + 压缩包」，需要约 2 倍 uploads 大小的可用空间。空间不足时用 `--out` 指到大盘。

## 二、新机恢复

如果旧机已 `--push`，直接登录新机：

```bash
ssh root@8.134.144.35
cd /root
sha256sum -c shinepick-migrate-*.sha256
tar -xzf shinepick-migrate-*.tar.gz
cd shinepick-migrate-*/
sudo ./restore-new.sh --public-url http://8.134.144.35:8080 --install-deps
```

> 如果备份用了 `--zstd`，解压命令改为 `tar --zstd -xf shinepick-migrate-*.tar.zst`。
>
> `restore-new.sh` 的第一个参数是迁移包或解包目录，省略时默认当前目录；上面的命令就是 `cd` 到解包目录后直接执行。

如果新机已自行安装 MySQL 8.0 / Redis / Nginx，去掉 `--install-deps`。RHEL 系首次安装的 MySQL root 临时密码在 `/var/log/mysqld.log`，用 `--mysql-root-pass` 传入。

恢复脚本会：

1. 校验整包与包内每个文件的 SHA256
2. 检查架构；`x86_64` 二进制不会在 `aarch64` 上跑，会直接报错
3. 恢复 `/opt/shinepick`、`/opt/apkserver`、`/usr/local/bin/shinepick`
4. 建库、建应用账号（默认沿用旧账号；旧账号是 `root` 时改为 `shinepick`），导入 dump，并逐表核对行数
5. 改写 `shinepick.env`：DSN 指向 `127.0.0.1:3306`，`UPLOAD_DIR` 指向新路径，`PUBLIC_BASE_URL` 写为新地址
6. 把数据库里 `users.avatar_url`、`checkins.image_urls`、`checkins.video_url` 中指向 `129.226.159.168:8080` / `127.0.0.1:8080` 的链接改为新地址
7. 安装 systemd 单元（把 `After/Wants` 里的 MySQL/Redis 服务名改成新机实际名称），恢复 Nginx/证书/cron
8. 启动 `shinepick-api`、`apkserver`，检查 `/ping`、应用账号 TCP 连接、Redis

常用参数：

```bash
--public-url URL     新对外地址，如 https://api.example.com
--new-ip IP          只给 IP，自动拼成 http://IP:8080
--db-user USER       应用数据库账号（默认沿用旧账号）
--db-pass PASS       应用数据库密码（默认沿用旧密码；为空则随机生成）
--mysql-root-pass P  MySQL root 密码（默认 socket / ~/.my.cnf）
--force              覆盖已有目录、删除并重建同名数据库（重跑/切换时用）
--skip-nginx / --skip-certs / --skip-apk
--with-cron          恢复全部 cron（默认只恢复含 shinepick/apk/backup 的）
--ignore-arch        忽略架构不一致（不推荐）
--keep-extract       恢复成功后保留解包目录（排查时用）
```

## 三、验证

```bash
curl http://127.0.0.1:8080/ping
curl http://127.0.0.1:8082/ping
systemctl status shinepick-api --no-pager
journalctl -u shinepick-api -n 50 --no-pager

# 数据库行数（与旧机对比）
mysql -N -e "SELECT COUNT(*) FROM shinepick.users;"
```

浏览器打开 `http://8.134.144.35:8080/`，重点检查：

- 登录是否正常（JWT_SECRET 沿用旧值，旧 token 仍有效）
- 历史头像/打卡图片能否加载（URL 改写是否成功）
- 新上传图片能否写入 `/opt/shinepick/uploads/`
- apkserver 页面与 APK 下载

## 四、正式切换

如果备份和恢复之间旧机仍有新数据，按下面顺序做最后一次增量：

1. 旧机再跑一次备份（会生成新时间戳的包）：
   ```bash
   sudo /root/backup-old.sh --push root@8.134.144.35
   ```
2. 新机用 `--force` 恢复新包（会删除并重建 shinepick 库）：
   ```bash
   tar -xzf shinepick-migrate-<新时间戳>.tar.gz
   cd shinepick-migrate-<新时间戳>
   sudo ./restore-new.sh --public-url http://8.134.144.35:8080 --force
   ```
3. 验证通过后，停旧机服务并改 DNS/安全组：
   ```bash
   # 旧机
   systemctl stop shinepick-api apkserver
   # 如需彻底停用
   systemctl disable shinepick-api apkserver
   ```
4. DNS 切到 `8.134.144.35`，观察客户端请求是否落到新机。

> 旧机不要立即释放，至少保留 3-7 天作为回滚副本。

## 五、回滚

- DNS 切回旧机 A 记录；
- 旧机 `systemctl start shinepick-api apkserver`（数据是切换时的状态，切换后新机产生的数据不会自动回流）；
- 新机保留迁移包和 `/opt/*.bak-*` 目录，便于排查。

## 六、客户端地址（重要）

现有 Android APK 是用编译期常量注入 API 地址的，v0.2.0 包里写死的是：

```text
http://129.226.159.168:8080/api/v1
```

服务端迁移不会改变已安装 APK 里的这个地址。切换后老客户端会继续请求旧机，处理方式二选一：

1. **重新打包 APK（推荐）**：用新地址重新构建，放到新机 apkserver 供用户升级：
   ```bash
   flutter build apk --release \
     --dart-define=API_BASE_URL=http://8.134.144.35:8080/api/v1
   ```
   然后把产物拷到新机 `/opt/apkserver/apks/`，页面会立即列出新包。
2. **旧机保留转发**：旧机不要释放，用 Nginx `stream` 或 `socat` 把 8080 转发到新机：
   ```nginx
   stream {
       server {
           listen 8080;
           proxy_pass 8.134.144.35:8080;
       }
   }
   ```
   这样老客户端仍可用，但旧机会一直占用一台机器/公网 IP；确认用户升级完成后即可停掉。

Web 端如果构建时也注入了 `API_BASE_URL`，同样需要重新 `flutter build web`；当前仓库里的 Web 产物只检索到相对路径 `/api/v1`，一般按同源处理即可。

## 七、注意事项

- 迁移包包含数据库密码、`JWT_SECRET`、`ADMIN_TOKEN` 和证书私钥，脚本已设 `600/700` 权限；验证完成后删除，不要放进 Web 目录或公共网盘。
- Redis 默认不迁移：验证码、限流、缓存都是可重建数据。若业务把重要状态放 Redis，加 `--with-redis`。
- MySQL 采用逻辑备份，只迁移 `DB_DSN` 指向的库；同实例的其他库不会被带走。
- `--force` 会 `DROP DATABASE`，只在确认新机数据可丢弃时使用。
- 新机本机防火墙（firewalld/ufw）也要放行 8080/8082，云安全组只是第一层。
- 时区不一致时脚本只告警，不自动修改；如业务依赖本地时间，`timedatectl set-timezone Asia/Shanghai`。
- 若旧机 Nginx 反代了 80/443，恢复后执行 `nginx -t`、`certbot renew --dry-run`，并确认证书续期定时器已启用。
