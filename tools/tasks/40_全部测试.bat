@echo off
rem 跑 tests 目录下所有 *.tscn，逐个汇总结果
rem
rem 判定规则：退出码为 0、出现 PASS、且没有脚本/引擎错误才算过。
rem   —— 只靠退出码不够：脚本解析失败时场景照样会跑，进程会挂住或退出码为 0。
rem --quit-after 是超时保险：测试脚本写错导致不 quit 时，最多跑 2 万帧就强制结束。
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
set "TMPOUT=%TEMP%\lightgame_test_out.txt"
set /a TOTAL=0
set /a FAIL=0
for %%T in ("%GODOT_PROJECT%\tests\*.tscn") do (
    set "REL=%%~nxT"
    set /a TOTAL+=1
    echo.
    echo   === 测试 !REL! ===
    "%GODOT_CONSOLE_EXE%" --headless --quit-after 60000 --path "%GODOT_PROJECT%" "res://tests/!REL!" > "!TMPOUT!" 2>&1
    set "TEST_EXIT=!ERRORLEVEL!"
    type "!TMPOUT!"
    set "TEST_FAILED=0"
    if not "!TEST_EXIT!"=="0" set "TEST_FAILED=1"
    findstr /c:"TEST RESULT: PASS" "!TMPOUT!" >nul
    if errorlevel 1 set "TEST_FAILED=1"
    findstr /c:"SCRIPT ERROR:" /b /c:"ERROR:" "!TMPOUT!" >nul
    if not errorlevel 1 set "TEST_FAILED=1"
    if "!TEST_FAILED!"=="1" (
        set /a FAIL+=1
        echo   [FAIL] !REL!  ^(退出码异常、缺少 PASS 或存在运行错误^)
    ) else (
        echo   [PASS] !REL!
    )
)
del "!TMPOUT!" >nul 2>&1
echo.
echo   共 !TOTAL! 个测试，失败 !FAIL! 个
if not defined DEV_MENU pause
if !FAIL! GTR 0 exit /b 1
exit /b 0
