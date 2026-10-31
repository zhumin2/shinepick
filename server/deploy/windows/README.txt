拾光 ShinePick · 服务端一键部署包（Windows）
================================================

包含组件
--------
- shinepick-api.exe     Go 服务端（API + Web 静态托管 + 运营接口）
- mysql/                便携版 MySQL 8.0.28（免安装）
- redis/                Redis 5.0.14 for Windows
- migrations/           数据库迁移脚本 0001~0007
- web/                  Web 客户端（由服务端 /static/web/ 托管）
- install.bat / start.bat / stop.bat / status.bat

一键部署
--------
1. 把整个文件夹放到目标机器任意目录（如 D:\shinepick）
2. 双击 install.bat        —— 初始化数据库 + 建库 + 迁移（仅首次）
3. 双击 start.bat          —— 启动 MySQL / Redis / API（三个最小化窗口）
4. 浏览器打开 http://127.0.0.1:8080/static/web/

日常使用
--------
- 启动: start.bat        停止: stop.bat        状态: status.bat
- Web 客户端: http://127.0.0.1:8080/static/web/
- 运营面板:   http://127.0.0.1:8080/admin（X-Admin-Token，默认 dev-admin-token）
- 健康检查:   http://127.0.0.1:8080/ping

配置（改脚本顶部变量）
--------
- 端口:        MYSQL_PORT / REDIS_PORT / API_PORT（默认 3306/6379/8080）
- MySQL 密码:  MYSQL_ROOT_PASSWORD（默认 123456，生产务必修改，
               同时改 start.bat 里的密码变量）
- JWT 密钥:    start.bat 里的 JWT_SECRET（生产务必修改）
- 运营令牌:    启动 API 前 set ADMIN_TOKEN=... （见 start.bat，可自行加一行）

数据与备份
--------
- 数据库数据: mysql\data\（备份=停服后整目录拷贝）
- 上传文件:   uploads\（头像/配图）
- Web 前端:   uploads\web\（更新前端时整目录替换）

常见问题
--------
- 端口被占用: 修改脚本顶部端口变量，或 netstat -ano | findstr :3306 查占用
- MySQL 起不来: 查看 "ShinepickMySQL" 窗口日志；数据目录损坏时删除 mysql\data 重跑 install.bat
- 电脑重启后需重新运行 start.bat（可自行加入开机启动文件夹）
