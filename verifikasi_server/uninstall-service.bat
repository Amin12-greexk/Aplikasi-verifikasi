@echo off
REM ==========================================
REM Verifikasi Server - Service Uninstallation
REM ==========================================
REM Requires: Administrator privileges
REM Usage: uninstall-service.bat

setlocal enabledelayedexpansion

REM Check for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo Error: This script requires administrator privileges!
    echo Please run Command Prompt as Administrator and try again.
    echo.
    pause
    exit /b 1
)

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0

REM Define path to service wrapper
set SERVICE_WRAPPER_EXE="%SCRIPT_DIR%verifikasi_service_wrapper.exe"

REM Check if executable file exists
if not exist !SERVICE_WRAPPER_EXE! (
    echo Error: verifikasi_service_wrapper.exe not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

echo.
echo ==========================================
echo Verifikasi Server - Service Uninstallation
echo ==========================================
echo.
echo This will remove the Verifikasi Server Windows Service
echo.

REM Check if service exists
sc query VerifikasiServer >nul 2>&1
if %errorlevel% neq 0 (
    echo Service not found. Nothing to uninstall.
    pause
    exit /b 0
)

REM Stop the service if it's running
echo Stopping service...
net stop VerifikasiServer >nul 2>&1

REM Wait a moment for service to stop
timeout /t 2 /nobreak

REM Remove the service
echo Removing service...
!SERVICE_WRAPPER_EXE! remove

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo Service removed successfully!
    echo ========================================
    echo.
) else (
    echo Error: Failed to remove service
    echo Please check Event Viewer for error details
    pause
    exit /b 1
)

pause
