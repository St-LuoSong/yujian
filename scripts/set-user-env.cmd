@echo off
REM ============================================================
REM  YuJianZhiLv - install permanent USER level environment
REM
REM  Writes only to HKCU\Environment, so no administrator rights
REM  are required. A .reg backup of the previous state is written
REM  to scripts\user-env-backup.reg before anything is changed.
REM
REM  PATH handling is append-only: an entry is added only when it
REM  is not already present. The machine level PATH is untouched
REM  and existing user PATH entries are preserved in order.
REM
REM  Usage:  scripts\set-user-env.cmd
REM  Then open a NEW cmd window so the values take effect.
REM ============================================================
setlocal EnableDelayedExpansion

set "PROJECT_ROOT=%~dp0.."
for %%I in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fI"

set "BACKUP_FILE=%~dp0user-env-backup.reg"

set "V_JAVA_HOME=C:\Program Files\Java\jdk-17"
set "V_FLUTTER_HOME=%PROJECT_ROOT%\tooling\flutter"
set "V_ANDROID_SDK_ROOT=%PROJECT_ROOT%\tooling\android-sdk"
set "V_ANDROID_HOME=%PROJECT_ROOT%\tooling\android-sdk"
set "V_GRADLE_USER_HOME=%PROJECT_ROOT%\tooling\.gradle"
set "V_ANDROID_USER_HOME=%PROJECT_ROOT%\tooling\.android"
set "V_PUB_CACHE=%PROJECT_ROOT%\tooling\.pub-cache"
set "V_PUB_HOSTED_URL=https://pub.flutter-io.cn"
set "V_FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"

echo === 1. Backing up HKCU\Environment ===
reg export "HKCU\Environment" "%BACKUP_FILE%" /y >nul 2>&1
if errorlevel 1 (
    echo    [warn] could not export backup, continuing anyway
    echo           backup target was: %BACKUP_FILE%
) else (
    echo    saved: %BACKUP_FILE%
)

echo.
echo === 2. Writing scalar variables ===
call :putValue JAVA_HOME "%V_JAVA_HOME%"
call :putValue FLUTTER_HOME "%V_FLUTTER_HOME%"
call :putValue ANDROID_SDK_ROOT "%V_ANDROID_SDK_ROOT%"
call :putValue ANDROID_HOME "%V_ANDROID_HOME%"
call :putValue GRADLE_USER_HOME "%V_GRADLE_USER_HOME%"
call :putValue ANDROID_USER_HOME "%V_ANDROID_USER_HOME%"
call :putValue PUB_CACHE "%V_PUB_CACHE%"
call :putValue PUB_HOSTED_URL "%V_PUB_HOSTED_URL%"
call :putValue FLUTTER_STORAGE_BASE_URL "%V_FLUTTER_STORAGE_BASE_URL%"

echo.
echo === 3. Merging PATH (append only) ===
call :readUserPath
if errorlevel 1 goto :fail
echo    current: %USER_PATH%

set "NEW_PATH=%USER_PATH%"
set "ENTRY=%V_JAVA_HOME%\bin"
call :appendPath
set "ENTRY=%V_FLUTTER_HOME%\bin"
call :appendPath
set "ENTRY=%V_ANDROID_SDK_ROOT%\cmdline-tools\latest\bin"
call :appendPath
set "ENTRY=%V_ANDROID_SDK_ROOT%\platform-tools"
call :appendPath

if "%NEW_PATH%"=="%USER_PATH%" (
    echo    no change needed
) else (
    reg add "HKCU\Environment" /v Path /t REG_EXPAND_SZ /d "%NEW_PATH%" /f >nul
    if errorlevel 1 (
        echo    *** failed to write PATH ***
        goto :fail
    )
    echo    updated: %NEW_PATH%
)

echo.
echo === 4. Installing the environment level Gradle init script ===
if not exist "%V_GRADLE_USER_HOME%\init.d" mkdir "%V_GRADLE_USER_HOME%\init.d" >nul 2>&1
copy /y "%~dp0gradle\alimaven-google.init.gradle" "%V_GRADLE_USER_HOME%\init.d\alimaven-google.init.gradle" >nul
if errorlevel 1 (
    echo    *** failed to install the Gradle init script ***
    goto :fail
)
echo    installed: %V_GRADLE_USER_HOME%\init.d\alimaven-google.init.gradle
echo.
echo === Done. Open a NEW cmd window, then run: flutter doctor -v ===
exit /b 0

:putValue
set "NAME=%~1"
set "VALUE=%~2"
reg add "HKCU\Environment" /v "%NAME%" /t REG_EXPAND_SZ /d "%VALUE%" /f >nul
if errorlevel 1 (
    echo    [fail] %NAME%
) else (
    echo    [ ok ] %NAME% = %VALUE%
)
exit /b 0

:readUserPath
REM Guard: never rebuild PATH when the registry key cannot be read,
REM otherwise a transient failure would silently drop existing entries.
reg query "HKCU\Environment" >nul 2>&1
if errorlevel 1 (
    echo    *** cannot read HKCU\Environment - aborting without changes ***
    exit /b 1
)
set "USER_PATH="
for /f "skip=2 tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"
exit /b 0

:appendPath
if "!ENTRY!"=="" exit /b 0
set "PROBE=;!NEW_PATH!;"
if not "!PROBE:;%ENTRY%;=!"=="!PROBE!" (
    echo    [keep] %ENTRY%
    exit /b 0
)
if "!NEW_PATH!"=="" (
    set "NEW_PATH=%ENTRY%"
) else (
    set "NEW_PATH=!NEW_PATH!;%ENTRY%"
)
echo    [add ] %ENTRY%
exit /b 0

:fail
echo.
echo *** ENVIRONMENT SETUP FAILED ***
exit /b 1
