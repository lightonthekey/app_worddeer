@echo off
chcp 65001 >nul
cd /d %~dp0

REM 本机 127.0.0.1:9893 有代理，会劫持 Flutter 的调试连接，先清掉
set http_proxy=
set https_proxy=
set HTTP_PROXY=
set HTTPS_PROXY=
set no_proxy=localhost,127.0.0.1,::1

echo 桌面预览（手机比例窗口 430x900）：改完代码按 r 热重载，q 退出
flutter run -d windows --debug
pause
