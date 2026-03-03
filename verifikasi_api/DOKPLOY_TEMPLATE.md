# Dokploy Deployment Template - verifikasi_api

Template ini untuk deploy `verifikasi_api` sebagai **Application** (bukan Compose) di Dokploy.

## 1) Create Application

Gunakan service type: `Application`.

## 2) General Tab

### Source

- Provider: `Git` / `GitHub` / `GitLab`
- Repository: `https://...` (repo kamu)
- Branch: `main` (atau branch production kamu)
- Auto Deploy: `ON` (recommended)

### Build Path (recommended)

- Build Path: `/verifikasi_api`

> Dengan Build Path di atas, field Docker cukup pakai path lokal folder `verifikasi_api`.

## 3) Build Type Tab

- Build Type: `Dockerfile`
- Dockerfile Path: `Dockerfile`
- Docker Context Path: `.`
- Docker Build Stage: *(kosongkan)*

## 4) Environment Tab

Tambahkan environment variables berikut:

```env
PORT=8080
DB_PATH=/data/log.db
```

Opsional:

```env
TZ=Asia/Jakarta
```

## 5) Advanced Tab -> Volumes

Tambahkan mount persisten:

- Type: `Volume Mount`
- Volume Name: `verifikasi_api_data`
- Mount Path: `/data`

## 6) Domains Tab

Tambahkan domain API:

- Host: `api.domainkamu.com`
- Path: `/`
- Internal Path: *(kosong)*
- Strip Path: `OFF`
- Container Port: `8080`
- HTTPS: `ON`
- Certificate: `letsencrypt`

## 7) DNS (di provider domain)

Buat record:

- Type: `A`
- Name: `api` (atau sesuai subdomain)
- Value: `IP_PUBLIC_VPS`

## 8) Deploy

Klik `Deploy` lalu cek:

- `https://api.domainkamu.com/logs`
- Harus return JSON seperti:

```json
{"logs":[]}
```

## Quick Alternative (if Build Path not used)

Kalau kamu tidak pakai Build Path `/verifikasi_api`, pakai konfigurasi ini:

- Dockerfile Path: `verifikasi_api/Dockerfile`
- Docker Context Path: `verifikasi_api`

## Notes

- Simpan data SQLite di `/data` agar tidak hilang saat redeploy.
- Jangan expose port via `Advanced -> Ports` jika sudah pakai `Domains` (routing cukup lewat Traefik/domain).
