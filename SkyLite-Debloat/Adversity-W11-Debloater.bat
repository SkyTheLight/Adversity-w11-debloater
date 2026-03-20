@echo off
REM ================================================================
REM Adversity Windows 11 Debloater - Performance Tweaker
REM Simple launcher - double-click to run
REM Author: SkyTheLight
REM ================================================================

setlocal enabledelayedexpansion
title Adversity W11 Debloat v1.0

echo.
echo   ====================================================
echo   Adversity W11 Debloat - Windows 11 Optimization Tool
echo   ====================================================
echo.
echo   Launching PowerShell script...
echo.

REM Run PowerShell script directly - Test-Admin inside script will elevate if needed
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Adversity-W11-Debloater-GUI.ps1"

REM Script will handle admin elevation internally
echo.
pause



