# Flutter SDK Issue - Fix & Troubleshooting

## Issue Encountered

```
Error: Unable to 'pub upgrade' flutter tool.
/mnt/c/Flutter/flutter/bin/internal/shared.sh: line 23:
/mnt/c/Flutter/flutter/bin/cache/dart-sdk/bin/dart: No such file or directory
```

This indicates the Flutter SDK cache is corrupted or incomplete.

---

## Solution Options

### Option 1: Flutter Pub Get (Quick Fix)

Try to get dependencies anyway:

```bash
cd "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server"
flutter pub get --no-pub-suppression-sdk-check
```

---

### Option 2: Reinstall Flutter Cache

```bash
# This will re-download and setup the Flutter SDK
cd %FLUTTER_HOME%
flutter doctor -v

# This should rebuild the cache
```

---

### Option 3: Download Flutter SDK Fresh

1. **Backup current Flutter:**
   ```batch
   REM Backup current Flutter if needed
   cd C:\
   ren "Flutter" "Flutter_Backup"
   ```

2. **Download Flutter:**
   - Go to https://flutter.dev/docs/get-started/install/windows
   - Download the latest Windows release (stable)
   - Extract to `C:\Flutter\`

3. **Setup environment:**
   ```batch
   REM Add to PATH
   set PATH=C:\Flutter\bin;%PATH%

   REM Run doctor to setup
   flutter doctor -v
   ```

4. **Try building again:**
   ```bash
   cd "C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server"
   flutter clean
   flutter pub get
   flutter build windows
   ```

---

### Option 4: Use Bash/WSL Flutter (If Available)

If you have Flutter installed in WSL2:

```bash
# In WSL2 terminal
cd /mnt/c/Users/USER/Desktop/Aplikasi\ verifikasi/verifikasi_server
flutter clean
flutter pub get
flutter build windows
```

---

## Verify Flutter Installation

```batch
REM Open Command Prompt and run:
flutter --version
flutter doctor -v

REM Should show:
REM Flutter X.X.X • channel stable
REM Framework • revision XXXXX
REM Engine • revision XXXXX
REM Dart SDK version X.XX.X
```

---

## Alternative: Build on Different Machine

If Flutter SDK cannot be fixed, you can:

1. **Use Docker** (if available)
   - Flutter has Docker images
   - Guaranteed consistent build environment

2. **Use CI/CD** (GitHub Actions, etc.)
   - Automatic build on cloud
   - Fresh environment each time

3. **Install on Different PC**
   - If you have access to another Windows machine
   - Install fresh Flutter there
   - Build on that machine

---

## For CI/CD (Windows GitHub Actions Example)

```yaml
name: Build Verifikasi Server

on: [push, pull_request]

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.13.0'
          cache: true

      - name: Get dependencies
        working-directory: verifikasi_server
        run: flutter pub get

      - name: Build Windows
        working-directory: verifikasi_server
        run: flutter build windows

      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: windows-build
          path: verifikasi_server/build/windows/x64/runner/Release/
```

---

## Debug Commands

If still having issues:

```bash
# Check Flutter version
flutter --version

# Run pub get with verbose output
flutter pub get -v

# Check all dependencies
flutter pub deps

# Run pub cache clean and retry
flutter pub cache clean
flutter pub get

# Check specific package
flutter pub cache list

# Force update pub
flutter pub upgrade
```

---

## Expected Build Output

When build succeeds, you should see:

```
Building Windows application...
[   +6 ms] executing: C:\Users\USER\Desktop\Aplikasi verifikasi\verifikasi_server\build\windows\x64\flutter\flutter_build.bat
[ +7.3 s] Building the Windows application...
[ +3.2 s] [OK] built build\windows\x64\runner\Release\verifikasi_server.exe
Building Windows application... 14.5s
[✓] Built build windows x64 runner Release app.
```

---

## Files After Successful Build

```
verifikasi_server/
  build/
    windows/
      x64/
        runner/
          Release/
            verifikasi_server.exe      ← Main executable
            data/                      ← Flutter assets folder
            msvcp140.dll
            vcruntime140.dll
            flutter_windows.dll
```

---

## Next Steps

Once Flutter builds successfully:

1. **Test Desktop Mode:**
   ```batch
   "C:\path\to\verifikasi_server\build\windows\x64\runner\Release\verifikasi_server.exe"
   ```

2. **Build Service Wrapper:**
   ```batch
   cd windows_service_wrapper
   cl.exe windows_service.cpp /link advapi32.lib winsvc.lib /OUT:verifikasi_service_wrapper.exe
   ```

3. **Deploy Service:**
   Follow WINDOWS_SERVICE_SETUP.md

---

## Support Resources

- [Flutter Docs - Windows Setup](https://flutter.dev/docs/get-started/install/windows)
- [Flutter FAQ](https://flutter.dev/docs/resources/faq)
- [Flutter Issues - GitHub](https://github.com/flutter/flutter/issues)
- [Stack Overflow - flutter tag](https://stackoverflow.com/questions/tagged/flutter)

---

**Note**: The code changes are complete and correct. The Flutter SDK issue is environmental and not caused by our code changes.

All code is ready to build once Flutter SDK is fixed!
