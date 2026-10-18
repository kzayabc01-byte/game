@echo off
rem ============================================================
rem  光线游戏 · Godot 统一入口
rem
rem  用法（一般不用手敲，任务脚本会 call 它）：
rem    godot.bat game            启动游戏
rem    godot.bat editor          打开编辑器
rem    godot.bat test <场景>     无头跑一个测试场景（有控制台输出）
rem    godot.bat env             只解析路径，把 GODOT_* 变量交给调用者
rem    godot.bat version         打印 Godot 版本
rem    godot.bat check           打印解析结果（排查用）
rem
rem  找路径的逻辑全在 tools\resolve_godot.ps1 里，这里只负责拼参数。
rem  想手动指定 Godot：双击 tools\tasks\05_设置Godot路径.bat，
rem  或者设置环境变量 GODOT。不需要改任何脚本。
rem ============================================================
chcp 65001 >nul
setlocal EnableExtensions
set "TOOLS=%~dp0"
set "PROJ=%~dp0.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%resolve_godot.ps1" -ProjectDir "%PROJ%"
if errorlevel 1 (
    echo.
    echo   没找到可用的 Godot，无法继续。
    echo   解决办法：双击 tools\tasks\05_设置Godot路径.bat，把 Godot 的 exe 拖进去。
    echo.
    exit /b 1
)
call "%TOOLS%.cache\env.cmd"

set "MODE=%~1"
if /i "%MODE%"=="game"    goto :mode_game
if /i "%MODE%"=="editor"  goto :mode_editor
if /i "%MODE%"=="test"    goto :mode_test
if /i "%MODE%"=="env"     goto :mode_env
if /i "%MODE%"=="version" goto :mode_version
if /i "%MODE%"=="check"   goto :mode_check
goto :usage

:mode_game
start "" "%GODOT_EXE%" --path "%GODOT_PROJECT%" %2 %3 %4 %5 %6 %7 %8 %9
exit /b 0

:mode_editor
start "" "%GODOT_EXE%" --editor --path "%GODOT_PROJECT%" %2 %3 %4 %5 %6 %7 %8 %9
exit /b 0

:mode_test
set "SCENE=%~2"
if "%SCENE%"=="" (
    echo   用法: godot.bat test res://tests/xxx.tscn
    exit /b 2
)
"%GODOT_CONSOLE_EXE%" --headless --path "%GODOT_PROJECT%" "%SCENE%"
exit /b %ERRORLEVEL%

:mode_version
"%GODOT_CONSOLE_EXE%" --version
exit /b %ERRORLEVEL%

:mode_env
rem 把解析结果传给调用者（endlocal 之后在同一行 set，才能把值带出 setlocal 作用域）
endlocal & set "GODOT_EXE=%GODOT_EXE%" & set "GODOT_CONSOLE_EXE=%GODOT_CONSOLE_EXE%" & set "GODOT_VERSION=%GODOT_VERSION%" & set "GODOT_PROJECT=%GODOT_PROJECT%" & set "GODOT_FOUND_BY=%GODOT_FOUND_BY%"
exit /b 0

:mode_check
echo   GODOT_EXE         = %GODOT_EXE%
echo   GODOT_CONSOLE_EXE = %GODOT_CONSOLE_EXE%
echo   GODOT_VERSION     = %GODOT_VERSION%
echo   GODOT_PROJECT     = %GODOT_PROJECT%
echo   GODOT_FOUND_BY    = %GODOT_FOUND_BY%
exit /b 0

:usage
echo.
echo   用法: godot.bat game^|editor^|test ^<场景^>^|env^|version^|check
echo.
if "%~1"=="" pause
exit /b 2
