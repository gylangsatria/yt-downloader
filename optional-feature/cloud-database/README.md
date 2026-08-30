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

## Step 2 — Keep MySQL off the public internet

The MariaDB container **does not need a host port**. It only has to be
reachable on the docker network that the tunnel/app uses. So by default do
**not** publish `3306` / `3307`.

**Option A — Cloudflare tunnel (recommended: no open port, no firewall access needed)**
- In `docker-compose.mariadb.yml`, do **not add a `ports:` mapping**. The
  container still listens on `3306` *inside* the `cloudflare-tunnel-vps`
  network, so nothing is exposed to the public internet.
- Zero Trust route: `db-yt-downloader.example.tld` → **TCP** → `yt-downloader-db:3306`
  (the in-network port, not a host port).
- On each PC use tunnel mode: `DB_URI=mysql://<user>:<pass>@127.0.0.1:3307/history`
  plus the `CF_TUNNEL_*` / `CF_ACCESS_*` vars (see main README). The app's
  `cloudflared-mysql-tcp` container relays through the tunnel.
- Verify externally: `nmap -sS -p 3306,3307 <CLOUD_IP>` → `filtered`/`closed`, never `open`.

> **No firewall access?** Omit the `ports:` mapping and recreate — no host port
> means nothing is reachable from the internet, regardless of firewall rules.
> This is the fix when you can't touch the security group:
> ```bash
> docker compose -f docker-compose.mariadb.yml down
> # remove 'ports:' from docker-compose.mariadb.yml
> docker compose -f docker-compose.mariadb.yml up -d
> ```

**Option B — Direct VPS IP (only if you can't use a tunnel AND can edit the firewall)**
```yaml
ports:
  - "${DB_PORT:-3306}:3306"
```
Restrict the source to your PC IPs — **not** `0.0.0.0/0`:

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
- `<PORT>` = the port actually exposed on the host if you picked **Option B**
  (e.g. `3307`, matching `${DB_PORT}`), or `127.0.0.1:3307` if you use **Option A** (tunnel,
  see the main README)
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

### Reverse migrate — cloud back to local

To stop using the cloud and go back to `DB_MODE=local` on a PC, pull the cloud
rows into the local SQLite file (keep `DB_MODE=cloud` in `.env` while running,
since the cloud is the source):

```bash
docker compose exec yt-downloader /app/db_history.sh migrate-local
# optional: target another file instead of the default history.db
docker compose exec yt-downloader /app/db_history.sh migrate-local /app/.yt-dlp-config/restore.db
```

Then set `DB_MODE=local` in `.env` and restart the container. `migrate-local`
upserts by unique `url` too, so it is also idempotent.

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

- [ ] **No public MySQL port** — MariaDB has no `ports:` mapping (Option A, tunnel) OR it is open only to your PC IPs (Option B, direct).
- [ ] Verify from outside: `nmap -sS -p 3306,3307 <CLOUD_IP>` shows `filtered`/`closed`.
- [ ] `DB_PASSWORD` and `DB_ROOT_PASSWORD` are strong and unique.
- [ ] App database user has **only** needed grants on its own DB (not `ALL ON *.*`).
- [ ] `.env` on the cloud server is git-ignored / outside the repo.
- [ ] Backups scheduled (database matters — not just downloads).
- [ ] Keep the app's `DB_URI` in `.env`, never in code (`*.env` is git-ignored).
