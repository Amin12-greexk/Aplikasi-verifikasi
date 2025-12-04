@echo off
REM ========================================
REM Verifikasi Server - Start Service
REM ========================================
REM Starts the Verifikasi Server Windows Service

setlocal enabledelayedexpansion

echo.
echo ========================================
echo Starting Verifikasi Server Service...
echo ========================================
echo.

net start VerifikasiServer

if %errorlevel% equ 0 (
    echo.
    echo Service started successfully!
    echo The HTTP API is now accessible at http://localhost:8080
    echo.
) else (
    echo.
    echo Error: Failed to start service
    echo Please check that:
    echo - The service is installed (run install-service.bat)
    echo - Windows Services snap-in (services.msc) shows the service
    echo - Event Viewer has error details
    echo.
)

pause
