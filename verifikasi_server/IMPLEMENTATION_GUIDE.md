# Verifikasi Server Windows Service - Implementation Guide

Panduan step-by-step untuk implementasi dan testing service wrapper.

---

## Phase 1: Prepare Development Environment

### Prerequisites Check

```bash
# Check Flutter is installed and updated
flutter --version

# Check Visual Studio is installed
# Open "x64 Native Tools Command Prompt for VS 2022" from Start Menu
# or verify: C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\
```

### Clone/Update Project

```bash
cd /mnt/c/Users/USER/Desktop/Aplikasi\ verifikasi/verifikasi_server

# Update dependencies
flutter pub get
```

---

## Phase 2: Build Flutter Application

### Build Windows Release

```bash
cd verifikasi_server

# Clean previous builds
flutter clean

# Build Windows release
flutter build windows --release

# Expected output folder:
# build/windows/x64/runner/Release/verifikasi_server.exe
# build/windows/x64/runner/Release/data/ (assets)
```

**Verification:**
```bash
# Check if executable exists
dir build\windows\x64\runner\Release\verifikasi_server.exe

# Test running in desktop mode
build\windows\x64\runner\Release\verifikasi_server.exe

# Should show window and console output:
# [DESKTOP MODE] Starting verifikasi_server with UI...
# Server jalan di http://0.0.0.0:8080
```

---

## Phase 3: Build Service Wrapper

### Option A: Using Visual Studio Developer Command Prompt (Recommended)

```batch
REM 1. Open "x64 Native Tools Command Prompt for VS 2022" as Administrator

REM 2. Navigate to service wrapper directory
cd C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\windows_service_wrapper

REM 3. Compile the service wrapper
cl.exe windows_service.cpp /link advapi32.lib winsvc.lib /OUT:verifikasi_service_wrapper.exe

REM 4. Verify the executable was created
dir verifikasi_service_wrapper.exe

REM Expected: File should be created in current directory
```

### Option B: Using CMake (Alternative)

```batch
REM 1. Install CMake if not already installed

REM 2. Navigate to service wrapper directory
cd windows_service_wrapper

REM 3. Generate Visual Studio project
cmake -G "Visual Studio 17 2022" -A x64 .

REM 4. Build
cmake --build . --config Release

REM 5. Find compiled executable
dir build\bin\Release\verifikasi_service_wrapper.exe
```

**Verification:**
```batch
# Test service wrapper help
verifikasi_service_wrapper.exe

# Expected output:
# Verifikasi Server - Windows Service Manager
# ========================================
# Usage:
#   verifikasi_service_wrapper.exe install <path_to_app>
#   verifikasi_service_wrapper.exe remove
#   verifikasi_service_wrapper.exe start
#   verifikasi_service_wrapper.exe stop
```

---

## Phase 4: Prepare Deployment Directory

### Create Installation Folder

```batch
REM 1. Create deployment directory
mkdir "C:\Program Files\VerifikasiServer"

REM 2. Navigate to it
cd /d "C:\Program Files\VerifikasiServer"
```

### Copy Executables

```batch
REM From Flutter build output
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\build\windows\x64\runner\Release\verifikasi_server.exe" .

REM From service wrapper build
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\windows_service_wrapper\verifikasi_service_wrapper.exe" .
```

### Copy Flutter Assets (data folder)

```batch
REM Copy the data folder with Flutter assets
xcopy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\build\windows\x64\runner\Release\data" data\ /E /I /Y
```

### Copy Batch Scripts

```batch
REM Copy batch scripts to make them easily accessible
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\install-service.bat" .
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\uninstall-service.bat" .
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\start-service.bat" .
```

### Verify Deployment Directory

```batch
REM Check what's in the deployment folder
cd "C:\Program Files\VerifikasiServer"
dir

REM Should show:
# verifikasi_server.exe
# verifikasi_service_wrapper.exe
# install-service.bat
# uninstall-service.bat
# start-service.bat
# data\ (folder)

REM Check data folder
dir data
```

---

## Phase 5: Install Windows Service

### Run Installation Script

```batch
REM 1. Open Command Prompt as Administrator
REM    (Right-click Command Prompt → Run as administrator)

REM 2. Navigate to deployment folder
cd /d "C:\Program Files\VerifikasiServer"

REM 3. Run installation script
install-service.bat

REM Expected output:
# ========================================
# Verifikasi Server - Service Installation
# ========================================
#
# This will install Verifikasi Server as a Windows Service
# Service Name: VerifikasiServer
# Service Display Name: Verifikasi Server
# Start Type: Automatic
#
# Location: C:\Program Files\VerifikasiServer\
#
# Installing service...
# Service installed successfully!
#
# Starting service...
#
# Service started successfully!
```

### Manual Installation (if batch fails)

```batch
REM If the batch script fails, try manual steps:

REM 1. Check if service already exists
sc query VerifikasiServer

REM 2. If exists, stop and remove it
net stop VerifikasiServer
verifikasi_service_wrapper.exe remove

REM 3. Install service
verifikasi_service_wrapper.exe install "C:\Program Files\VerifikasiServer\verifikasi_server.exe"

REM 4. Start service
net start VerifikasiServer

REM 5. Verify
sc query VerifikasiServer
```

---

## Phase 6: Verify Service Installation

### Check 1: Services.msc

```
1. Press: Win + R
2. Type: services.msc
3. Press: Enter
4. Look for "Verifikasi Server" in the list
5. Verify:
   - Status: "Running"
   - Startup Type: "Automatic"
```

### Check 2: Command Line

```batch
REM Check service status
sc query VerifikasiServer

REM Expected output:
# SERVICE_NAME: VerifikasiServer
# DISPLAY_NAME: Verifikasi Server
# TYPE: 10 WIN32_OWN_PROCESS
# STATE: 4 RUNNING
# WIN32_EXIT_CODE: 0 (0x0)
# SERVICE_EXIT_CODE: 0 (0x0)
# CHECKPOINT: 0x0
# WAIT_HINT: 0x0

REM Check if process is running
tasklist | findstr verifikasi_server

REM Check if listening on port 8080
netstat -ano | findstr :8080

REM Expected: Should show ESTABLISHED or LISTENING on port 8080
```

### Check 3: API Accessibility

```batch
REM Test API endpoint using curl (if installed)
curl http://localhost:8080/logs

REM Or open in browser:
# http://localhost:8080/logs
#
# Should return JSON with log data (or empty array if no logs yet)
# Example: {"logs": [...]}
```

### Check 4: Event Viewer

```
1. Press: Win + R
2. Type: eventvwr.msc
3. Press: Enter
4. Navigate to: Windows Logs → System
5. Look for events from "VerifikasiServer"
6. Should show: Service started successfully
```

---

## Phase 7: Test Sleep Mode Functionality

### Test 1: Verify API During Sleep

```batch
REM 1. Service should be running
sc query VerifikasiServer

REM 2. Test API before sleep
curl http://localhost:8080/logs

REM 3. Put PC to sleep:
REM    - Press: Win + X
REM    - Select: Sleep
REM    OR
REM    - Control Panel → Power Options → Sleep

REM 4. Wait 2-3 minutes

REM 5. Wake PC (press any key or move mouse)

REM 6. Wait 10 seconds for network to stabilize

REM 7. Test API after sleep
curl http://localhost:8080/logs

REM Should still work!
```

### Test 2: Service Auto-Restart After Crash

```batch
REM 1. Find service process
tasklist | findstr verifikasi_server.exe

REM Sample output:
# verifikasi_server.exe  8932  Console  0  5,234 K

REM 2. Kill the process
taskkill /PID 8932 /F

REM 3. Wait 3 seconds

REM 4. Check if service restarted
tasklist | findstr verifikasi_server.exe

REM Should show a new process with different PID
REM The service wrapper automatically restarts it!
```

### Test 3: System Reboot

```batch
REM 1. Verify service is running
sc query VerifikasiServer

REM 2. Reboot the PC:
REM    - Press: Win + X
REM    - Select: Restart
REM    OR
REM    - Command: shutdown /r /t 0

REM 3. After reboot, verify service auto-started:
REM    - Open Command Prompt as Administrator
REM    - Run: sc query VerifikasiServer
REM    - Should show STATE: 4 RUNNING

REM 4. Test API:
REM    - curl http://localhost:8080/logs
REM    - Should work without manual start!
```

---

## Phase 8: Test Desktop Mode with System Tray

### Desktop Mode Execution

```batch
REM Navigate to deployment folder
cd "C:\Program Files\VerifikasiServer"

REM Run in desktop mode (with UI)
verifikasi_server.exe

REM Or with auto-minimize to tray
verifikasi_server.exe --minimize-to-tray

REM Expected:
# - Window opens with login screen
# - Console output shows: [DESKTOP MODE] Starting verifikasi_server with UI...
# - Server starts on port 8080
# - System tray icon appears (if --minimize-to-tray flag used)
```

### System Tray Features

```
1. Click tray icon in taskbar → Shows dashboard UI
2. Right-click tray icon → Context menu with options:
   - Dashboard: Show the application window
   - Server Status: Display server status
   - Exit: Close application gracefully
```

---

## Phase 9: Testing Checklist

### Service Functionality
- [ ] Service installs successfully without errors
- [ ] Service starts automatically after installation
- [ ] Service appears in Services.msc as "Running"
- [ ] Service startup type is "Automatic"
- [ ] HTTP API is accessible on http://localhost:8080
- [ ] Service survives PC sleep mode
- [ ] Service auto-restarts if process is killed
- [ ] Service auto-starts after system reboot

### Desktop Mode
- [ ] Desktop mode launches without errors
- [ ] UI window appears correctly
- [ ] Login page is functional
- [ ] HTTP server works with UI running
- [ ] System tray icon appears when flag is used
- [ ] Minimize to tray works
- [ ] Restore from tray works

### API Endpoints
- [ ] GET /logs returns data
- [ ] GET /logs-history/<date> works
- [ ] POST /auth/login accepts credentials
- [ ] POST /scan-pengawas works
- [ ] POST /scan-security works

### Firewall & Network
- [ ] API accessible from other PCs on network
- [ ] Windows Firewall allows port 8080
- [ ] Network connectivity restored after sleep

### Cleanup & Uninstall
- [ ] Uninstall script removes service successfully
- [ ] Service no longer appears in Services.msc
- [ ] No processes remain after uninstall

---

## Phase 10: Troubleshooting During Testing

### Issue: Service won't install

```batch
REM Check admin privileges
net session >nul 2>&1
if errorlevel 1 echo Need administrator!

REM Check if service already exists
sc query VerifikasiServer

REM If exists, remove first
net stop VerifikasiServer
sc delete VerifikasiServer
```

### Issue: Service starts but stops immediately

```batch
REM Check event viewer for errors
eventvwr.msc

REM Check if executable is accessible
cd "C:\Program Files\VerifikasiServer"
verifikasi_server.exe --service-mode

REM Check for file permission issues
icacls "C:\Program Files\VerifikasiServer" /T
```

### Issue: API not accessible

```batch
REM Check if service is running
sc query VerifikasiServer

REM Check if port is in use
netstat -ano | findstr :8080

REM Check firewall
netsh advfirewall firewall show rule name="Verifikasi Server"

REM Add firewall rule if needed
netsh advfirewall firewall add rule name="Verifikasi Server" dir=in action=allow protocol=tcp localport=8080
```

### Issue: Service crashes after a few seconds

```batch
REM Check database locks
cd "C:\Program Files\VerifikasiServer"
dir log.db*

REM Try renaming database (will create new one)
REM (backup old one first!)

REM Check Windows Event Log
eventvwr.msc
```

---

## Next Steps

Once all tests pass:

1. **Documentation**: Review WINDOWS_SERVICE_SETUP.md
2. **User Training**: Train users on service management
3. **Monitoring**: Setup monitoring/alerting if needed
4. **Backup**: Setup database backup automation
5. **Security Hardening**: Change default credentials
6. **Network Configuration**: Configure firewalls and network access

---

**Status**: Ready for testing
**Last Updated**: December 2025
