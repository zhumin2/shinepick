@echo off
setlocal
chcp 65001 >nul
title ShinePick Server Setup

rem ====== config (edit if needed) ======
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "MYSQL_PORT=3306"
set "REDIS_PORT=6379"
set "API_PORT=8080"
set "MYSQL_ROOT_PASSWORD=123456"

echo ============================================
echo   ShinePick Server Setup
echo   Dir:   %ROOT%
echo   MySQL:%MYSQL_PORT%  Redis:%REDIS_PORT%  API:%API_PORT%
echo ============================================

rem ---- 1. generate my.ini (forward slashes: mysql eats backslash escapes) ----
set "ROOT_FWD=%ROOT:\=/%"
> "%ROOT%\my.ini" echo [mysqld]
>>"%ROOT%\my.ini" echo basedir=%ROOT_FWD%/mysql
>>"%ROOT%\my.ini" echo datadir=%ROOT_FWD%/mysql/data
>>"%ROOT%\my.ini" echo port=%MYSQL_PORT%
>>"%ROOT%\my.ini" echo character-set-server=utf8mb4
>>"%ROOT%\my.ini" echo collation-server=utf8mb4_unicode_ci
>>"%ROOT%\my.ini" echo default-authentication-plugin=mysql_native_password
>>"%ROOT%\my.ini" echo skip-log-bin
echo [1/4] my.ini generated

rem ---- 2. init data dir (first install only) ----
if not exist "%ROOT%\mysql\data\mysql" (
  echo [2/4] Initializing MySQL data dir, please wait...
  "%ROOT%\mysql\bin\mysqld.exe" --defaults-file="%ROOT%\my.ini" --initialize-insecure --console
  if errorlevel 1 (
    echo Init FAILED. Check port usage and disk permissions.
    pause
    exit /b 1
  )
) else (
  echo [2/4] Data dir exists, skip init
)

rem ---- 3. start mysql, set password, create db ----
echo [3/4] Starting MySQL ...
start "ShinepickMySQL" /min "%ROOT%\mysql\bin\mysqld.exe" --defaults-file="%ROOT%\my.ini" --console
set /a TRIES=0
:waitmysql
set /a TRIES+=1
if %TRIES% GTR 30 (
  echo MySQL start TIMEOUT. Check the MySQL window log.
  pause
  exit /b 1
)
"%ROOT%\mysql\bin\mysqladmin.exe" -P %MYSQL_PORT% --protocol=tcp ping >nul 2>&1
if errorlevel 1 (
  ping -n 2 127.0.0.1 >nul
  goto waitmysql
)

"%ROOT%\mysql\bin\mysql.exe" -P %MYSQL_PORT% --protocol=tcp -u root --skip-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '%MYSQL_ROOT_PASSWORD%';" >nul 2>&1
"%ROOT%\mysql\bin\mysql.exe" -P %MYSQL_PORT% --protocol=tcp -u root -p%MYSQL_ROOT_PASSWORD% -e "CREATE DATABASE IF NOT EXISTS shinepick CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; FLUSH PRIVILEGES;" 2>nul
if errorlevel 1 (
  echo Create DB FAILED: check root password is %MYSQL_ROOT_PASSWORD% - edit config at top.
  pause
  exit /b 1
)

rem ---- 4. run migrations (first install only) ----
"%ROOT%\mysql\bin\mysql.exe" -P %MYSQL_PORT% --protocol=tcp -u root -p%MYSQL_ROOT_PASSWORD% -e "USE shinepick; SHOW TABLES LIKE 'users';" 2>nul | findstr /i users >nul
if errorlevel 1 (
  echo [4/4] Running migrations ...
  for %%F in ("%ROOT%\migrations\0*.sql") do (
    echo %%~nxF | findstr /i rollback >nul
    if not errorlevel 1 (
      echo   - %%~nxF skipped
    ) else (
      echo   - %%~nxF
      "%ROOT%\mysql\bin\mysql.exe" --default-character-set=utf8mb4 -P %MYSQL_PORT% --protocol=tcp -u root -p%MYSQL_ROOT_PASSWORD% shinepick < "%%F"
      if errorlevel 1 (
        echo Migration FAILED: %%~nxF
        pause
        exit /b 1
      )
    )
  )
) else (
  echo [4/4] DB already initialized, skip migrations
)

if not exist "%ROOT%\uploads\avatars" mkdir "%ROOT%\uploads\avatars"
if not exist "%ROOT%\uploads\images" mkdir "%ROOT%\uploads\images"
if not exist "%ROOT%\uploads\web" mkdir "%ROOT%\uploads\web"

echo.
echo ============================================
echo   Setup DONE. Run start.bat to launch.
echo   Web: http://127.0.0.1:%API_PORT%/static/web/
echo   Health: http://127.0.0.1:%API_PORT%/ping
echo ============================================
pause
