@echo off
setlocal
chcp 65001 >nul
title ShinePick Server - Status

set "API_PORT=8080"
set "MYSQL_PORT=3306"
set "MYSQL_ROOT_PASSWORD=123456"

echo ---- MySQL ----
"%~dp0mysql\bin\mysqladmin.exe" -P %MYSQL_PORT% --protocol=tcp ping 2>&1 | findstr /i alive
if errorlevel 1 echo [stopped]

echo ---- Redis ----
"%~dp0redis\redis-cli.exe" -p 6379 ping 2>&1

echo ---- API ----
curl -s -m 5 http://127.0.0.1:%API_PORT%/ping
echo.
echo.
pause
