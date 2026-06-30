# Setup Push Notifikasi FCM (Firebase Cloud Messaging)

Push asli yang bekerja **walau aplikasi ditutup**. Server mendeteksi izin toilet yang
waktunya habis lalu mengirim notifikasi ke HP security lewat FCM.

Arsitektur:
1. HP security login → aplikasi mendaftarkan **FCM token** ke server (`POST /devices/register`).
2. Server menjalankan scheduler tiap **30 detik**, mengecek `toilet_permit` yang sudah
   `SCANNED` & lewat `expires_at` → mengirim push ke semua token role `security`.
3. Karena push dikirim dari server, notifikasi tetap sampai meski aplikasi tertutup.

---

## A. Sisi aplikasi (verifikasi_mobile)

### 1. Tambahkan `google-services.json`
Dari Firebase Console → Project Settings → **Your apps** → Android app.

- Pastikan **package name** Android app di Firebase = `com.example.verifikasi_mobile`
  (lihat `android/app/build.gradle.kts` → `applicationId`).
  Kalau belum ada, tambahkan app Android baru dengan package name itu.
- Download `google-services.json`, taruh di:
  ```
  verifikasi_mobile/android/app/google-services.json
  ```

> ⚠️ Tanpa file ini, build Android akan **gagal** (plugin google-services mewajibkannya).
> File ini berisi config publik, tapi tetap sudah otomatis di-ignore git (lihat catatan di bawah).

### 2. Build ulang aplikasi
Dependency & konfigurasi gradle sudah ditambahkan otomatis:
- `pubspec.yaml`: `firebase_core`, `firebase_messaging`
- `android/settings.gradle.kts` & `android/app/build.gradle.kts`: plugin `com.google.gms.google-services`
- `AndroidManifest.xml`: izin `POST_NOTIFICATIONS`, `VIBRATE`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`

Jalankan:
```bash
cd verifikasi_mobile
flutter clean
flutter pub get
flutter build apk --release
```

---

## B. Sisi server (verifikasi_api)

### 1. Ambil Service Account
Firebase Console → Project Settings → **Service accounts** →
**Generate new private key** → unduh file JSON (mis. `serviceAccount.json`).

> 🔒 File ini RAHASIA (berisi private key). Jangan commit ke GitHub.

### 2. Set environment variable di Dokploy
Buka aplikasi `verifikasi_api` di Dokploy → tab **Environment**, tambahkan:

| Variable | Nilai |
|---|---|
| `FCM_SERVICE_ACCOUNT_JSON` | **seluruh isi** file `serviceAccount.json` (di-minify jadi 1 baris) |
| `FCM_PROJECT_ID` | *(opsional)* project id Firebase. Kalau kosong, diambil dari JSON. |

Cara mudah minify JSON jadi 1 baris (PowerShell):
```powershell
(Get-Content serviceAccount.json -Raw | ConvertFrom-Json | ConvertTo-Json -Compress)
```
Salin hasilnya ke nilai `FCM_SERVICE_ACCOUNT_JSON`.

**Alternatif** (kalau pakai file mount, bukan env JSON):
- Mount file `serviceAccount.json` ke container, lalu set
  `FCM_SERVICE_ACCOUNT_PATH=/data/serviceAccount.json`.

### 3. Redeploy
Setelah redeploy, cek **Logs** harus muncul:
```
[FCM] Configured for project "namaproject-xxxx".
[FCM] Expiry push scheduler started (every 30s).
```
Kalau muncul `[FCM] Not configured ...` berarti env belum terbaca.

---

## C. Cara menguji
1. Login sebagai **security** di HP → token otomatis terdaftar.
   (Cek opsional: `GET /admin/...` belum ada endpoint lihat token; bisa cek tabel `device_tokens` langsung di DB.)
2. Buat izin toilet (pengawas approve → security proof-scan) dengan durasi singkat (mis. 1 menit).
3. **Tutup aplikasi** di HP security.
4. Tunggu sampai durasi habis + maksimal 30 detik → notifikasi "Waktu toilet sudah habis" muncul.

---

## D. Catatan teknis
- Notifikasi dikirim **sekali per izin** (`expiry_notified=1`). Proof-scan ulang me-reset flag.
- Token tidak valid (HP uninstall / token kedaluwarsa) otomatis dihapus dari `device_tokens`.
- Channel Android FCM = `toilet_expiry_channel` (sama dengan local notification).
- Saat aplikasi **terbuka** (foreground), notifikasi ditampilkan via local notification
  (`FcmService._handleForegroundMessage`). Saat **tertutup/background**, sistem Android
  menampilkannya otomatis dari payload `notification`.
- Polling lama (`ToiletExpiryMonitorService` 10 detik + WorkManager 15 menit) tetap ada
  sebagai cadangan; FCM adalah jalur utama untuk app-tertutup.

## E. Keamanan file
Tambahkan ke `.gitignore` masing-masing agar tidak ter-push:
- `verifikasi_mobile/android/app/google-services.json`
- `serviceAccount.json` (di mana pun Anda menaruhnya)
