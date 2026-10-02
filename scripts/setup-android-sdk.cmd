@echo off
REM ============================================================
REM  YuJianZhiLv - Android SDK component installer (one-off)
REM
REM  Installs the Android SDK packages required to build the
REM  Flutter APK into the project local SDK at .\tooling\android-sdk.
REM
REM  Requirements matched to this project:
REM      Flutter 3.47.5  ->  compileSdk / targetSdk 36
REM      AGP 9.1.0       ->  JDK 17
REM
REM  Usage:  scripts\setup-android-sdk.cmd
REM  Safe to re-run; sdkmanager skips already installed packages.
REM ============================================================
setlocal

set "PROJECT_ROOT=%~dp0.."
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "ANDROID_SDK_ROOT=%PROJECT_ROOT%\tooling\android-sdk"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "SDKMANAGER=%ANDROID_SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"

echo [1/3] JDK in use:
"%JAVA_HOME%\bin\java" -version
if errorlevel 1 goto :fail

echo.
echo [2/3] Accepting SDK licenses...
REM Non interactive: feed a stream of "y" so the script can run unattended and
REM still works on a machine where the licenses were never accepted before.
(for /l %%i in (1,1,100) do @echo y) | call "%SDKMANAGER%" --sdk_root="%ANDROID_SDK_ROOT%" --licenses >nul
if errorlevel 1 goto :fail
echo       licenses accepted

echo.
echo [3/3] Installing SDK packages...
call "%SDKMANAGER%" --sdk_root="%ANDROID_SDK_ROOT%" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
if errorlevel 1 goto :fail

echo.
echo === Installed packages ===
call "%SDKMANAGER%" --sdk_root="%ANDROID_SDK_ROOT%" --list_installed
exit /b 0

:fail
echo.
echo *** INSTALL FAILED - check network connectivity and messages above ***
exit /b 1
