@echo off
REM Run the Daseeki-Armory headless stat-formula self-tests under real Lua 5.1.
REM Uses the vendored Lua 5.1 shipped with nexus-test-harness (a sibling repo).
REM Usage: run-selftests.cmd [ARMORY_DIR]
setlocal
set HERE=%~dp0
set LUA=%HERE%..\..\nexus-test-harness\lua51\lua5.1.exe
if not exist "%LUA%" set LUA=%HERE%..\..\..\nexus-test-harness\lua51\lua5.1.exe
set ARMORY=%~1
if "%ARMORY%"=="" set ARMORY=%HERE%..
"%LUA%" "%HERE%run-selftests.lua" "%ARMORY%"
exit /b %ERRORLEVEL%
