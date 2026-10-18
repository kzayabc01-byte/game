@echo off
rem 从 blocks\_template 生成一个新积木（机关类），自动填好类名、场景、脚本
chcp 65001 >nul
setlocal EnableExtensions
set "TOOLS=%~dp0.."
set "NAME=%~1"

if not defined NAME (
    echo.
    echo   新积木名（英文小写 + 下划线，如 rotating_mirror）：
    set /p "NAME=  > "
)
if not defined NAME (
    echo   已取消。
    if not defined DEV_MENU pause
    exit /b 1
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\new_block.ps1" -Name "%NAME%" -ProjectDir "%~dp0..\.."
set "RC=%ERRORLEVEL%"
echo.
if not defined DEV_MENU pause
exit /b %RC%
