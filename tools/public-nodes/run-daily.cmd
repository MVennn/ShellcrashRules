@echo off
setlocal
cd /d "%~dp0..\.."
if not exist ".work\public-nodes" mkdir ".work\public-nodes"
rem 无人值守会跑很久：task.log 超过 1MB 就轮转一份，避免无限增长
if exist ".work\public-nodes\task.log" (
  for %%A in (".work\public-nodes\task.log") do if %%~zA GTR 1048576 move /y ".work\public-nodes\task.log" ".work\public-nodes\task.log.1" >nul
)
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
python -X utf8 "tools\public-nodes\screen.py" >> ".work\public-nodes\task.log" 2>&1
exit /b %ERRORLEVEL%
