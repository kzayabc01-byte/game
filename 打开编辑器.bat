@echo off
rem 双击用 Godot 编辑器打开本项目（改场景、拼关卡、写代码用这个）。
rem 注意要指到 .exe 文件本身，不能只写文件夹。
set "GODOT=D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" (
    echo.
    echo 找不到 Godot 可执行文件：
    echo   %GODOT%
    echo 请用记事本打开本文件，把 GODOT= 后面的路径改成你电脑上 Godot 的 .exe 完整路径。
    echo.
    pause
    exit /b 1
)

start "" "%GODOT%" --editor --path "%~dp0."
