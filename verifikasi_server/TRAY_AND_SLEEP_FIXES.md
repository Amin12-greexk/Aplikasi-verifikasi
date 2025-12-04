# System Tray & Sleep Mode Fixes

Dokumentasi tentang implementasi system tray yang proper dan prevent sleep mode.

---

## 🔧 Masalah yang Diperbaiki

### 1. ✅ Tray Icon Tidak Muncul
**Masalah**: Icon di system tray tidak muncul di taskbar

**Penyebab**: Package `system_tray` yang digunakan tidak compatible dengan Flutter Windows

**Solusi**: Menggunakan `tray_manager` + `window_manager` yang lebih robust

### 2. ✅ PC Bisa Sleep Padahal Aplikasi Berjalan
**Masalah**: PC masih bisa sleep meskipun aplikasi sedang jalan

**Penyebab**: Tidak ada call ke Windows API untuk prevent sleep

**Solusi**: Implement `SetThreadExecutionState` di native C++ code

---

## 📦 Dependencies yang Ditambahkan

### pubspec.yaml
```yaml
dependencies:
  tray_manager: ^0.2.0      # Proper system tray management
  window_manager: ^0.3.7    # Window management and events
```

---

## 🎯 Implementasi Detail

### 1. System Tray Manager (Dart)

**File**: `lib/system_tray_manager.dart`

```dart
class SystemTrayManager with TrayListener, WindowListener {
  // Initialize with tray_manager and window_manager
  Future<void> initialize({
    required VoidCallback onShow,
    required VoidCallback onExit,
  }) async {
    // Setup window manager
    await windowManager.ensureInitialized();

    // Setup tray manager
    await trayManager.ensureInitialized();

    // Create tray menu with items:
    // - Show Dashboard
    // - Server Status
    // - Exit
  }

  // Minimize window to tray
  Future<void> hideWindow() async {
    await windowManager.hide();
  }

  // Show window from tray
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
```

**Features**:
- ✅ Tray icon dengan menu
- ✅ Click tray icon untuk show/hide window
- ✅ Right-click untuk context menu
- ✅ Minimize window ke tray
- ✅ Window event listeners

### 2. Window Manager Integration (Dart)

**File**: `lib/main.dart` - `_ServerAppState`

```dart
class _ServerAppState extends State<ServerApp> with WindowListener {
  Future<void> _initWindowManager() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.white,
      skipTaskbar: false,
      alwaysOnTop: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  void onWindowMinimize() {
    // Minimize button → Hide to tray
    _trayManager.hideWindow();
  }

  @override
  void onWindowClose() {
    // Close button → Minimize to tray instead of closing
    _trayManager.hideWindow();
  }
}
```

**Features**:
- ✅ Window initialization dengan options
- ✅ Minimize button → Tray
- ✅ Close button → Tray (bukan exit)
- ✅ Window event handlers

### 3. Sleep Prevention (C++)

**File**: `windows/runner/main.cpp`

```cpp
#include <powrprof.h>
#pragma comment(lib, "powrprof.lib")

// Prevent system sleep
void PreventSystemSleep() {
  EXECUTION_STATE previousState = SetThreadExecutionState(
      ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
  // ES_CONTINUOUS: Kontinyu
  // ES_SYSTEM_REQUIRED: Prevent system sleep
  // ES_AWAYMODE_REQUIRED: Allow away mode
}

// In wWinMain - Desktop mode
PreventSystemSleep();  // Call saat app start
// ... message loop ...
SetThreadExecutionState(ES_CONTINUOUS);  // Allow sleep saat app close
```

**Features**:
- ✅ Prevent system sleep
- ✅ Allow away mode (partial sleep)
- ✅ Release lock saat app close
- ✅ Works tanpa user input

---

## 🎨 User Experience

### System Tray Menu
```
┌─ Verifikasi Server ──────────────┐
│                                  │
│  Show Dashboard                  │
│  ─────────────────────────────── │
│  Server Status: Running          │
│  ─────────────────────────────── │
│  Exit                            │
└──────────────────────────────────┘
```

### Window Behavior
```
App Start
  ↓
Window appears on screen
  ↓
Tray icon appears in system tray
  ↓
User clicks minimize button
  ↓
Window hides → Appears only in tray
  ↓
User clicks tray icon or "Show Dashboard"
  ↓
Window reappears
  ↓
User clicks close button
  ↓
Window hides to tray (doesn't exit)
```

### Sleep Prevention
```
App Running
  ↓
SetThreadExecutionState() called
  ↓
PC prevents sleep/suspend
  ↓
Even with idle, PC stays awake
  ↓
App Exits
  ↓
SetThreadExecutionState(ES_CONTINUOUS)
  ↓
PC can sleep normally
```

---

## 📋 Build Changes

### Dependencies Updated
```yaml
# Before
system_tray: ^2.0.0  ← Removed (had issues)

# After
tray_manager: ^0.2.0  ← Added (better support)
window_manager: ^0.3.7 ← Added (window events)
```

### Native Code Updated
```cpp
#include <powrprof.h>      ← Added
#pragma comment(lib, "powrprof.lib") ← Added

PreventSystemSleep();      ← Added in desktop mode
SetThreadExecutionState() ← Added for cleanup
```

### Dart Code Updated
```dart
import 'package:window_manager/window_manager.dart';

class _ServerAppState extends State<ServerApp> with WindowListener {
  // WindowListener methods added
}

Future<void> _initWindowManager() { ... }  // New method
```

---

## 🧪 Testing

### Test 1: Tray Icon Visibility
```
1. Run: flutter run
2. Look at bottom-right taskbar area
3. Should see Verifikasi Server icon
4. Right-click on icon → Should show menu
5. Click icon → Window appear/hide
```

### Test 2: Minimize to Tray
```
1. Click minimize button on window
2. Window should disappear
3. Icon should appear/stay in tray
4. Click tray icon → Window reappears
```

### Test 3: Sleep Prevention
```
1. Run application
2. Let PC idle (no input) for 5 minutes
3. PC should NOT go to sleep
4. Close application
5. Let PC idle for 5 minutes
6. PC should go to sleep normally
```

### Test 4: Menu Items
```
1. Right-click tray icon
2. Click "Show Dashboard" → Window appears
3. Right-click again
4. Click "Server Status" → Should log "Running on port 8080"
5. Click "Exit" → Application closes
```

---

## 🔍 Troubleshooting

### Tray Icon Not Showing

**Check 1: Dependencies**
```bash
flutter pub get
```

**Check 2: Rebuild**
```bash
flutter clean
flutter pub get
flutter build windows --release
```

**Check 3: Windows Version**
- Requires Windows 7 or newer
- Check: `winver` command

### PC Still Goes to Sleep

**Check 1: Windows Power Settings**
- Settings → System → Power & battery
- Change "Sleep" timeout to "Never" for testing

**Check 2: Verify Code Called**
```
1. Run app with debug console visible
2. Should see: "System sleep prevention enabled"
3. If not, rebuild with clean
```

**Check 3: Other Programs**
- Other apps might override sleep settings
- Check: `powercfg /lastwake` in Command Prompt

### Minimize Button Not Working

**Fix**: Update window_manager to latest version
```bash
flutter pub upgrade window_manager
```

---

## 📊 Technical Details

### SetThreadExecutionState Flags

| Flag | Purpose |
|------|---------|
| `ES_CONTINUOUS` | Continue specified state |
| `ES_SYSTEM_REQUIRED` | Prevent system sleep |
| `ES_DISPLAY_REQUIRED` | Prevent display sleep |
| `ES_USER_PRESENT` | User is present (deprecated) |
| `ES_AWAYMODE_REQUIRED` | Allow away mode during system required |

**Used Combination**:
```cpp
ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED
```
- Prevent system sleep
- Allow partial sleep (away mode)
- Continue indefinitely

### Tray Manager Events

Supported events:
- `onTrayIconMouseDown` - Left click
- `onTrayIconRightMouseDown` - Right click
- `onTrayMenuItemClick` - Menu item selection
- Various window events

---

## 🔐 Security & Performance

### Sleep Prevention Impact
- ✅ Minimal CPU impact when idle
- ✅ Only prevents system sleep, not display
- ⚠️ Higher power consumption
- ⚠️ Set timeout in Windows settings if needed

### Tray Manager Impact
- ✅ Minimal memory footprint
- ✅ Efficient event handling
- ✅ Native Windows API usage

---

## 🚀 Production Deployment

### Batch Script Update Needed
Update `install-service.bat` to note that system tray is only in desktop mode:

```batch
echo The service runs in background without UI (no tray).
echo For desktop mode with tray, run: verifikasi_server.exe
echo For system tray, use: verifikasi_server.exe --minimize-to-tray
```

### Service Mode Unaffected
- Service mode (`--service-mode`) still headless
- No tray icon in service mode
- Sleep prevention only in desktop mode

---

## 📝 Code Changes Summary

### Files Modified
1. `pubspec.yaml` - Added dependencies
2. `lib/main.dart` - Window manager integration
3. `lib/system_tray_manager.dart` - Rewritten with tray_manager
4. `windows/runner/main.cpp` - Sleep prevention

### Lines of Code
- Dart: ~80 lines (system_tray_manager)
- Dart: ~60 lines (window manager in main)
- C++: ~15 lines (sleep prevention)
- Total: ~155 lines added

### Backward Compatibility
- ✅ Service mode unaffected
- ✅ API still works
- ✅ Database unaffected
- ✅ All existing features work

---

## 🎯 Features Now Working

### System Tray
- ✅ Tray icon appears in taskbar
- ✅ Right-click context menu
- ✅ "Show Dashboard" option
- ✅ "Server Status" option
- ✅ "Exit" option
- ✅ Click icon to toggle window visibility

### Sleep Prevention
- ✅ PC does not sleep while app running
- ✅ Can still use away mode
- ✅ Released on app exit
- ✅ Works in desktop mode

### Window Management
- ✅ Minimize to tray
- ✅ Restore from tray
- ✅ Close minimizes to tray (not exit)
- ✅ Proper window events

---

## 📞 Support

See main documentation files:
- WINDOWS_SERVICE_SETUP.md
- IMPLEMENTATION_GUIDE.md
- SERVICE_README.md

---

**Status**: ✅ Implementation Complete
**Version**: 1.0.0
**Last Updated**: December 4, 2025
