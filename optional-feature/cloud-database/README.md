# Cloud Database (MariaDB) — Deployment Guide

Share download history across **multiple PCs** by hosting the database on a
cloud server instead of local SQLite.

```
┌────────────┐          ┌──────────────────────────┐          ┌────────────┐
│   PC 1     │─────────▶│  MariaDB server (cloud)   │◀─────────│   PC 2     │
│ yt-downloader│  DB_URI │  docker-compose.mariadb │  DB_URI  │ yt-downloader│
└────────────┘          └──────────────────────────┘          └────────────┘
```

> Only **history** is shared. Downloaded media files stay on the PC that
> downloaded them (`downloads/` is not synced).

---

## Prerequisites

- Docker / Docker Compose v2 on the **cloud server**.
- A cloud host / VPS with a public IP (e.g. DigitalOcean, Hetzner, AWS, Railway, etc.).
- The project sources copied onto the cloud server (only this folder is needed).
- On each PC: the yt-downloader app with the `mariadb-client`-capable image (v3.0.0+).

---

## Step 1 — Deploy MariaDB on the cloud server

```bash
# 1. Enter the cloud database folder
cd optional-feature/cloud-database

# 2. Prepare credentials
cp docker-compose.mariadb.env.example .env
nano .env        # set real DB_USER, DB_PASSWORD, DB_ROOT_PASSWORD

# 3. Start the database and wait until it is "healthy"
docker compose -f docker-compose.mariadb.yml up -d
docker compose -f docker-compose.mariadb.yml ps   # STATUS: healthy

# 4. Confirm the point of connection
docker compose -f docker-compose.mariadb.yml exec mariadb \
  mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_DATABASE" -e "SELECT 1;"
```

On first start the MariaDB image creates:

- database `history` (`DB_DATABASE`)
- app user `gylang` (`DB_USER` / `DB_PASSWORD`), allowed to use the app
- data persisted in the named volume `mariadb_data`

---

## Step 2 — Open MySQL port only to your PCs

Expose TCP **3306** but restrict source IPs in your firewall / cloud
security group to the public IPs of PC 1 and PC 2 — **not** `0.0.0.0/0`.

Examples:

```bash
# firewall-cmd (RedHat family)
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 \
  source address=<PC1_IP> port protocol=tcp port=3306 accept'
sudo firewall-cmd --reload

# ufw (Debian/Ubuntu)
sudo ufw allow from <PC1_IP> to any port 3306
sudo ufw allow from <PC2_IP> to any port 3306
```

---

## Step 3 — Point each PC to the cloud database (`.env`)

On **each** PC, in the app `.env`:

```env
DB_MODE=cloud
DB_URI=mysql://gylang:<your-password>@<CLOUD_IP>:3306/history
```

- `gylang` = `DB_USER` from Step 1
- `<your-password>` = `DB_PASSWORD`
- `<CLOUD_IP>` = public IP of the cloud server
- `history` = `DB_DATABASE`

Then rebuild & run:

```bash
./run.sh          # or: docker compose up -d --build
```

---

## Step 4 — Migrate existing local history (optional, once per PC)

If PC 1 already has rows in its local `history.db`, push them to the cloud DB:

```bash
docker compose exec yt-downloader /app/db_history.sh migrate-cloud
```

Expected output:

```
[DB] Migrated <N> rows from /app/.yt-dlp-config/history.db to cloud (gylang@<CLOUD_IP>).
```

It is idempotent — duplicate URLs are skipped (`url` is `UNIQUE`).

---

## Verify it worked

Run on **both** PCs — you must see the same data:

```bash
docker compose exec yt-downloader /app/db_history.sh stats
docker compose exec yt-downloader /app/db_history.sh recent 10
```

Duplicate-detection is now global: download a URL on PC 1, then enqueue the
same URL on PC 2 → PC 2 prints `[SKIP] Already downloaded on ...`.

---

## Backup

```bash
# On the cloud server
docker compose -f docker-compose.mariadb.yml exec mariadb \
  sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" history' \
  > history_backup.sql

# Restore
docker compose -f docker-compose.mariadb.yml exec -T mariadb \
  sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" history' < history_backup.sql
```

---

## Security checklist

- [ ] Port 3306 exposed **only** to PC 1 & PC 2 IPs.
- [ ] `DB_PASSWORD` and `DB_ROOT_PASSWORD` are strong and unique.
- [ ] `.env` on the cloud server is git-ignored / outside the repo.
- [ ] Backups scheduled (database matters — not just downloads).
- [ ] Keep the app's `DB_URI` in `.env`, never in code (`*.env` is git-ignored).
