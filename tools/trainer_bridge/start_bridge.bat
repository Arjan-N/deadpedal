@echo off
rem DEAD PEDAL trainer bridge - double-click to connect your smart trainer.
rem First run installs the Bluetooth library (needs internet, ~1 minute).
cd /d "%~dp0"
title DEAD PEDAL trainer bridge

set PY=
where py >nul 2>nul && set PY=py -3
if not defined PY where python >nul 2>nul && set PY=python
if not defined PY (
    echo Python 3 was not found.
    echo Install it from https://www.python.org/downloads/ and tick
    echo "Add python.exe to PATH" during installation, then run this again.
    pause
    exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
    echo Setting up for the first time...
    %PY% -m venv .venv || goto :error
)
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q bleak || goto :error
".venv\Scripts\python.exe" trainer_bridge.py %*
pause
exit /b 0

:error
echo Setup failed - see the message above.
pause
exit /b 1
