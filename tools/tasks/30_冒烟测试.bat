@echo off
rem 无头跑 tests\smoke_test.tscn：验证 level_01 的完整通关链路
chcp 65001 >nul
call "%~dp0..\godot.bat" test res://tests/smoke_test.tscn
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo   [PASS] 冒烟测试通过
) else (
    echo   [FAIL] 冒烟测试失败，退出码 %RC%
)
if not defined DEV_MENU pause
exit /b %RC%
