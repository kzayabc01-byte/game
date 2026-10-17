@echo off
rem 手动指定本机 Godot 路径：只问一次，写进 tools\godot_path.cfg（不提交 git）
chcp 65001 >nul
setlocal EnableExtensions
set "TOOLS=%~dp0.."

echo.
echo   ==========================================================
echo     设置 Godot 路径
echo   ==========================================================
echo.
echo     把 Godot 的 exe（或它所在的文件夹）拖进本窗口，然后回车。
echo     例：D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
echo     直接回车 = 取消
echo.
set "P="
set /p "P=  Godot 路径> "
if not defined P (
    echo.
    echo   已取消。
    if not defined DEV_MENU pause
    exit /b 1
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\resolve_godot.ps1" -Set "%P%" -ProjectDir "%~dp0..\.."
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo   设置成功。以后直接双击 启动游戏.bat 就行。
) else (
    echo   设置失败：请确认路径指向 Godot 的 exe，或它所在的文件夹。
)
if not defined DEV_MENU pause
exit /b %RC%
