@echo off
rem 跑 tests 目录下所有 *.tscn，逐个汇总结果
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0..\godot.bat" env >nul
if errorlevel 1 (
    echo   找不到 Godot，无法运行测试。
    if not defined DEV_MENU pause
    exit /b 1
)
if not exist "%GODOT_PROJECT%\tests\*.tscn" (
    echo   tests 目录里没有测试场景。
    if not defined DEV_MENU pause
    exit /b 0
)
set /a TOTAL=0
set /a FAIL=0
for %%T in ("%GODOT_PROJECT%\tests\*.tscn") do (
    set "REL=%%~nxT"
    set /a TOTAL+=1
    echo.
    echo   === 测试 !REL! ===
    "%GODOT_CONSOLE_EXE%" --headless --path "%GODOT_PROJECT%" "res://tests/!REL!"
    if errorlevel 1 (
        set /a FAIL+=1
        echo   [FAIL] !REL!
    ) else (
        echo   [PASS] !REL!
    )
)
echo.
echo   共 !TOTAL! 个测试，失败 !FAIL! 个
if not defined DEV_MENU pause
if !FAIL! GTR 0 exit /b 1
exit /b 0
