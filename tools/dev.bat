@echo off
rem ============================================================
rem  光线游戏 · 开发菜单
rem
rem  * 菜单里有多少项 = tools\tasks\ 下有多少个 NN_xxx.bat
rem  * 新增一个工具：把 NN_名字.bat 丢进 tools\tasks\ 即可，
rem    不用改这个文件、也不用改任何清单。
rem  * 双击运行本文件进入菜单；命令行 dev.bat 30 可直接执行 30 号任务，
rem    dev.bat 90 my_block 会把 my_block 作为参数传给任务。
rem ============================================================
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
set "TOOLS=%~dp0"
set "TASKDIR=%~dp0tasks"

if not "%~1"=="" goto :direct

call "%TOOLS%godot.bat" env >nul 2>&1
if errorlevel 1 set "GODOT_VERSION="

:menu
cls
echo ============================================================
echo    光线游戏 · 开发菜单
if defined GODOT_VERSION (
    echo    Godot !GODOT_VERSION!   ^(来源: !GODOT_FOUND_BY!^)
) else (
    echo    Godot 未找到  ^-^-^>  请先选 05 设置一次
)
echo ============================================================
echo.
for /f "delims=" %%F in ('dir /b /on "%TASKDIR%\*.bat" 2^>nul') do (
    set "LBL=%%~nF"
    echo       !LBL:~0,2!. !LBL:~3!
)
echo.
echo       0. 退出
echo.
set "PICK="
set /p "PICK=    请输入编号 > "
if not defined PICK goto :menu
if "!PICK!"=="0" exit /b 0
goto :run

:run
set "TARGET="
for /f "delims=" %%F in ('dir /b /on "%TASKDIR%\!PICK!_*.bat" 2^>nul') do (
    if not defined TARGET set "TARGET=%%F"
)
if not defined TARGET (
    echo.
    echo    没有编号 "!PICK!" 的任务。
    timeout /t 2 >nul
    goto :menu
)
set "DEV_MENU=1"
echo.
call "%TASKDIR%\!TARGET!"
echo.
pause
goto :menu

:direct
set "TARGET="
for /f "delims=" %%F in ('dir /b /on "%TASKDIR%\%~1_*.bat" 2^>nul') do (
    if not defined TARGET set "TARGET=%%F"
)
if not defined TARGET (
    echo 没有编号为 %~1 的任务。
    exit /b 2
)
set "DEV_MENU=1"
call "%TASKDIR%\%TARGET%" %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%
