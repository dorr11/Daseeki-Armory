@echo off
REM Run the Daseeki-Armory headless stat-formula self-tests under real Lua 5.1.
REM Uses the vendored Lua 5.1 shipped with nexus-test-harness (a sibling repo).
REM Usage: run-selftests.cmd [ARMORY_DIR]
setlocal
set HERE=%~dp0
REM DASEEKI_LUA51 overrides the search when the repo is checked out somewhere the
REM sibling layout does not hold (a git worktree under %TEMP%, for instance) -- an
REM agent running the gates from a worktree needs a way to point at the interpreter.
REM Mirrors Daseeki-Bags/harness/run-selftests.cmd.
set LUA=%DASEEKI_LUA51%
if "%LUA%"=="" set LUA=%HERE%..\..\nexus-test-harness\lua51\lua5.1.exe
if not exist "%LUA%" set LUA=%HERE%..\..\..\nexus-test-harness\lua51\lua5.1.exe
if not exist "%LUA%" (
  echo [FAIL] cannot find the vendored Lua 5.1 interpreter.
  echo        Looked beside the repo for nexus-test-harness\lua51\lua5.1.exe.
  echo        Set DASEEKI_LUA51 to its full path and re-run.
  exit /b 4
)
set ARMORY=%~1
if "%ARMORY%"=="" set ARMORY=%HERE%..
"%LUA%" "%HERE%run-selftests.lua" "%ARMORY%"
exit /b %ERRORLEVEL%
