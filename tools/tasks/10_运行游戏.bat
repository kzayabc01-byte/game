@echo off
rem 启动游戏（主菜单 -> 关卡）
chcp 65001 >nul
call "%~dp0..\godot.bat" game
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo   启动失败，退出码 %RC%
    if not defined DEV_MENU pause
)
exit /b %RC%
