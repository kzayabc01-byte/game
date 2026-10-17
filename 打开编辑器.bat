@echo off
rem 双击用 Godot 编辑器打开本工程（改场景、拼关卡、写代码）。
rem 路径同样不用改，逻辑见 启动游戏.bat 的说明。
chcp 65001 >nul
call "%~dp0tools\godot.bat" editor
if errorlevel 1 pause
exit /b %ERRORLEVEL%
