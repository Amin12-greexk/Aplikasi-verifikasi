# Sleep Mode & Auto-Reconnect Guide

Dokumentasi tentang implementasi auto-reconnect ketika PC sleep dan network kembali online.

---

## 🔧 Masalah yang Diperbaiki

### Masalah Original
**Saat PC sleep:**
1. Jaringan disconnect
2. API request hangus/timeout
3. Fetch data berhenti
4. User aplikasi blank/loading forever

### Solusi Implementasi
Buat robust HTTP client dengan:
- ✅ Auto-retry logic (3x dengan exponential backoff)
- ✅ Timeout handling (10 detik per request)
- ✅ Connection recovery
- ✅ Sleep-aware retry delays

---

## 📦 Files yang Diubah/Dibuat

### New Files
1. **lib/api_client_retry.dart** (180+ lines)
   - Enhanced API client dengan retry logic
   - Timeout handling
   - Connection error recovery
   - Sleep-aware exponential backoff

### Modified Files
1. **lib/status_page.dart**
   - Import dari `api_client` → `api_client_retry`
   - Call `ApiClientRetry.fetchLogs()` instead of `fetchLogs()`
   - Call `ApiClientRetry.dailyReset()` instead of `dailyReset()`

2. **lib/scanner_page.dart**
   - Import dari `api_client` → `api_client_retry`
   - Call `ApiClientRetry.accPengawas()` dan `ApiClientRetry.accSecurity()`

---

## 🎯 Cara Kerjanya

### Retry Logic
```dart
/// Jika request timeout atau connection error:

Attempt 1
  ↓
Wait 2 seconds (base delay)
  ↓
Attempt 2
  ↓
Wait 4 seconds (2 * base delay)
  ↓
Attempt 3
  ↓
Wait 6 seconds (3 * base delay)
  ↓
Attempt 4
  ↓
If still fails, throw exception
```

### Sleep & Wake Scenario
```
Before Sleep:
  App running, data fetching normally
  ↓
User: Sleep PC
  ↓
Network: Disconnect
  ↓
Current API call: Timeout (auto-retry starts)
  ↓
Attempt 1: FAIL (no network yet)
  ↓
Wait 2s...
  ↓
Attempt 2: FAIL (still disconnected)
  ↓
Wait 4s...
  ↓
User wakes PC
  ↓
Network: Reconnect
  ↓
Attempt 3: SUCCESS! ✓
  ↓
Data shows on UI immediately
```

---

## 📋 Configuration

### Retry Settings (dapat diubah di api_client_retry.dart)

```dart
class ApiClientRetry {
  static const int maxRetries = 3;              // Max retry attempts
  static const Duration timeout = Duration(seconds: 10);  // Per request timeout
  static const Duration retryDelay = Duration(seconds: 2); // Base retry delay
}
```

### Untuk Ubah:
- **Lebih sering retry**: `maxRetries = 5`
- **Timeout lebih lama**: `timeout = Duration(seconds: 15)`
- **Delay lebih cepat**: `retryDelay = Duration(seconds: 1)`

---

## ✨ Features

### 1. Automatic Retry
```
✅ On timeout
✅ On connection refused
✅ On network unreachable
✅ On host unreachable
```

### 2. Exponential Backoff
```
✅ Retry 1: 2 seconds wait
✅ Retry 2: 4 seconds wait (2 * attempts)
✅ Retry 3: 6 seconds wait (3 * attempts)
```

### 3. Error Messages
```
"Request timeout after 10s"
"Connection refused"
"Network unreachable"
→ Semua di-log dan di-retry
```

### 4. Graceful Degradation
```
✅ Retries transparent to user
✅ Shows loading state
✅ No UI freezes
✅ Proper error messages if all retries fail
```

---

## 🧪 Testing Scenarios

### Test 1: Normal Network (Baseline)
```
1. Run app normally
2. Scanner scan barcode
3. Should ACC immediately
4. No delays should happen
```

### Test 2: Slow Network
```
1. App running
2. Toggle airplane mode OFF
3. Scanner scan barcode
4. Should retry & eventually succeed
5. After 3-5 seconds, data shows
```

### Test 3: PC Sleep During Fetch
```
1. App running, fetch logs in background
2. Data loading...
3. User: Sleep PC (Win+X → Sleep)
4. Network disconnects
5. Fetch continues retrying
6. User wakes PC
7. Network reconnects within 10 seconds
8. Fetch succeeds! ✓
9. Data shows on UI
```

### Test 4: PC Sleep - Scanner
```
1. App running
2. PC Sleep
3. User wakes PC
4. Scan barcode with scanner
5. Should handle connection recovery
6. ACC success shows within 5-10 seconds
```

### Test 5: Complete Network Outage
```
1. App running
2. Disconnect WiFi / mobile data
3. Scanner scan barcode
4. Should fail gracefully after 3 retries
5. Error message: "Koneksi error - Cek server"
6. User can retry manually
```

---

## 🔍 Debug Logging

### Logged Info
App akan log semua API activity:

```
[API] fetchLogs() started
[API] Request timeout after 10s
[API] Retrying after sleep (attempt 1/3)
[API] Retry 1 failed: Connection refused
[API] Retrying after sleep (attempt 2/3)
[API] Retry 2 succeeded!
[API] fetchLogs() completed
```

### How to View Logs
1. Run di Android Studio
2. Open Logcat
3. Filter: `[API]`
4. Watch retry attempts

---

## 📊 Performance Impact

### Network Usage
- Minimal additional traffic
- Only retries on failure
- No continuous polling

### Battery Impact
- Minimal (only retry delays)
- ~2-6 seconds per retry
- Better than app timeout & manual refresh

### User Experience
- Transparent (happens in background)
- Shows loading state
- Proper error handling
- Auto-recovery without user action

---

## ⚠️ Known Limitations

### 1. Time-to-Recovery
- PC sleep → wake dapat take 5-10 seconds
- Network reconnect tidak instant
- Retry 3 akan succeed setelah network online

### 2. Server Restart
- Jika server restart saat sleep
- Akan fail all retries
- Error: "Connection refused"

### 3. WiFi Reconnect
- Some WiFi take time to reconnect
- Retry delay may not be enough
- Increase `maxRetries` jika perlu

---

## 🔧 Troubleshooting

### Issue: Still Get Timeout After Wake
**Solution**: Increase `maxRetries` atau `timeout`

```dart
// In api_client_retry.dart
static const int maxRetries = 5;  // Increased from 3
static const Duration timeout = Duration(seconds: 15); // Increased from 10
```

### Issue: Takes Too Long to Retry
**Solution**: Decrease `retryDelay`

```dart
static const Duration retryDelay = Duration(seconds: 1); // Decreased from 2
```

### Issue: Too Much Retry Attempts
**Solution**: Decrease `maxRetries`

```dart
static const int maxRetries = 2; // Decreased from 3
```

---

## 🚀 Future Enhancements

Possible improvements:
1. Add exponential backoff with jitter
2. Implement circuit breaker pattern
3. Cache responses locally
4. Add connection state listener
5. Implement periodic health check

---

## 📝 API Methods Available

All methods have auto-retry:
```
✅ ApiClientRetry.fetchLogs()
✅ ApiClientRetry.accPengawas(id)
✅ ApiClientRetry.accSecurity(id)
✅ ApiClientRetry.dailyReset()
✅ ApiClientRetry.deleteLog(id)
✅ ApiClientRetry.updateLogStatus(id, status_pengawas, status_security)
✅ ApiClientRetry.fetchLogsByDate(date)
✅ ApiClientRetry.checkConnectivity()
```

---

## 🎯 Use Cases

### Use Case 1: Pengawas Scanning
```
1. Pengawas scanning barcodes
2. PC sleep during operation
3. Wake up & scan continues
4. Approval works seamlessly
```

### Use Case 2: Security Check
```
1. Security scanning barcodes
2. Network brief outage
3. App auto-retries
4. Approval processed automatically
```

### Use Case 3: Status Monitoring
```
1. Dashboard showing status
2. PC sleep
3. Auto-retry in background
4. Data refreshes when network back
```

---

## ✅ Testing Checklist

- [ ] Normal operation (no sleep) works
- [ ] Scan during slow network works
- [ ] PC sleep + wake + scan works
- [ ] PC sleep + manual refresh + wake works
- [ ] Network outage handled gracefully
- [ ] Error messages display correctly
- [ ] Retry attempts logged properly
- [ ] No UI freezes during retry
- [ ] Loading state shows properly
- [ ] Success happens automatically after wake

---

## 📞 Support

### Issues
1. Check logs: Filter `[API]` in Logcat
2. Try increase retry attempts
3. Try increase timeout
4. Check server is running

### More Details
See main documentation files:
- QUICKSTART.md
- WINDOWS_SERVICE_SETUP.md
- TRAY_AND_SLEEP_FIXES.md

---

**Status**: ✅ Implementation Complete
**Version**: 1.0.0
**Last Updated**: December 4, 2025
