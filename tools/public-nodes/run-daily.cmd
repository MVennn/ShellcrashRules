@echo off
rem Keep this file ASCII-only. Task Scheduler runs cmd.exe under the OEM code
rem page (936 here); UTF-8 Chinese comments get mis-decoded and can abort the
rem script before python starts (seen 2026-10-22: task returned 0, no output).
rem No multi-line if(...) blocks either: .gitattributes forces eol=lf and cmd
rem mis-parses LF multi-line blocks.
setlocal
cd /d "%~dp0..\.."
if not exist ".work\public-nodes" mkdir ".work\public-nodes"
rem Rotate task.log at 1MB so an unattended daily run cannot fill the disk.
if exist ".work\public-nodes\task.log" for %%A in (".work\public-nodes\task.log") do if %%~zA GTR 1048576 move /y ".work\public-nodes\task.log" ".work\public-nodes\task.log.1" >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
python -X utf8 "tools\public-nodes\screen.py" >> ".work\public-nodes\task.log" 2>&1
exit /b %ERRORLEVEL%
