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
