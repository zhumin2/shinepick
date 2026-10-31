@echo off
setlocal
chcp 65001 >nul
title ShinePick Server

rem ====== config (keep same as install.bat) ======
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MYSQL_PORT=3306"
set "REDIS_PORT=6379"
set "API_PORT=8080"
set "MYSQL_ROOT_PASSWORD=123456"
set "JWT_SECRET=change-me-in-production"

if not exist "%ROOT%\my.ini" (
  echo Please run install.bat first.
  pause
  exit /b 1
)

rem ---- 1. MySQL ----
start "ShinepickMySQL" /min "%ROOT%\mysql\bin\mysqld.exe" --defaults-file="%ROOT%\my.ini" --console
set /a TRIES=0
:waitmysql
set /a TRIES+=1
if %TRIES% GTR 30 (
  echo MySQL start TIMEOUT.
  pause
  exit /b 1
)
"%ROOT%\mysql\bin\mysqladmin.exe" -P %MYSQL_PORT% --protocol=tcp ping >nul 2>&1
if errorlevel 1 (
  ping -n 2 127.0.0.1 >nul
  goto waitmysql
)
echo [1/3] MySQL started (port %MYSQL_PORT%)

rem ---- 2. Redis ----
start "ShinepickRedis" /min "%ROOT%\redis\redis-server.exe" --port %REDIS_PORT%
ping -n 3 127.0.0.1 >nul
echo [2/3] Redis started (port %REDIS_PORT%)

rem ---- 3. API ----
set "DB_DSN=root:%MYSQL_ROOT_PASSWORD%@tcp(127.0.0.1:%MYSQL_PORT%)/shinepick?charset=utf8mb4&parseTime=True&loc=Local"
set "REDIS_ADDR=127.0.0.1:%REDIS_PORT%"
set "PORT=%API_PORT%"
set "UPLOAD_DIR=%ROOT%/uploads"
set "PUBLIC_BASE_URL=http://127.0.0.1:%API_PORT%"
set "APP_ENV=prod"
start "ShinepickAPI" /min "%ROOT%\server\shinepick-api.exe"
ping -n 3 127.0.0.1 >nul
echo [3/3] API started (port %API_PORT%)

echo.
echo ============================================
echo   ShinePick server is running
echo   Web:   http://127.0.0.1:%API_PORT%/static/web/
echo   Admin: http://127.0.0.1:%API_PORT%/admin
echo   Stop:  stop.bat
echo ============================================
pause
