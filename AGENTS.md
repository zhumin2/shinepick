# AGENTS.md — 拾光 ShinePick 项目背景

> 给后续 agent 的项目全貌：产品定位、代码结构、构建部署、Sprint 历史、踩坑经验、当前状态。
> 最后更新：2026-11-08（v0.6.0 后台强化开发完成，待发版）。

---

## 1. 项目是什么

**拾光 ShinePick** 是一个「记录每日正向小事」的轻社交 App。

- **核心玩法**：用户每天打卡一件正向小事（运动/阅读/旅行/社交/宠物/其他），每次打卡产生一颗「光点」，落在个人的「拾光树」上，树随打卡成长（12 阶段），并解锁徽章。
- **社交**：点亮 / 拥抱 / 同路（三种互动）、小便签留言（作者可图钉指定展示）、他人公开主页。
- **北极星指标**：周活跃打卡用户数（WAC）。
- **设计原则**：温和不焦虑（无排行榜、无连续打卡惩罚文案）、默认匿名安全（非同行关系互动通知匿名）、弱网可用（草稿/离线缓存）。

产品文档在仓库根：`拾光-产品设计文档-v1.md`（+ PDF）、`拾光-技术设计文档-v1.md`、`拾光-开发计划-v1.md`（12 Sprint / 6 里程碑）、`拾光-S1细化-开发计划.md`。
高保真原型：`prototype/拾光-产品原型.html`（单文件 HTML，含全部页面与设计 token）。

**计划与进度**：S1–S8 全部完成，里程碑 M1–M4 达成；原计划 S9（性能加固）尚未开始，实际先做了「社交体验补全」（他人主页等）。

---

## 2. 仓库结构

```
shinepick/
├── app/                     # Flutter 客户端（Android / Web / Windows / iOS）
│   ├── lib/
│   │   ├── main.dart        # MultiProvider 入口
│   │   ├── core/            # network(dio)/router(go_router)/theme/error/utils
│   │   ├── features/        # auth checkin comment discover garden home profile settings shell social
│   │   └── shared/          # models(Checkin/User) storage(token_store) widgets(FeedCard/Avatar/...)
│   ├── test/                # 组件/路由测试（8 个 _test.dart）
│   └── android|ios|web|windows/
├── server/                  # Go 服务端（Gin + GORM）
│   ├── cmd/api/main.go      # 入口：配置→DB/Redis→路由→每日 cron
│   ├── internal/
│   │   ├── config/          # 全部 env 读取
│   │   ├── model/           # GORM 模型
│   │   ├── repository/      # 数据访问（user/checkin/interaction/social/badge）
│   │   ├── service/         # 业务逻辑（auth/user/checkin/interaction/feed/social/tree/admin）
│   │   ├── module/          # HTTP handler + 路由注册（auth user checkin interaction social tree feed upload admin）
│   │   ├── middleware/      # JWT Auth
│   │   ├── pkg/             # code(错误码) httpx(响应) jwt audit sms
│   │   └── router/router.go # 装配全部模块
│   ├── migrations/          # 手写 SQL（0001–0007，各带 _rollback.sql）
│   ├── deploy/
│   │   ├── linux/           # install.sh / shinepick.sh / systemd / env / uploads / web / migrate/
│   │   ├── windows/         # install/start/stop/status + build_apk.bat + export_local_db.bat
│   │   ├── Dockerfile, docker-compose.yml, postman/
│   ├── bin/                 # 编译产物（gitignore）
│   ├── uploads/             # 运行时上传（avatars/images）+ web/ 前端产物
│   └── go.mod               # module shinepick
├── prototype/               # 高保真原型 + 设计稿
├── gui-test-screenshots/    # 原型截图（视觉验收参考）
├── index.html               # 仓库落地页
└── 拾光-*.md                # 产品/技术/计划文档
```

---

## 3. 技术栈

| 层 | 技术 | 版本/说明 |
|---|---|---|
| 客户端 | Flutter | 3.47.8（Dart 3） |
| 状态管理 | provider | 4 个 Controller：Auth/Checkin/Social/Garden |
| 路由 | go_router | 13.x |
| 网络 | dio | 统一 `ApiClient`（get/post/patch/delete/uploadBytes） |
| 本地存储 | hive + hive_flutter | token、草稿、feed 缓存 |
| 图片 | image + file_picker | 客户端多级压缩后 multipart 上传 |
| 服务端 | Go + Gin + GORM | go.mod 声明 go 1.18，本机工具链 Go 1.27.3 |
| 数据库 | MySQL 8.0 | utf8mb4，DSN 见 env |
| 缓存/频控/幂等 | Redis 5.0 | INCR 窗口、SetNX 幂等、feed 缓存 |
| 鉴权 | JWT 双 token | access 7d + refresh 30d 轮换（Bearer） |
| 短信 | 腾讯云 SMS | TC3-HMAC-SHA256 手写签名，无 SDK；SMS_TYPE=mock 时固定 123456 |
| 内容审核 | mock 关键词 / 远程服务 | AUDIT_TYPE=mock/remote |

---

## 4. 服务端架构

分层：`module(handler)` → `service` → `repository` → `model(GORM)`；横切 `middleware/pkg`。

### 4.1 API 一览（全部前缀 `/api/v1`）

**公开**
| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/sms-code` | 发验证码（60s 频控） |
| POST | `/auth/login` | 手机号+验证码登录，返回双 token |
| POST | `/auth/refresh` | refresh 换 access（轮换） |
| GET | `/ping` | 健康检查（在根，不在 /api/v1） |
| GET | `/app/latest` | 检查更新：代理 apkserver `/api/latest`（APK_LATEST_BASE env 配置公网基地址），返回 `{version,url}`；apkserver 按文件名 `shinepick-server-vX.Y.Z-android.apk` 自动探测最高版本，上传即生效 |

**登录态（middleware.Auth）**
| 方法 | 路径 | 说明 |
|---|---|---|
| GET/PATCH | `/users/me` | 我的资料（含 stats） |
| POST | `/users/me/avatar` | 头像上传（≤2MB，jpg/png/webp） |
| GET | `/users/:id` | **他人公开主页**（无手机号/未成年标记；封禁返回 5001） |
| GET | `/users/:id/checkins` | 某人的打卡列表（自己=全部，他人=同路人可见），游标分页 |
| GET | `/users/:id/companions` | 某人的同路人列表（id/nickname/avatar_url/since，排除自己与封禁号） |
| POST/GET/DELETE | `/checkins` `/checkins/:id` | 发布/详情/软删（幂等，重复删 5001） |
| PATCH | `/checkins/:id` | 作者改可见范围 `{visibility: 1\|2\|3}`（隐藏/公开）；删除与改隐藏都会触发今日微光缓存重建 |
| POST/DELETE | `/checkins/:id/reactions` | 点亮(1)/拥抱(2)/同路(3)，幂等；同路建关系 |
| POST/GET | `/checkins/:id/comments` | 留言（≤80 字） |
| DELETE | `/comments/:id` | 删留言（本人或作者） |
| PATCH | `/comments/:id/feature` | 作者图钉指定/取消展示 |
| GET | `/feed` | 今日微光（每日 08:00 CST 品类均衡精选）+ 同品类 doing |
| GET | `/feed/companions?cursor=` | 同路人动态流（互为同路人的最新公开拾光，排除自己，JOIN 关系表） |
| GET | `/explore?category=&cursor=` | 发现页分页浏览 |
| GET | `/checkins/:id` | 详情，响应 `{checkin, user}`（user=作者昵称/头像）；非作者仅 visibility=2 可见 |
| GET | `/users/me/weekly` | 拾光周报（周一至周日）：本周次数/天数/连续、上周对比、7 日明细（含当日主品类）、品类分布 |
| GET | `/tree` | 树状态 + 季节 + 光点历史 |
| GET | `/badges` | 徽章列表；POST `/badges/evaluate` 幂等补发 |
| GET/POST | `/notifications` `/notifications/read` | 通知列表/全部已读 |
| POST/GET/DELETE | `/blocks` `/blocks/:userId` | 拉黑/黑名单/取消 |
| POST | `/reports` | 举报 |
| POST | `/uploads/images` | 多图上传（≤9 张，单张 ≤5MB） |

**运营（`/admin`，X-Admin-Token + 同 IP 10 次失败锁 10 分钟防爆破）**
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/admin/stats` | 北极星指标面板数据 |
| GET | `/admin/stats/trend?days=` | 逐日 DAU/打卡数/新增用户（缺省 14 天，1–60） |
| PUT | `/admin/feed/selected` | 指定今日精选 |
| POST | `/admin/feed/rebuild` | 重建今日精选 |
| GET | `/admin/reports?status=&page=` | 举报列表（含被举报对象内容快照；status 0/1/2/all） |
| POST | `/admin/reports/:id/handle` | 处理举报 `{action: delete_content\|ban_user\|dismiss, note?}` |
| GET | `/admin/users?keyword=&page=` | 用户列表（昵称模糊/ID 精确；手机号密文不可搜） |
| GET | `/admin/users/:id` | 用户详情（资料+统计+最近 10 条打卡含未公开） |
| PUT | `/admin/users/:id/status` | 封禁/解封 `{status:0\|1}`，即时失效/恢复登录态 |
| GET | `/admin/checkins?keyword=&category=&page=` | 全量打卡巡检（含未公开/已删） |
| DELETE | `/admin/checkins/:id` | 下架打卡（软删+重建今日微光） |
| GET | `/admin/comments?keyword=&page=` | 留言巡检 |
| DELETE | `/admin/comments/:id` | 删留言 |
| POST | `/admin/announcements` | 系统公告 `{user_ids:null(全员)\|[..], content≤140}` → notifications type=5 |
| GET | `/admin/feedback?status=&page=` | 意见反馈列表 |
| POST | `/admin/feedback/:id/done` | 标记反馈已处理 |
| GET | `/admin/actions?page=` | 管理操作留底查询 |
| GET | `/admin/trash/checkins?page=`、`GET /admin/trash/comments?page=` | 回收站：已删打卡/留言列表（v0.6.1） |
| POST | `/admin/trash/checkins/:id/restore`、`POST /admin/trash/comments/:id/restore` | 恢复软删内容（打卡恢复后重建今日微光；v0.6.1） |
| GET | `/admin/announcements` | 近期系统通知批次与已读率（type=5 按文案+日期聚合，v0.6.1） |
| GET | `/admin` | HTML 运营面板（tab：指标/举报/用户/内容/公告/反馈/日志/回收站；公告 tab 含已读率表；反馈 tab 可一键回复=定向公告；面板无 token 输入值，token 存 localStorage） |

**登录态补充（v0.6.0）**：`POST /feedback` 意见反馈（≤200 字，10 分钟 1 条）。 |

**静态**：`/static/*` → `UPLOAD_DIR`（含 `/static/web/` 前端产物，带 `Cache-Control: no-cache, must-revalidate`）；头像 `/static/avatars/`，配图 `/static/images/`。

### 4.2 错误码（`internal/pkg/code`）

`0` 成功；`1001` 参数错误；`2001` 未登录/过期；`3001` 验证码错误/过期；`4001` 操作过于频繁；`4101` 审核未通过；`5001` 不存在/已删除；`5002` 无权限；`5003` 账号已被封禁；`9000` 内部错误。响应统一 `{code,message,data,request_id}`。

### 4.3 关键实现约定

- **幂等**：打卡/留言/互动都带 `client_token`，Redis SetNX + TTL；**幂等判断必须早于频控**（否则重试被频控挡住）。
- **频控**：Redis INCR 窗口——打卡 3 次/分、留言 1 条/10s、短信 1 条/60s。
- **审核**：发布打卡/留言前过 `audit`，命中敏感词返回 4101。
- **通知**：`social.notifyEvent` 服务层生成文案；非同行关系点亮/拥抱匿名；10 分钟内同事件聚合；夜间免打扰在客户端设置。
- **每日精选**：`StartDailyCron` 08:00 CST 重建；品类均衡轮转 + Redis 缓存 + 管理后台可覆盖。
- **徽章**：发布打卡触发 `EvaluateBadges`（幂等，自愈补发），8 枚种子见 `0006_badges.sql`。
- **时区**：业务统一东八区 `cstZone = FixedZone("CST", 8*3600)`；`checkin_date` 为 DATE。
- **连续天数**：`computeStreak` 从今天（今天没打卡则从昨天）往前数，断签归零。

### 4.4 环境变量（`internal/config/config.go`）

`APP_ENV PORT DB_DSN REDIS_ADDR REDIS_PASSWORD JWT_SECRET REFRESH_TTL UPLOAD_DIR PUBLIC_BASE_URL ADMIN_TOKEN SMS_TYPE SMS_SECRET_ID SMS_SECRET_KEY SMS_APP_ID SMS_SIGN_NAME SMS_TEMPLATE_ID AUDIT_TYPE AUDIT_REMOTE_URL APK_LATEST_BASE`

---

## 5. 数据模型与迁移

手写 SQL，**不用 AutoMigrate**；每份含 `_rollback.sql`；部署脚本自动跳过 rollback。

| 迁移 | 内容 |
|---|---|
| 0001 | `users`（昵称/头像/bio/性别/城市/生日/is_minor/status）+ `user_secure`（手机号） |
| 0002 | `checkins`（category/content/checkin_date/visibility/image_urls JSON/extra JSON/client_token/软删）+ `tree_progress` |
| 0003 | `reactions`（type 1/2/3，唯一键防重）+ `comments` + `companion_relations` |
| 0004 | `comments.is_featured`（图钉展示） |
| 0005 | `notifications` + `blocks` + `reports` |
| 0006 | `badges`（8 枚种子）+ `user_badges` |
| 0007 | `checkins.custom_name`（自定义品类；后简化为 category=6「其他」，列保留兼容） |

品类：1 运动、2 阅读、3 旅行、4 社交、5 宠物、6 其他。

---

## 6. 客户端架构

- **入口** `main.dart`：MultiProvider(AuthController, CheckinController, SocialController, GardenController) + MaterialApp.router。
- **路由** `core/router/app_router.dart`：`/login` `/home`(ShellPage) `/profile` `/notifications` `/user/:id` `/settings`；`refreshListenable: auth` 驱动登录态重定向。
- **壳** `features/shell/shell_page.dart`：IndexedStack 4 Tab（今日/发现/拾光树/我的）+ 中央凸起 FAB + 发布成功 `SuccessOverlay`。
- **主要页面**：
  - 今日：问候 + 今日卡(N/5 品类勾选) + doing 横滑 + 今日微光 + 我的拾光
  - 发现：品类墨色 Tab + 列表 + 长按举报/拉黑
  - 拾光树：CustomPainter 12 阶段树 + 季节色 + 光点呼吸 + 徽章横滑 + 年进度
  - 我的：横排头部 + 4 格统计 + 轻量拾光列表 + 通知/设置入口
  - 打卡弹层：3 列品类网格 + 内容输入（emoji 面板）+ 图片选择压缩上传 + 可见范围
  - 留言弹层、通知页、设置页（夜间免打扰/安全中心/黑名单/退出）、他人主页
- **共享组件** `shared/widgets/`：`FeedCard`（渐变封面+meta+内容+图+胶囊互动+留言预览）、`Avatar`、`ImageviewerPage`（全屏缩放/多图滑动）、`EmojiPickerSheet`（内嵌 4 组 32 表情）、`EmojiText`（局部 emoji 字体兜底）、`Toast`、`AppSheet`、`ActBtn`。
- **主题 token** `core/theme/app_theme.dart`：primary `#E89B3C`、primaryDark `#C97F22`、bg `#FAF8F3`、sand `#F7E3C4`、textMain `#3A3A3A`、textSub、divider `#ECE6D8`、cardShadow、圆角 16/20。
- **网络**：`ApiConfig.baseUrl` 来自 `--dart-define=API_BASE_URL`，默认 `http://10.0.2.2:8080/api/v1`（仅 Android 模拟器）。Web 必须用相对路径 `/api/v1`。
- **图片压缩**：`ImageCompressor` 多级降级 (1920,85)→(1280,75)→(960,70)→(640,60)，目标 ≤500KB；上传带进度、60s 超时、自动重试一次。

### 客户端路由铁律
**二级页面一律 `context.push()`**。`context.go()` 是平级替换，会把页面栈清掉导致「无法返回」——这个 bug 在「我的页」「通知页」「设置页」都犯过（5087159、83b1b36 修复）。

---

## 7. 构建与运行

### 本机开发（Windows）
```bash
# 依赖：MySQL 8.0.28 (root/123456) + Redis 6379
cd server && go run ./cmd/api            # 或 server/bin/shinepick-api.exe，:8080
cd app && flutter run -d windows \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```
mock 验证码固定 `123456`（`SMS_TYPE=mock`），日志 `[sms:mock]` 可见。

### Web（同源，部署用）
```bash
cd app && flutter build web --release \
  --dart-define=API_BASE_URL=/api/v1 --base-href=/static/web/
# 产物拷到 server/uploads/web/ 与 server/deploy/linux/web/
```
访问 `http://<host>:8080/static/web/`。**Git Bash 坑**：`--base-href /static/web/` 会被 MSYS 路径转换劫持成 `C:/Program Files/Git/static/web/`（构建日志可见）——必须 `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"` 前缀或写 `--base-href=/static/web/` 等号形式加环境变量；验证产物用 ASCII 特征串（如 grep `feedback`）。

### Android APK
```bash
server/deploy/windows/build_apk.bat   # 内含 API_BASE_URL 与 JDK/SDK 路径
```
当前脚本指向 `http://8.134.144.35:8080/api/v1`。产物 `app/build/app/outputs/flutter-apk/app-release.apk`（约 60MB）。

### Windows 桌面
`flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1`。

### Linux 服务端
```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/shinepick-api-linux-amd64 ./cmd/api
```
部署套件 `server/deploy/linux/`：`install.sh`（自动检测 apt/dnf/yum、建库、跑迁移跳过 rollback）、`shinepick.sh`（start/stop/restart/status/health/logs/backup/update）、systemd 单元（沙箱加固，`User=shinepick`，`EnvironmentFile=/opt/shinepick/shinepick.env`）。

---

## 8. 部署拓扑（当前生产）

| 项 | 值 |
|---|---|
| 新机 | **8.134.144.35**（阿里云，主机名 iZ7xv4sx7fokr0uivm0kd3Z，Alibaba Cloud Linux / yum 系） |
| 旧机（迁移源） | 129.226.159.168（腾讯云 OpenCloudOS 9），保留 3–7 天 |
| API + Web + 静态 | `http://8.134.144.35:8080`（`/static/web/`、`/static/avatars/`、`/static/images/`） |
| APK 下载站 | `http://8.134.144.35:8082`（apkserver，目录 `/opt/apkserver/apks`，Go 零依赖单文件服务） |
| 服务端目录 | `/opt/shinepick`（二进制 shinepick-api、uploads、shinepick.env） |
| 进程管理 | systemd：`shinepick-api`、`apkserver` |
| 80 / 443 | **未开放**（实测连不通），客户端必须带 `:8080` |

**迁移**：`server/deploy/linux/migrate/`（`backup-old.sh` → `restore-new.sh`），流程与坑见该目录 README。迁移已成功完成（2026-11-03）。

**当前 APK**：v0.2.1，已改内置地址为 `http://8.134.144.35:8080/api/v1`（本机 `D:\code\elive\shinepick-server-v0.2.1-android.apk`）。服务器 `/opt/apkserver/apks` 里仍有旧 v0.2.0（旧 IP），需替换。

---

## 9. 开发历史（按里程碑）

### M1 基础平台（S1–S2）
- `244c3fb` 产品文档 + 高保真原型；`f10b808` 文档 v1.1；`32878a2` 技术设计；`232d763` 开发计划；`7129a51` S1 细化。
- `62a9cd3` **S1 工程骨架**：Go 服务端账号体系（短信登录/双 token/刷新）+ Flutter 骨架 + CI 待授权。
- `a852c34` **S2 用户资料**：GET/PATCH `/users/me`、生日联动 is_minor、头像上传 + 静态服务，18 项单测。
- `a8c19c6` 客户端「我的」页（资料编辑/头像/统计骨架）+ 基础组件库。

### M2 打卡闭环（S3–S4）
- `7aafef9` **S3 打卡闭环**：checkins/tree_progress 建表、发布事务联动树进度、审核拦截、频控、client_token 幂等、可见范围、多图上传；客户端打卡弹层 + 今日卡 + 光点动画。
- `d4948d4` 我的页统计接入真实打卡天数/连续天数（含断签与 RFC3339 归一化）。
- `e914b90` **S4 Feed 与今日页**：每日微光品类均衡 + 同品类陌生人 + Redis 缓存 + 08:00 cron；发现页接口；客户端三区布局、离线缓存、打卡草稿。
- `d3a9f72` 修复内容页头像只显示首字；`6dfcb13` 单图全宽 / 多图宫格。

### M3 互动与治理（S5–S6）
- `8eed2ed` **S5 互动与留言**：reactions/comments/companion_relations；点亮/拥抱/同路（幂等、my_reactions 回填）；80 字留言 + 审核 + 频控 + 幂等 + 本人/作者可删；客户端三态乐观更新。
- `70ea153` 留言发送加固（finally 复位、超时、具体错误）；`b4aafdf` 留言图钉精选展示（最多 2 条预览）；`87bb470` 预览显示头像。
- `9451e80` Web 上传修复（file_picker 在 Web 只有 bytes）。
- `5f6e38b` **S6 通知与治理**：notifications/blocks/reports 建表；互动/留言/同路通知（匿名 + 10 分钟聚合）；拉黑双向过滤 + 举报；客户端底部导航 + 发现页 + 通知页 + 设置页。

### M4 拾光树与内测（S7–S8）
- `aab0889` **S7 拾光树与徽章**：badges/user_badges + 8 枚种子；GET /tree、/badges、幂等评估；客户端 CustomPainter 12 阶段树 + 季节色 + 徽章 + 年进度。
- `54927c3` 原型全面对齐（中央 FAB、仪式感动画、品类勾选、渐变封面、胶囊互动、墨色 Tab 等）。
- `7acf009` → `2ed7394` 自定义品类 → 简化为统一「其他」（category=6）。
- `d7200f8` **S8 内测收尾**：X-Admin-Token 运营接口（stats/精选/重建）+ HTML 面板；长按举报/拉黑；黑名单管理。

### 部署与渠道
- `e8434fa` Linux 部署套件；`65ffb7e` Windows 一键部署；`80e51ed` Web 前端随仓库分发；`d8cec35` Web 改相对 API 路径。
- `18a51de`/`8dc0ec0`/`bc2a521` 测试数据与图片随仓库分发（后 `ca82d2f` 因误导入风险移除 SQL）；`fd7764c` 凭据解析；`1dc9ce8` 多发行版；`a7f3c27` `shinepick.sh` 统一管理。
- `3f92bb3` 安卓构建打通（Manifest 权限 + 明文 HTTP + gradle 9.3.1 + 禁 Kotlin 增量）。
- `f7efe26` 阿里云短信 → `7c363ec` 换腾讯云 SMS（TC3 签名）。

### 后续迭代（2026-10 下旬–11 月）
- `6c38849`/`1bc4498`/`0a7a98c` 图片压缩/进度/重试/头像压缩。
- `c0c286f` 图片全屏查看器；`f73a632` 键盘遮挡修复。
- `632b5cc` 情绪标签（后因与 emoji 重复移除）；`c697b68` emoji 面板 + Noto Color Emoji；`d0bf3f1`/`87a3d10`/`bd4a81e` emoji 三轮修复（UTF-16 光标、面板不遮挡、移除全局 fallback 修数字全角）。
- `fb7cf38` **他人公开主页**：GET `/users/{id}`（无手机号/未成年标记）+ 客户端 UserProfilePage + Feed 卡头像昵称跳转。
- `e389c80`/`6e2a6ac` 服务器迁移脚本；`8f5503d` APK 地址切到新服务器。

**共 71+ 提交**，主线 `main`，GitHub `zhumin2/shinepick`。

---

## 10. 踩坑经验（非常重要，改代码前必读）

### 客户端
1. **`context.go()` 会清栈**：二级页面用 `push()`，否则无法返回（5087159 / 83b1b36）。
2. **Web 文件选择只有 bytes**：`PlatformFile.path` 为 null，必须 `readAsBytes()` + `MultipartFile.fromBytes`。
3. **Dart String 是 UTF-16 码元坐标**：emoji 插入光标用 `emoji.length` 而不是 `runes.length`，混用导致连续输入乱码。
4. **Noto Color Emoji 含数字字形**：全局 `fontFamilyFallback` 会让数字变全角宽体；只在用户内容上用 `EmojiText` 局部兜底。
5. **表情面板要内嵌在弹层底部**（替换系统键盘区域），独立弹窗会遮挡输入框。
6. **发现页互动无反应**：`toggleReaction` 不能依赖 Controller 内部列表判断当前态，改为外部传 `currentlyActive` 且总是发请求。
7. **留言弹层关闭后要刷新**：发现页 `_reload()` / 首页 `_refreshAll()`，否则新留言不出现在卡片预览。
8. **Web 发版缓存**：浏览器会缓存旧 `main.dart.js`，服务端已加 no-cache；验证产物含新代码不能用 grep 中文（dart2js 用 UTF-16 编码字符串），要 grep ASCII 特征串。
9. **测试环境**：`testWidgets` 是 fake-async，Hive 真实 IO 会挂起；`flutter_test` 拦截所有 HTTP（E2E 用独立 dart 进程）。

### 服务端
10. **幂等必须在频控之前**：同一 client_token 重试若先撞频控会失败。
11. **`range` 循环变量是副本**：过滤拉黑内容不能在原切片上改，要返回新切片（`FilterBlockedFeedItems`）。
12. **DATE 列扫描出 RFC3339**：比较日期必须 `normalizeDate` 取前 10 位。
13. **连续天数**：今天没打卡不算断签（从昨天开始数），当日尚未结束。

### 构建/部署
14. **Windows 批处理**：纯 ASCII + CRLF（中文+LF 被 cmd 按 GBK 解析炸）；if 块内 echo 禁圆括号；等待用 `ping -n`（`timeout` 会解析到 GNU timeout）；`< nul` 在 Git Bash 会创建字面 `nul` 保留名文件（用 Python `\\?\` 设备路径删）。
15. **MySQL 选项文件**：路径必须正斜杠（`\` 是转义符）。
16. **所有 mysql 客户端显式 `-P` + `--protocol=tcp`**（否则连默认 3306）。
17. **迁移循环过滤 `*rollback*.sql`**；install.sh 迁移不可重入（0001/0007 非 IF NOT EXISTS，无 schema_migrations 表）——**不要先导库再跑 install.sh**。
18. **Gradle/AGP**：AGP 9.1 需 Gradle 9.3.1；旧 groovy 配置会遮蔽 kts 模板必须删；Windows Defender 锁 Kotlin `.tab` 缓存 → `kotlin.incremental=false` + 排除 build 目录。
19. **GitHub 推送不稳**：先 `git -c http.version=HTTP/1.1 -c http.postBuffer=157286400 push`，仍失败用 `-c http.curloptResolve=github.com:443:140.82.116.3`（113/114/116.3 实测通），循环重试。
20. **服务端 Web 构建必须相对路径** `/api/v1`，否则访客浏览器请求打到访客自己机器。

### 数据安全
21. 服务器已有真实数据：**所有更新/迁移脚本禁止 DROP/DELETE**；部署脚本会在跑迁移前检查 users 表是否已有数据。
22. `shinepick-data.sql` 曾因 REPLACE 语义可能覆盖线上数据，已从仓库移除并 gitignore。

---

## 11. 测试

- **客户端**：`cd app && flutter test`（8 个测试文件，24 项通过 + 1 skip）；`flutter analyze` 必须零问题。
- **服务端**：`cd server && go test ./...`（4 个 `_test.go`，覆盖认证/资料/打卡/互动/树等核心逻辑）。
- 部署后验证：`curl http://<host>:8080/ping` 应返回 `{"code":0,"message":"ok",...}`；`/api/v1/users/me` 未登录应返回 401 + code 2001。

---

## 12. 当前状态与下一步

### 已完成
- S1–S8、M1–M4；原型对齐；emoji；图片压缩/全屏；他人公开主页；服务器迁移；**v0.4.0 检查更新发版闭环、v0.4.1 图标、v0.5.0 周报/树分享/同路人分页、v0.5.1/0.5.2 修复与暖心短句**。
- **v0.6.0 后台强化（2026-11-08 本地完成、curl 冒烟全过，待发版）**：
  - 安全：admin 防爆破（10 次锁 10 分钟）、面板去明文 token、Auth 中间件封禁校验（Redis 60s 缓存 + 管理动作即时失效缓存）、登录/刷新拦封禁（新错误码 5003）。
  - 治理：举报处理台（快照+删内容/封作者/驳回）、用户管理（搜索/详情/封禁解封）、内容巡检（打卡/留言搜索+下架）；**公开流三查询补 `users.status=0` 过滤**（每日精选候选/今日品类/发现页——此前封禁后内容仍在公开流）、打卡详情非作者视角拦封禁作者。
  - 运营：系统公告（全员/定向，批量 INSERT 500/批）、14 天趋势、意见反馈（服务端+设置页入口）、管理操作留底（0009）、面板 tab 化（page.go，7 tab）。
  - 迁移：0008 feedback、0009 admin_actions（本地 dev 库已应用）。
  - 测试：go build/vet/test 全绿（新增 middleware 3 项 + service 2 项）；flutter analyze 0 问题 + 29 测试全绿；客户端版本 0.6.0。

### 待办（优先级从高到低）
1. **v0.6.1 发版（服务端增量，无迁移/无 APK/无 Web）**：服务器 `git pull`（到含 v0.6.1 的提交）→ `shinepick.sh update`（仓库预编译二进制已同步刷新）→ 面板验证回收站/公告已读率/反馈回复。v0.6.0 已于 2026-11-08 发版并外网验证（检查更新返回 0.6.0、面板 200）。
2. **生产化**：服务器 DB 密码/JWT_SECRET 仍默认；短信仍 mock（任何手机号 + 123456）；建议 Nginx + HTTPS + 域名；图片 URL 建议改存相对路径。
3. 留存方向候选（v0.7）：本地打卡提醒（flutter_local_notifications）、拾光日历、年底年度回顾。
4. S9 计划项：压测（P95<300ms）、防刷（设备指纹）、监控（Prometheus/Sentry）、审核误伤收敛（词库管理）。
5. S8-04/06（TestFlight、崩溃上报）需外部资源。

### 明确暂缓
- 腾讯云短信真实发送：代码已就绪，等签名/模板审核与凭据，**不要主动推进**。

---

## 13. 协作约定

- **提交信息**：中文，`feat:` / `fix:` / `chore:` / `docs:` / `build:` / `refactor:` / `security:` 前缀 + 模块括号（如 `fix(app):`、`feat(server):`、`feat(deploy):`），正文说清「改了什么 + 为什么」。
- **代码风格**：Go 按 gofmt；Dart 按 `flutter analyze` 零告警；注释中文、解释「为什么」而非「做什么」。
- **UI 改动**：对齐 `prototype/拾光-产品原型.html` 与 `app_theme.dart` token，不引入新的色板/圆角体系。
- **先测后提交**：`flutter analyze` + `flutter test` + `go test ./...` 全绿再提交；构建产物（web/APK）改动一并提交以便服务器分发。
- **数据库**：只加新迁移文件，不改历史迁移；每个迁移配 `_rollback.sql`；上线前确认不会破坏已有数据。
