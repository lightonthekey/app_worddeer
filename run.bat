@echo off
chcp 65001 >nul
cd /d %~dp0

REM 本机 127.0.0.1:9893 有代理，会劫持 Flutter 的 VM Service，先清掉
set http_proxy=
set https_proxy=
set HTTP_PROXY=
set HTTPS_PROXY=
set no_proxy=localhost,127.0.0.1,::1

echo [1/2] 检查模拟器...
"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" devices

echo.
echo [2/2] flutter run（热重载：改完代码按 r 重新载入，按 q 退出）
flutter run -d emulator-5554 --debug
pause
