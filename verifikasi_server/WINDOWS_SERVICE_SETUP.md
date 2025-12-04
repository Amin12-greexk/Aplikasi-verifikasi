# Verifikasi Server - Windows Service Setup Guide

Dokumentasi lengkap untuk setup Verifikasi Server sebagai Windows Service yang auto-startup dan tetap berjalan saat PC sleep.

## Overview

Verifikasi Server sekarang mendukung dua mode operasi:

### 1. Desktop Mode (Default)
- Menjalankan aplikasi dengan UI grafis
- HTTP API server berjalan di background
- User dapat minimize ke system tray
- Manual launch oleh user

### 2. Service Mode (Windows Service)
- Menjalankan aplikasi tanpa UI (headless)
- HTTP API server berjalan 24/7
- Auto-startup setelah PC boot
- Auto-restart jika crash
- Tetap berjalan saat PC sleep

---

## Prerequisites

### System Requirements
- Windows 7 atau lebih baru
- Administrator access untuk instalasi service
- Visual Studio 2019+ dengan C++ workload (untuk compile service wrapper)

### Build Requirements untuk Service Wrapper

**Option A: Visual Studio Command Prompt (Recommended)**
1. Install Visual Studio 2019 atau lebih baru dengan C++ workload
2. Open "Visual Studio Developer Command Prompt" as Administrator
3. Navigate ke folder `windows_service_wrapper`
4. Compile: `cl.exe windows_service.cpp /link advapi32.lib winsvc.lib /OUT:verifikasi_service_wrapper.exe`

**Option B: CMake + Visual Studio**
1. Install CMake (3.14 atau lebih baru)
2. Open Command Prompt in `windows_service_wrapper` folder
3. Build:
```batch
cmake -G "Visual Studio 17 2022" -A x64 .
cmake --build . --config Release
```

---

## Building the Application

### Step 1: Build Flutter Application

```bash
cd verifikasi_server
flutter pub get
flutter build windows
```

Ini menghasilkan: `build\windows\x64\runner\Release\verifikasi_server.exe`

### Step 2: Build Service Wrapper (Windows Only)

#### Using Visual Studio Command Prompt:

```batch
REM Open "Visual Studio Developer Command Prompt" as Administrator
cd windows_service_wrapper

REM Compile
cl.exe windows_service.cpp /link advapi32.lib winsvc.lib /OUT:verifikasi_service_wrapper.exe

REM Verify build
dir verifikasi_service_wrapper.exe
```

#### Using CMake:

```batch
cd windows_service_wrapper
cmake -G "Visual Studio 17 2022" -A x64 .
cmake --build . --config Release

REM Output will be in build\bin\Release\
```

---

## Deployment

### Step 1: Prepare Deployment Directory

1. Create folder: `C:\Program Files\VerifikasiServer\`
   (atau lokasi lain sesuai preferensi)

2. Copy files dari build output:
   - `verifikasi_server.exe` → `C:\Program Files\VerifikasiServer\`
   - `verifikasi_service_wrapper.exe` → `C:\Program Files\VerifikasiServer\`
   - `install-service.bat` → `C:\Program Files\VerifikasiServer\`
   - `uninstall-service.bat` → `C:\Program Files\VerifikasiServer\`
   - `start-service.bat` → `C:\Program Files\VerifikasiServer\`
   - `data/` folder (Flutter assets) → `C:\Program Files\VerifikasiServer\data\`

### Step 2: Install as Windows Service

1. Open Command Prompt as **Administrator**
2. Navigate to deployment folder:
   ```batch
   cd C:\Program Files\VerifikasiServer\
   ```
3. Run installation script:
   ```batch
   install-service.bat
   ```

Expected output:
```
========================================
Verifikasi Server - Service Installation
========================================

This will install Verifikasi Server as a Windows Service
Service Name: VerifikasiServer
...
Service installed successfully!
Service started successfully!
```

### Step 3: Verify Service Installation

#### Option A: Using Services.msc
1. Open Services (press `Win + R`, type `services.msc`, press Enter)
2. Look for "Verifikasi Server" in the list
3. Verify:
   - Status: "Started" or "Running"
   - Startup Type: "Automatic"

#### Option B: Using Command Line
```batch
REM Check service status
sc query VerifikasiServer

REM Expected output shows:
REM SERVICE_NAME: VerifikasiServer
REM STATE: 4 RUNNING (0 STOPPED)
REM START_TYPE: 2 AUTO_START (3 DEMAND_START)
```

#### Option C: Test API Access
Open browser and navigate to:
```
http://localhost:8080/logs
```

Should return JSON data about current logs (if data exists).

---

## Usage

### Running as Service (Automatic)

The service will:
- **Auto-start** on Windows boot
- **Run in background** without UI
- **Remain active** during sleep/suspend
- **Auto-restart** if application crashes
- **Accept API requests** on `http://localhost:8080`

### Manual Service Control

#### Start Service
```batch
REM Using batch script
start-service.bat

REM Or using command line
net start VerifikasiServer
```

#### Stop Service
```batch
REM Using command line
net stop VerifikasiServer

REM Or uninstall completely
uninstall-service.bat
```

#### View Service Status
```batch
sc query VerifikasiServer
```

#### View Service Logs
1. Open Event Viewer (press `Win + R`, type `eventvwr.msc`)
2. Navigate to: Windows Logs → System
3. Filter by source "VerifikasiServer"

### Desktop Mode with System Tray (Manual Launch)

If you want to run desktop version with UI and system tray:

```batch
REM From command line with system tray
verifikasi_server.exe --minimize-to-tray

REM To run normal desktop mode
verifikasi_server.exe
```

System Tray Features:
- Click tray icon to show/hide dashboard
- Right-click for context menu
- "Show Dashboard" - Display the UI
- "Server Status" - Check if server is running
- "Exit" - Gracefully close application

---

## API Access

### Accessing the Server

From any machine on the network:
```
http://<computer-name>:8080/logs
http://<ip-address>:8080/logs
```

### Common API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/logs` | Get current logs |
| GET | `/logs-history/<date>` | Get logs for specific date |
| POST | `/auth/login` | User login (pengawas/security) |
| POST | `/admin/login` | Admin login |
| POST | `/scan-pengawas` | Record supervisor scan |
| POST | `/scan-security` | Record security scan |

### Authentication

Default credentials (untuk development):
- **Supervisor**: `pengawas` / `pengawas123`
- **Security**: `security` / `security123`
- **Admin**: `admin` / `admin123`

---

## Troubleshooting

### Issue: Service won't start

**Check 1: Administrator Privileges**
```batch
REM Run Command Prompt as Administrator
net start VerifikasiServer
```

**Check 2: Service Status**
```batch
sc query VerifikasiServer
```

**Check 3: Event Viewer Logs**
1. Open Event Viewer: `eventvwr.msc`
2. Navigate to: Windows Logs → System
3. Look for errors related to "VerifikasiServer"

**Check 4: File Permissions**
- Ensure `C:\Program Files\VerifikasiServer\` is readable
- Check that `verifikasi_server.exe` exists
- Verify `data/` folder with assets exists

### Issue: API not accessible on network

**Check 1: Windows Firewall**
```batch
REM Allow port 8080 in Windows Firewall
netsh advfirewall firewall add rule name="Verifikasi Server" dir=in action=allow protocol=tcp localport=8080
```

**Check 2: API Port Binding**
```batch
REM Check what's using port 8080
netstat -ano | findstr :8080
```

**Check 3: Service Running**
```batch
REM Verify service is running
sc query VerifikasiServer
```

### Issue: Service crashes repeatedly

**Check 1: Database Locks**
- Database might be locked by another process
- Try stopping service and check: `log.db`, `log.db-shm`, `log.db-wal` files

**Check 2: Port Already in Use**
- Another application might be using port 8080
- Change server port in code or use different port

**Check 3: File System Issues**
- Check disk space
- Verify write permissions to `C:\Program Files\VerifikasiServer\`

**Check 4: System Event Log**
Open Event Viewer and check Application logs for detailed error messages.

### Issue: PC goes to sleep but can't wake up / connectivity lost

This is normal behavior - the API server continues to run in background. To access it after wake:

1. Wake the PC (press any key, move mouse, etc.)
2. Wait 5-10 seconds for network to stabilize
3. API should be accessible again

---

## Uninstallation

### Remove Windows Service

1. Open Command Prompt as **Administrator**
2. Navigate to deployment folder:
   ```batch
   cd C:\Program Files\VerifikasiServer\
   ```
3. Run uninstall script:
   ```batch
   uninstall-service.bat
   ```

### Manual Uninstall

```batch
REM Stop service
net stop VerifikasiServer

REM Remove service
sc delete VerifikasiServer

REM Delete folder
rmdir /s /q C:\Program Files\VerifikasiServer\
```

---

## Advanced Configuration

### Change Service Start Type

```batch
REM Change from AUTO_START to DEMAND_START (manual start)
sc config VerifikasiServer start= demand

REM Change back to AUTO_START
sc config VerifikasiServer start= auto

REM Make service delayed-start (starts 2 minutes after boot)
sc config VerifikasiServer start= delayed-auto
```

### Change Service Account

By default, service runs as LOCAL_SYSTEM (highest privilege).

To change to network service account:
```batch
sc config VerifikasiServer obj= NT AUTHORITY\NetworkService
```

### Enable Service Recovery (Auto-Restart on Crash)

This is already configured in the service wrapper, but can be tweaked:

```batch
REM Set service to restart after 5 seconds on failure
sc failure VerifikasiServer reset= 86400 actions= restart/5000
```

---

## Performance & Monitoring

### Monitor Service Health

```batch
REM Check service status
sc query VerifikasiServer

REM Check process memory usage
tasklist | findstr verifikasi_server

REM Check if listening on port 8080
netstat -ano | findstr :8080
```

### View Real-time Logs

Service wrapper outputs logs to console. To capture:

```batch
REM Run service directly (not as service) to see console output
verifikasi_server.exe --service-mode > server.log 2>&1
```

---

## Security Considerations

### For Production Use

1. **Change Default Passwords**
   - Modify admin/pengawas/security credentials in database
   - Use strong, unique passwords

2. **Enable HTTPS**
   - Add SSL certificate support to shelf server
   - Update API endpoints to use HTTPS

3. **Firewall Rules**
   - Restrict port 8080 access to authorized IPs
   - Use Windows Firewall advanced rules

4. **Database Backup**
   - Schedule regular backups of `log.db`
   - Store backups in separate location

5. **Service Account**
   - Consider running service as dedicated low-privilege account
   - Not LOCAL_SYSTEM if possible

---

## Additional Resources

- [Windows Services Documentation](https://docs.microsoft.com/en-us/windows/win32/services/services)
- [Service Control Manager (SCM)](https://docs.microsoft.com/en-us/windows/win32/services/service-control-manager)
- [Flutter Desktop Documentation](https://flutter.dev/docs/development/platform-integration/windows)
- [Shelf HTTP Server Framework](https://pub.dev/packages/shelf)

---

## Support & Troubleshooting

For issues or questions:

1. Check Event Viewer logs: `eventvwr.msc`
2. Review service status: `sc query VerifikasiServer`
3. Check API connectivity: `http://localhost:8080/logs`
4. Review application logs in database

---

**Last Updated**: December 2025
**Supported**: Windows 7, Windows 10, Windows 11, Windows Server 2016+
