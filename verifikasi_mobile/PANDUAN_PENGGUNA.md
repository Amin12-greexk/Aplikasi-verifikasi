# Panduan Pengguna (Manual Book) - Aplikasi Verifikasi

Aplikasi Verifikasi adalah sistem mobile berbasis Android/iOS yang dirancang untuk memfasilitasi dan mencatat proses alur kepulangan karyawan serta izin ke toilet di lingkungan kerja. Aplikasi ini menggunakan pemindaian (scan) QR Code atau Barcode melalui kamera perangkat.

---

## 1. Hak Akses dan Peran (Role)

Aplikasi ini menggunakan sistem berbasis peran (Role-Based Access Control) yang menentukan wewenang pengguna dalam menggunakan fitur aplikasi:

1. **Pengawas (Supervisor)**
   - Bertugas sebagai pemberi persetujuan (ACC) pertama untuk kepulangan maupun izin toilet.
   - Pindai (scan) QR karyawan oleh Pengawas akan menandai status izin/kepulangan menjadi **"Approved by Pengawas"** (Disetujui Pengawas).
2. **Security (Keamanan)**
   - Bertugas sebagai pemeriksa/validasi akhir di pos atau pintu keluar.
   - Pindai (scan) QR karyawan oleh Security hanya bisa dilakukan **setelah** karyawan mendapat ACC dari Pengawas.
   - Pada Izin Toilet, pindai oleh Security akan **memulai timer** tenggat waktu karyawan berada di toilet.
3. **Admin / IT**
   - Memiliki akses untuk fitur tambahan seperti Koreksi Data, merevisi data yang salah, atau melakukan penyesuaian data setoran/log.

---

## 2. Memulai Aplikasi

### 2.1. Pengaturan Server (URL API)
Jika aplikasi baru pertama kali diinstal atau ada perubahan alamat server:
1. Buka aplikasi.
2. Pada layar Login, tekan ikon **Pengaturan (Gear)** di pojok layar.
3. Masukkan **URL Server** dan **API Key** yang valid (disediakan oleh tim IT).
4. Tekan **Simpan**.

### 2.2. Login
1. Masukkan **Username** dan **Password** Anda.
2. Tekan tombol **Login**.
3. Aplikasi akan mengenali otomatis apakah Anda masuk sebagai Pengawas atau Security.

---

## 3. Menu Verifikasi Pulang

Menu ini digunakan untuk mengatur alur kepulangan karyawan secara teratur.

Masuk ke tab **Verifikasi** di bagian bawah layar, lalu pilih kartu **Verifikasi Pulang**.

### A. Scan Pulang
1. Pilih menu **Scan Pulang**.
2. Arahkan kamera ke QR Code / Barcode yang ada pada ID Card atau Tiket Karyawan.
3. Jika Anda **Pengawas**: Pindai QR untuk menyetujui karyawan pulang. Akan muncul notifikasi "Berhasil".
4. Jika Anda **Security**: Pindai QR karyawan. Layar akan menampilkan notifikasi "Berhasil" jika Pengawas sudah meng-ACC. Jika Pengawas belum meng-ACC, pemindaian akan ditolak.

### B. Status Pulang
1. Pilih menu **Status Pulang**.
2. Anda bisa memantau daftar karyawan yang sedang dalam proses pulang hari ini.
3. Status yang tersedia:
   - **Menunggu Security (Kuning/Biru)**: Sudah di-ACC Pengawas, sedang menuju pos Security.
   - **Selesai (Hijau)**: Sudah di-scan oleh Pengawas dan Security. Karyawan sudah keluar.

### C. Riwayat Pulang
1. Pilih menu **Riwayat Pulang**.
2. Menampilkan log riwayat pemindaian kepulangan.
3. Anda bisa menekan **ikon kalender** untuk melihat riwayat pada tanggal sebelumnya.

---

## 4. Menu Izin Toilet

Menu ini digunakan untuk melacak dan membatasi durasi karyawan yang pergi ke toilet saat jam kerja.

Masuk ke tab **Verifikasi** di bagian bawah layar, lalu pilih kartu **Izin Toilet**.

### A. Scan Toilet
1. Pilih menu **Scan Toilet**.
2. **Pengawas** memindai QR karyawan untuk memberikan izin.
3. **Security** memindai QR karyawan saat karyawan secara fisik melewati pos untuk ke toilet.
4. **Catatan Penting**: Saat Security memindai QR, **Timer Toilet akan otomatis berjalan**!

### B. Status Toilet
1. Pilih menu **Status Toilet**.
2. Menampilkan daftar karyawan yang sedang meminta izin atau sedang berada di toilet.
3. Status yang tersedia:
   - **Menunggu Scan Security**: Pengawas sudah memberi izin, tetapi karyawan belum sampai di pos Security. Timer belum berjalan.
   - **Selesai / Sedang Berjalan**: Security sudah memindai, timer hitung mundur (countdown) akan terlihat berjalan secara real-time.
   - **Waktu Habis (Merah)**: Durasi izin toilet telah melewati batas waktu yang ditentukan (misalnya 10/15 menit).

### C. Riwayat Toilet
1. Pilih menu **Riwayat Toilet**.
2. Anda dapat melihat log lengkap karyawan yang pergi ke toilet, jam berapa mulai, jam disetujui, dan pengawasnya.
3. Anda bisa menggunakan filter rentang tanggal.

---

## 5. Fitur Sinkronisasi Offline (Otomatis)

Aplikasi dirancang untuk bisa berjalan di area *Blank Spot* (Area tidak ada sinyal internet).
1. Jika Anda sedang berada di area tanpa sinyal dan memindai QR Karyawan, pemindaian **TIDAK AKAN** gagal total.
2. Aplikasi akan memunculkan status: **"Disimpan offline — akan dikirim saat koneksi pulih"** (Warna Kuning).
3. Data akan disimpan secara lokal di HP Anda.
4. Begitu Anda mendapatkan sinyal internet kembali, aplikasi akan secara otomatis **mengirim paksa (flush)** semua antrean scan offline ke server di latar belakang. Anda tidak perlu melakukan scan ulang.

---

## 6. Menu Koreksi Data (Khusus Peran Tertentu)

Fitur ini digunakan untuk mereparasi atau memasukkan data pencatatan/log secara manual jika terjadi kesalahan operasional di lapangan.
1. Masuk ke halaman **Koreksi Data**.
2. Gunakan form pencarian untuk mencari nama atau ID karyawan.
3. Mengisi jam atau status pemindaian secara manual (Misal: Override status dari belum diverifikasi menjadi sudah diverifikasi untuk kasus khusus).
4. Riwayat perubahan akan tercatat dalam tabel *History* tepat di bawah form pencarian.

---

## 7. Menu Riwayat (Absensi)

1. Pilih tab **Riwayat** di bagian bawah layar utama.
2. Tab ini difokuskan sebagai hub ringkasan history secara umum, utamanya digunakan untuk menampilkan **Log Absensi** harian.
3. Silakan gunakan Date Picker untuk memfilter data pada hari-hari tertentu.

---

## 8. Profil dan Logout

1. Pilih tab **Profil / Beranda** lalu ketuk nama/foto profil atau tombol pojok layar.
2. Untuk keluar dari akun Anda, pastikan semua pekerjaan selesai dan pemindaian offline telah tersinkronisasi.
3. Tekan **Logout** untuk kembali ke halaman Login.

---
### Tips Penggunaan Kamera Scanner:
- Pastikan pencahayaan cukup saat melakukan pemindaian.
- Anda bisa men-zoom kamera (cubit layar / pinch-to-zoom) saat barcode berukuran kecil.
- Jaga jarak sekitar 10 - 20 cm dari barcode.
- Layar kamera akan memberi tahu bila terdeteksi kamera dikunci *(Processing)* untuk menghindari pemindaian ganda*(double-scan)* secara tak disengaja.

*(Versi Panduan: 1.0)*
