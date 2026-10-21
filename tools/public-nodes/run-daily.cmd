@echo off
setlocal
cd /d "%~dp0..\.."
if not exist ".work\public-nodes" mkdir ".work\public-nodes"
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
python -X utf8 "tools\public-nodes\screen.py" >> ".work\public-nodes\task.log" 2>&1
exit /b %ERRORLEVEL%
