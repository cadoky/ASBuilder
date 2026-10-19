@echo off
rem ASBuilder: rebuilds Data.lua and Names.lua from AzerothSurvivors.exe after a game update.
rem Double-click it. It only reads the game; it changes nothing there.
setlocal
cd /d "%~dp0"
set "PY="
if exist "..\..\..\.coop-runtime\python.exe" set "PY=..\..\..\.coop-runtime\python.exe"
if not defined PY (
  where python >nul 2>nul && set "PY=python"
)
if not defined PY (
  where py >nul 2>nul && set "PY=py -3"
)
if not defined PY (
  echo Python was not found. Install Python 3 from python.org, or run this from a game folder
  echo that has the co-op's .coop-runtime folder.
  pause
  exit /b 1
)
%PY% -I extract.py %*
echo.
pause
