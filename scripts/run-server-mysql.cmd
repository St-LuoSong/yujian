@echo off
rem ---------------------------------------------------------------------------
rem Local launcher: Spring Boot against MySQL 8 instead of the embedded H2 file.
rem
rem Prerequisite (once): the yujian_travel database and the yujian account must
rem already exist.
rem
rem   default, docker compose on 3306:
rem     docker compose up -d mysql
rem     (the mysql image already creates the database and the yujian account)
rem   any other MySQL 8, e.g. a native install on a different port:
rem     set MYSQL_PORT=3307 ^& scripts\init-mysql.cmd
rem   then run this script.
rem
rem Usage: scripts\run-server-mysql.cmd
rem
rem Override anything through scripts\local.env (git-ignored), which is applied
rem after the defaults below and therefore wins: MYSQL_HOST / MYSQL_PORT /
rem MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD / MYSQL_URL.
rem
rem Note: keep this file ASCII-only. cmd.exe reads it with the OEM code page,
rem so non-ASCII comments can be mis-parsed as commands.
rem ---------------------------------------------------------------------------
call "%~dp0..\toolchain.cmd" >nul
cd /d "%~dp0..\backend\server"

rem prod profile = MySQL datasource (see application-prod.yml).
set "SPRING_PROFILES_ACTIVE=prod"
set "ADMIN_USERNAME=operator"
set "ADMIN_PASSWORD=Operator12345"
set "ADMIN_EMAIL=operator@yujian.local"

rem Defaults mirror docker-compose.yml, so both paths end up with the same
rem database name and the same dev account.
if not defined MYSQL_HOST set "MYSQL_HOST=127.0.0.1"
if not defined MYSQL_PORT set "MYSQL_PORT=3306"
if not defined MYSQL_DATABASE set "MYSQL_DATABASE=yujian_travel"
if not defined MYSQL_USER set "MYSQL_USER=yujian"
if not defined MYSQL_PASSWORD set "MYSQL_PASSWORD=yujian_dev_password"

rem Only non-empty values are applied, so leaving a key blank in local.env
rem falls back to a real environment variable instead of erasing it.
if exist "%~dp0local.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0local.env") do (
    if not "%%B"=="" set "%%A=%%B"
  )
)

rem Built last so that a MYSQL_PORT/MYSQL_HOST set in local.env is honoured.
if not defined MYSQL_URL set "MYSQL_URL=jdbc:mysql://%MYSQL_HOST%:%MYSQL_PORT%/%MYSQL_DATABASE%?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai&allowPublicKeyRetrieval=true&useSSL=false"

netstat -an | findstr /r /c:":%MYSQL_PORT% .*LISTENING" >nul 2>nul
if errorlevel 1 echo [mysql-server] WARN: nothing seems to listen on port %MYSQL_PORT% - start MySQL first.

if defined BAIDU_MAP_AK (echo [mysql-server] baidu map ak: configured) else (echo [mysql-server] baidu map ak: not configured - routes will be marked degraded)
if defined RAILWAY_MCP_URL (echo [mysql-server] railway mcp: %RAILWAY_MCP_URL%) else (echo [mysql-server] railway mcp: not set - using reference timetable)
echo [mysql-server] admin=%ADMIN_USERNAME% profile=prod db=mysql target=%MYSQL_HOST%:%MYSQL_PORT%/%MYSQL_DATABASE%
echo [mysql-server] note: the H2 file database is a different store - existing H2 data is NOT migrated automatically.
mvn -o -q spring-boot:run
