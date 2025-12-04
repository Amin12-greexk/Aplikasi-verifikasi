@echo off
REM ========================================
REM Verifikasi Server - Service Installation
REM ========================================
REM Requires: Administrator privileges
REM Usage: install-service.bat

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

REM Define paths to executables
set SERVICE_WRAPPER_EXE="%SCRIPT_DIR%verifikasi_service_wrapper.exe"
set SERVER_EXE="%SCRIPT_DIR%verifikasi_server.exe"

REM Check if executable files exist
if not exist !SERVICE_WRAPPER_EXE! (
    echo Error: verifikasi_service_wrapper.exe not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

if not exist !SERVER_EXE! (
    echo Error: verifikasi_server.exe not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

echo.
echo ========================================
echo Verifikasi Server - Service Installation
echo ========================================
echo.
echo This will install Verifikasi Server as a Windows Service
echo Service Name: VerifikasiServer
echo Service Display Name: Verifikasi Server
echo Start Type: Automatic
echo.
echo Location: %SCRIPT_DIR%
echo.

REM Check if service already exists
sc query VerifikasiServer >nul 2>&1
if %errorlevel% equ 0 (
    echo Service already exists. Removing old service...
    net stop VerifikasiServer >nul 2>&1
    !SERVICE_WRAPPER_EXE! remove
    if %errorlevel% neq 0 (
        echo Error: Failed to remove existing service
        pause
        exit /b 1
    )
    echo Old service removed successfully
    echo.
)

REM Install the service
echo Installing service...
!SERVICE_WRAPPER_EXE! install !SERVER_EXE!

if %errorlevel% equ 0 (
    echo Service installed successfully!
    echo.
    echo Starting service...
    net start VerifikasiServer

    if %errorlevel% equ 0 (
        echo.
        echo ========================================
        echo Service started successfully!
        echo ========================================
        echo.
        echo You can now:
        echo - Open Windows Services (services.msc) to manage the service
        echo - Access the API at http://localhost:8080/logs
        echo - Check the status: net stop VerifikasiServer
        echo - Stop the service: net start VerifikasiServer
        echo.
        echo The service is configured to:
        echo - Start automatically on system boot
        echo - Restart automatically if it crashes
        echo - Run in the background without a UI
        echo.
    ) else (
        echo Error: Failed to start service
        echo Please check Windows Event Viewer for error details
        pause
        exit /b 1
    )
) else (
    echo Error: Failed to install service
    echo Please check that you have administrator privileges
    echo and that verifikasi_server.exe is in the same directory
    pause
    exit /b 1
)

pause
