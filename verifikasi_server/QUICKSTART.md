# Quick Start - Windows Service Deployment

Panduan cepat untuk deploy Verifikasi Server sebagai Windows Service.

---

## 📋 Prerequisites (5 minutes)

✅ Windows 7 or newer
✅ Administrator account
✅ Visual Studio 2019+ (for C++ compilation)
✅ Flutter installed and working

---

## 🔨 Build Process (15 minutes)

### Step 1: Build Flutter App

```bash
cd "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server"
flutter clean
flutter pub get
flutter build windows --release
```

**Expected Output:**
```
[✓] Built build windows x64 runner Release app.
```

### Step 2: Build Service Wrapper

```batch
REM Open "x64 Native Tools Command Prompt for VS 2022" as Administrator

cd windows_service_wrapper

cl.exe windows_service.cpp /link advapi32.lib winsvc.lib /OUT:verifikasi_service_wrapper.exe

REM Verify
dir verifikasi_service_wrapper.exe
```

---

## 📦 Deploy (5 minutes)

### Create Deployment Folder

```batch
mkdir "C:\Program Files\VerifikasiServer"
cd "C:\Program Files\VerifikasiServer"
```

### Copy Files

```batch
REM Copy executables
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\build\windows\x64\runner\Release\verifikasi_server.exe" .

copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\windows_service_wrapper\verifikasi_service_wrapper.exe" .

REM Copy Flutter assets
xcopy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\build\windows\x64\runner\Release\data" data\ /E /I /Y

REM Copy scripts
copy "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\install-service.bat" .
```

### Install Service

```batch
REM Run as Administrator!
cd "C:\Program Files\VerifikasiServer"
install-service.bat
```

---

## ✅ Verify Installation (2 minutes)

### Check 1: Services Management

```
Press: Win + R
Type: services.msc
Press: Enter

Look for "Verifikasi Server" → Should show "Running"
```

### Check 2: Command Line

```batch
sc query VerifikasiServer

REM Expected:
REM STATE: 4 RUNNING
REM START_TYPE: 2 AUTO_START
```

### Check 3: API Test

Open browser:
```
http://localhost:8080/logs
```

Should return JSON data.

---

## 🎯 Done!

Your service is now:
- ✅ Installed as Windows Service
- ✅ Running in background
- ✅ Will auto-start on next reboot
- ✅ Will survive PC sleep
- ✅ Will auto-restart if it crashes

---

## 🚀 Testing

### Test 1: PC Sleep

```
1. Service should be running: sc query VerifikasiServer
2. Put PC to sleep: Win + X → Sleep
3. Wait 2 minutes
4. Wake PC (press any key)
5. Test API: http://localhost:8080/logs
6. Should still work!
```

### Test 2: Service Crash Recovery

```
1. Find process: tasklist | findstr verifikasi
2. Kill it: taskkill /PID XXXX /F
3. Wait 3 seconds
4. Check if restarted: tasklist | findstr verifikasi
5. Should show new process!
```

### Test 3: Reboot

```
1. Reboot PC: shutdown /r /t 0
2. After reboot, check: sc query VerifikasiServer
3. Should show RUNNING (auto-started)
```

---

## 📖 Documentation

- **SERVICE_README.md** - Overview and quick reference
- **WINDOWS_SERVICE_SETUP.md** - Complete setup guide
- **IMPLEMENTATION_GUIDE.md** - Detailed step-by-step
- **Troubleshooting** - See WINDOWS_SERVICE_SETUP.md

---

## 🛠️ Common Tasks

### Start Service
```batch
net start VerifikasiServer
```

### Stop Service
```batch
net stop VerifikasiServer
```

### Check Status
```batch
sc query VerifikasiServer
```

### View Logs
```
Event Viewer (eventvwr.msc)
→ Windows Logs
→ System
→ Filter by VerifikasiServer
```

### Uninstall Service
```batch
cd "C:\Program Files\VerifikasiServer"
uninstall-service.bat
```

---

## ❓ Troubleshooting

### Service won't start
1. Run Command Prompt as Administrator
2. Check: `sc query VerifikasiServer`
3. View logs: `eventvwr.msc`

### API not accessible
1. Check firewall: Allow port 8080
2. Check service running: `sc query VerifikasiServer`
3. Test locally: `curl http://localhost:8080/logs`

### Service keeps crashing
1. Check Event Viewer for errors
2. Verify database file (log.db) exists
3. Check disk space
4. Check permissions on C:\Program Files\VerifikasiServer\

See WINDOWS_SERVICE_SETUP.md for more troubleshooting.

---

## 📝 API Endpoints

Available while service is running:

```
GET  http://localhost:8080/logs                    - Get all current logs
GET  http://localhost:8080/logs-history/2024-12-01 - Get logs by date
POST http://localhost:8080/auth/login              - User login
POST http://localhost:8080/scan-pengawas           - Record supervisor scan
POST http://localhost:8080/scan-security           - Record security scan
```

Default credentials:
- Admin: admin / admin123
- Supervisor: pengawas / pengawas123
- Security: security / security123

---

## 🔒 Security Note

**For Production:**
1. Change default credentials
2. Enable HTTPS
3. Restrict firewall rules
4. Run as lower-privilege account
5. Setup database backups

---

## 🎓 How It Works

**Service Mode:**
```
Windows boots
  ↓
Service Control Manager starts VerifikasiServer
  ↓
Service wrapper launches verifikasi_server.exe --service-mode
  ↓
HTTP server listens on :8080
  ↓
Ready to accept API requests
```

**During PC Sleep:**
```
User sleeps PC
  ↓
verifikasi_server process continues (headless, no UI)
  ↓
HTTP server stays responsive
  ↓
When PC wakes, network reconnects
  ↓
Service immediately accessible again
```

**Auto-Restart:**
```
If server crashes
  ↓
Service wrapper detects exit
  ↓
Waits 3 seconds
  ↓
Automatically restarts server
  ↓
Service never goes down
```

---

## 📞 Need Help?

1. Check SERVICE_README.md for quick reference
2. Check WINDOWS_SERVICE_SETUP.md for detailed guide
3. Check IMPLEMENTATION_GUIDE.md for troubleshooting
4. Check Windows Event Viewer for error logs

---

**Estimated Total Time**: ~25 minutes from start to fully operational service

**Status**: Ready to deploy!
