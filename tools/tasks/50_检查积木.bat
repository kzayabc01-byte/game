@echo off
rem 扫描 blocks\ 下所有积木：根节点类型、碰撞层、脚本、命名规范
chcp 65001 >nul
setlocal EnableExtensions
call "%~dp0..\godot.bat" env >nul
if errorlevel 1 (
    echo   找不到 Godot，无法检查。
    if not defined DEV_MENU pause
    exit /b 1
)
echo.
"%GODOT_CONSOLE_EXE%" --headless --path "%GODOT_PROJECT%" --script res://tools/lint_blocks.gd
set "RC=%ERRORLEVEL%"
if not defined DEV_MENU pause
exit /b %RC%
