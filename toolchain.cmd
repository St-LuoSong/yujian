@echo off
REM ============================================================
REM  YuJianZhiLv - project scoped toolchain environment
REM
REM  Usage (cmd.exe, from anywhere):
REM      call D:\DESKTOP\ProWeb\toolchain.cmd
REM      flutter build apk --release
REM
REM  This file only affects the CURRENT cmd session.
REM  Permanent user level variables are installed once by
REM      scripts\set-user-env.cmd
REM ============================================================

set "PROJECT_ROOT=%~dp0"
if "%PROJECT_ROOT:~-1%"=="\" set "PROJECT_ROOT=%PROJECT_ROOT:~0,-1%"

set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "FLUTTER_HOME=%PROJECT_ROOT%\tooling\flutter"
set "ANDROID_SDK_ROOT=%PROJECT_ROOT%\tooling\android-sdk"
set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
set "GRADLE_USER_HOME=%PROJECT_ROOT%\tooling\.gradle"
set "ANDROID_USER_HOME=%PROJECT_ROOT%\tooling\.android"
REM Keep the pub cache on the same drive as the project. The Kotlin incremental
REM compiler cannot relativize source paths across Windows drives, so a pub
REM cache on C: breaks plugin compilation for a project checked out on D:.
set "PUB_CACHE=%PROJECT_ROOT%\tooling\.pub-cache"
set "PATH=%JAVA_HOME%\bin;%FLUTTER_HOME%\bin;%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin;%ANDROID_SDK_ROOT%\platform-tools;%PATH%"

REM Keep GRADLE_USER_HOME in sync with the environment level Gradle init script
REM that redirects Google's Maven repository to a reachable mirror. Gradle only
REM auto loads init scripts from %GRADLE_USER_HOME%\init.d, so the versioned
REM source of truth is copied there. Idempotent: safe to run on every call.
if not exist "%GRADLE_USER_HOME%\init.d" mkdir "%GRADLE_USER_HOME%\init.d" >nul 2>&1
copy /y "%PROJECT_ROOT%\scripts\gradle\alimaven-google.init.gradle" "%GRADLE_USER_HOME%\init.d\alimaven-google.init.gradle" >nul 2>&1

echo [toolchain] PROJECT_ROOT      = %PROJECT_ROOT%
echo [toolchain] JAVA_HOME         = %JAVA_HOME%
echo [toolchain] FLUTTER_HOME      = %FLUTTER_HOME%
echo [toolchain] ANDROID_SDK_ROOT  = %ANDROID_SDK_ROOT%
echo [toolchain] GRADLE_USER_HOME  = %GRADLE_USER_HOME%
echo [toolchain] ANDROID_USER_HOME = %ANDROID_USER_HOME%
echo [toolchain] PUB_CACHE         = %PUB_CACHE%
echo.
echo Toolchain ready. Try:  flutter --version
