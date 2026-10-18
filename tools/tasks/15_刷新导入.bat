@echo off
rem 刷新导入与全局类缓存
rem 新增/改名带 class_name 的脚本后跑一次，否则无头运行会报 Could not find type "XXX"
chcp 65001 >nul
setlocal EnableExtensions
call "%~dp0..\godot.bat" env >nul
if errorlevel 1 (
    echo   找不到 Godot。
    if not defined DEV_MENU pause
    exit /b 1
)
echo.
echo   正在刷新导入与全局类缓存……
"%GODOT_CONSOLE_EXE%" --headless --path "%GODOT_PROJECT%" --import
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo   完成：.godot 导入缓存与全局类缓存已更新。
) else (
    echo   刷新失败，退出码 %RC%
)
if not defined DEV_MENU pause
exit /b %RC%
