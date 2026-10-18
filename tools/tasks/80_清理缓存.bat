@echo off
rem 删除导入缓存（.godot）和路径缓存，解决“改了资源没生效”
chcp 65001 >nul
setlocal EnableExtensions
set "PROJ=%~dp0..\.."
set "TOOLS=%~dp0.."
echo.
if exist "%PROJ%\.godot" (
    rd /s /q "%PROJ%\.godot"
    echo   已删除 .godot 导入缓存
) else (
    echo   .godot 缓存本来就不存在
)
if exist "%TOOLS%\.cache" (
    rd /s /q "%TOOLS%\.cache"
    echo   已删除路径缓存（下次启动会重新探测 Godot）
)
echo.
echo   清理完成。
if not defined DEV_MENU pause
exit /b 0
