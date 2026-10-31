@echo off
setlocal
chcp 65001 >nul
title ShinePick Server - Stop

set "MYSQL_PORT=3306"

echo Stopping API ...
taskkill /im shinepick-api.exe /f >nul 2>&1

echo Stopping Redis ...
taskkill /im redis-server.exe /f >nul 2>&1

echo Stopping MySQL gracefully ...
"%~dp0mysql\bin\mysqladmin.exe" -P %MYSQL_PORT% --protocol=tcp -u root -p123456 shutdown >nul 2>&1
if errorlevel 1 taskkill /im mysqld.exe /f >nul 2>&1

echo.
echo All services stopped.
ping -n 3 127.0.0.1 >nul
