# Verifikasi API (Headless)

Service ini adalah versi headless dari API `verifikasi_server` agar bisa dijalankan di VPS Linux (Dokploy/Docker) dengan perilaku endpoint yang sama.

## Endpoint yang tersedia

Semua endpoint utama disamakan dengan server desktop:

- `POST /auth/login`
- `POST /scan-pengawas`
- `POST /scan-security`
- `POST /toilet-permit/approve`
- `POST /toilet-permit/proof-scan`
- `GET /status/<id>`
- `GET /logs`
- `GET /logs/`
- `GET /toilet-permits`
- `GET /toilet-permit/status/<id>`
- `GET /logs-history/<tanggal>`
- `GET /toilet-permits-history/<tanggal>`
- `GET /dates-history`
- `POST /daily-reset`
- `POST /logs`
- `GET /logs/<id>`
- `PUT /logs/<id>`
- `DELETE /logs/<id>`
- `POST /admin/login`
- `GET /admin/users`
- `POST /admin/users`
- `PUT /admin/users/<id>`
- `DELETE /admin/users/<id>`
- `POST /admin/clear-logs`
- `POST /admin/clear-all-data`

## Jalankan lokal (tanpa Docker)

```bash
dart pub get
dart run bin/server.dart
```

Environment opsional:

- `PORT` (default: `8080`)
- `DB_PATH` (default: `data/log.db`)
- contoh file: `.env.example`

Contoh:

```bash
PORT=8080 DB_PATH=data/log.db dart run bin/server.dart
```

## Build dan run dengan Docker

```bash
docker build -t verifikasi-api:latest .
docker run -d --name verifikasi-api -p 8080:8080 -e PORT=8080 -e DB_PATH=/data/log.db -v verifikasi_api_data:/data verifikasi-api:latest
```

## Deploy ke Dokploy

Template field-by-field:

- lihat [DOKPLOY_TEMPLATE.md](./DOKPLOY_TEMPLATE.md)

1. Push folder ini ke repo git.
2. Di Dokploy, buat `Application` baru (Dockerfile build).
3. Set:
   - Build Context: `verifikasi_api`
   - Dockerfile: `verifikasi_api/Dockerfile`
4. Tambah environment:
   - `PORT=8080`
   - `DB_PATH=/data/log.db`
5. Tambah volume persistent:
   - Mount path: `/data`
6. Tambah domain dan route ke port container `8080`.
7. Update `Server URL` di aplikasi mobile ke domain API (HTTPS).

## Catatan fitur izin toilet

- Tidak perlu environment variable tambahan untuk fitur ini.
- Tabel `toilet_permit` dan `toilet_permit_history` dibuat otomatis saat service boot.
- Smoke test minimal setelah deploy:
  - `GET /logs`
  - `GET /toilet-permits`

## Data karyawan & shift (lookup dari QR)

Master karyawan (dari Excel) dan shift dominan bulan lalu (dari presensi) disimpan di
tabel `employees`, `employee_shift_month`, dan `import_batches`.

Import (default DRY-RUN; tambah `--commit` untuk menyimpan). Master dulu, baru presensi:

```bash
dart run bin/import_employees.dart master --file "DATA KARYAWAN.xlsx" --sheet "DATA KARYAWAN" --report master.json
dart run bin/import_employees.dart presensi --file PRESENSI.xlsx --sheet OKTOBER --report presensi.json
```

- Penghubung master dan presensi adalah **PIN**. Batas shift: jam masuk sebelum 12:00 = PAGI, selain itu SORE.
  Shift per karyawan = yang dominan (minimal 60% dan minimal 5 hari hadir), selain itu `TIDAK_PASTI`.
- Shift manual: tambahkan kolom `SHIFT` (PAGI/SORE) di sheet master; nilainya menimpa shift presensi.
- Di Docker: `docker exec -it <container> /app/import_employees master --file /data/master.xlsx --db /data/log.db`

Endpoint (tanpa login, tidak mengembalikan NIK/alamat):

- `POST /employee/lookup` body `{"q": "<isi QR>"}` atau `{"employee_id": 12}` (untuk memilih saat `AMBIGUOUS`)
- Status: `FOUND`, `AMBIGUOUS`, `NOT_FOUND`. Rate limit 120/menit/IP.
- Env opsional `LOOKUP_API_KEY`: bila diisi, header `x-api-key` wajib.
