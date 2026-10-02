@echo off
rem ---------------------------------------------------------------------------
rem Local dev/demo launcher: embedded H2 + operator account.
rem These credentials are for local demo only. Production must override the
rem ADMIN_* environment variables; never commit real secrets.
rem
rem Secrets live in scripts\local.env (git-ignored). Copy scripts\local.env.example
rem and fill in BAIDU_MAP_AK / RAILWAY_MCP_URL / LLM keys. Keeping them out of this
rem file means the launcher itself never carries a credential, and "which data
rem sources are actually configured" is answered by the startup lines below.
rem
rem Note: keep this file ASCII-only. cmd.exe reads it with the OEM code page,
rem so non-ASCII comments can be mis-parsed as commands.
rem Usage: scripts\run-server-dev.cmd
rem ---------------------------------------------------------------------------
call "%~dp0..\toolchain.cmd" >nul
cd /d "%~dp0..\backend\server"
set "ADMIN_USERNAME=operator"
set "ADMIN_PASSWORD=Operator12345"
set "ADMIN_EMAIL=operator@yujian.local"

rem Only non-empty values are applied, so leaving a key blank in local.env
rem falls back to a real environment variable instead of erasing it.
if exist "%~dp0local.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0local.env") do (
    if not "%%B"=="" set "%%A=%%B"
  )
)

if defined BAIDU_MAP_AK (echo [dev-server] baidu map ak: configured) else (echo [dev-server] baidu map ak: not configured - routes will be marked degraded)
if defined RAILWAY_MCP_URL (echo [dev-server] railway mcp: %RAILWAY_MCP_URL%) else (echo [dev-server] railway mcp: not set - using reference timetable)
echo [dev-server] admin=%ADMIN_USERNAME% profile=dev db=h2
mvn -o -q spring-boot:run

