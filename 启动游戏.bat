@echo off
rem 双击直接运行游戏（主菜单 -> 关卡）。
rem
rem 不用改这里的路径：Godot 由 tools\resolve_godot.ps1 自动探测
rem （环境变量 GODOT -> tools\godot_path.cfg -> 缓存 -> PATH -> 常见目录）。
rem 想手动指定：双击 tools\tasks\05_设置Godot路径.bat，只问一次。
chcp 65001 >nul
call "%~dp0tools\godot.bat" game
if errorlevel 1 pause
exit /b %ERRORLEVEL%
git worktree list