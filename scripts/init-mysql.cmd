@echo off
rem ---------------------------------------------------------------------------
rem Create the yujian_travel database + yujian account on a MySQL 8 server.
rem Works both for a native MySQL install (default 127.0.0.1:3306) and for the
rem docker-compose database, which only differs by host/port.
rem
rem Idempotent: re-running never drops data. It only needs the root account
rem once; the application itself connects as the unprivileged 'yujian' user.
rem
rem Usage:
rem   scripts\init-mysql.cmd                    (prompts for the root password)
rem   set MYSQL_PORT=3307 ^& scripts\init-mysql.cmd   (docker-compose database)
rem   scripts\init-mysql.cmd <root-password>    (non-interactive; the password
rem                                              ends up in the cmd history)
rem
rem Optional overrides: MYSQL_HOST / MYSQL_PORT / MYSQL_ROOT_USER
rem Note: keep this file ASCII-only. cmd.exe reads it with the OEM code page,
rem so non-ASCII text here can be mis-parsed as commands.
rem ---------------------------------------------------------------------------
setlocal
set "SQL_FILE=%~dp0init-mysql.sql"
if not defined MYSQL_HOST set "MYSQL_HOST=127.0.0.1"
if not defined MYSQL_PORT set "MYSQL_PORT=3306"
if not defined MYSQL_ROOT_USER set "MYSQL_ROOT_USER=root"

where mysql >nul 2>nul
if errorlevel 1 (
  echo [init-mysql] ERROR: mysql client not found on PATH.
  echo [init-mysql] Add "C:\Program Files\MySQL\MySQL Server 8.2\bin" to PATH,
  echo [init-mysql] or use the container database:
  echo [init-mysql]   set MYSQL_PORT=3307 ^& docker compose up -d mysql
  exit /b 1
)

if not exist "%SQL_FILE%" (
  echo [init-mysql] ERROR: missing %SQL_FILE%
  exit /b 1
)

echo [init-mysql] target=%MYSQL_HOST%:%MYSQL_PORT% admin=%MYSQL_ROOT_USER%
echo [init-mysql] creating database yujian_travel and user yujian ...

rem -p prompts for the password; -p<value> takes it from the argument.
rem Built as a variable so that "if errorlevel" stays directly after mysql.
set "PWD_ARG=-p"
if not "%~1"=="" set "PWD_ARG=-p%~1"
mysql --default-character-set=utf8mb4 -h %MYSQL_HOST% -P %MYSQL_PORT% -u %MYSQL_ROOT_USER% %PWD_ARG% < "%SQL_FILE%"
if errorlevel 1 (
  echo [init-mysql] FAILED. Check that MySQL is running and the root password is correct.
  exit /b 1
)
echo [init-mysql] done. Next: scripts\run-server-mysql.cmd
endlocal
