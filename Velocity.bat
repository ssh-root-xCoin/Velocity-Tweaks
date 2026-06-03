@echo off
title Velocity - Windows Performance Toolkit
cd /d "%~dp0"

:: Velocity launcher. Elevates, then runs the GUI under Windows PowerShell in STA
:: mode (required for WPF). The .ps1 also self-elevates as a safety net.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "PS1=%~dp0Velocity.ps1"
if not exist "%PS1%" (
    echo ERROR: Velocity.ps1 was not found next to this launcher.
    pause
    exit /b 1
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%PS1%"
