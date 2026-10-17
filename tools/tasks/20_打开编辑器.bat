@echo off
rem 用 Godot 编辑器打开本工程（改场景、拼关卡、写代码）
chcp 65001 >nul
call "%~dp0..\godot.bat" editor
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo   打开编辑器失败，退出码 %RC%
    if not defined DEV_MENU pause
)
exit /b %RC%
