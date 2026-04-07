#!/usr/bin/env bash
# ============================================================
# Backup script - DB dumps, site content, Traefik certs
# Creates local backup, then syncs to Hetzner Storage Box
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
BACKUP_DIR="${PROJECT_DIR}/backups/${TIMESTAMP}"

source "${PROJECT_DIR}/.env"

mkdir -p "$BACKUP_DIR"

echo "=== Creating backup: $BACKUP_DIR ==="

# MariaDB databases
docker exec mariadb mariadb-dump -u root -p"${MARIADB_ROOT_PASSWORD}" "${WP1_DB_NAME}" | gzip > "$BACKUP_DIR/wordpress1-db.sql.gz"
echo ">>> WordPress 1 DB backed up"

docker exec mariadb mariadb-dump -u root -p"${MARIADB_ROOT_PASSWORD}" "${WP2_DB_NAME}" | gzip > "$BACKUP_DIR/wordpress2-db.sql.gz"
echo ">>> WordPress 2 DB backed up"

# PostgreSQL databases
docker exec postgres pg_dump -U "${POSTGRES_USER:-postgres}" "${UMAMI_DB_NAME:-umami}" | gzip > "$BACKUP_DIR/umami-db.sql.gz"
echo ">>> Umami analytics DB backed up"

docker exec postgres pg_dump -U "${POSTGRES_USER:-postgres}" "${N8N_DB_NAME:-n8n}" | gzip > "$BACKUP_DIR/n8n-db.sql.gz"
echo ">>> n8n DB backed up"

# WordPress uploads (themes, plugins, uploads)
docker cp wordpress1:/var/www/html/wp-content - | gzip > "$BACKUP_DIR/wordpress1-wp-content.tar.gz"
echo ">>> WordPress 1 wp-content backed up"

docker cp wordpress2:/var/www/html/wp-content - | gzip > "$BACKUP_DIR/wordpress2-wp-content.tar.gz"
echo ">>> WordPress 2 wp-content backed up"

# Traefik certificates
docker cp traefik:/certs/acme.json "$BACKUP_DIR/acme.json" 2>/dev/null || echo ">>> No acme.json found (skipped)"

# Uptime Kuma database (MariaDB)
docker exec mariadb mariadb-dump -u root -p"${MARIADB_ROOT_PASSWORD}" "${UPTIME_KUMA_DB_NAME:-uptime_kuma}" | gzip > "$BACKUP_DIR/uptime-kuma-db.sql.gz"
echo ">>> Uptime Kuma DB backed up"

# Grafana database
docker cp grafana:/var/lib/grafana/grafana.db "$BACKUP_DIR/grafana.db" 2>/dev/null || echo ">>> No grafana.db found (skipped)"

# Authelia database
docker cp authelia:/config/db.sqlite3 "$BACKUP_DIR/authelia.db" 2>/dev/null || echo ">>> No Authelia DB found (skipped)"

echo "=== Local backup complete: $BACKUP_DIR ==="

# ============================================================
# Sync to Hetzner Storage Box (offsite backup)
# ============================================================
if [[ -n "${STORAGEBOX_USER:-}" && -n "${STORAGEBOX_HOST:-}" ]]; then
    STORAGEBOX_PORT="${STORAGEBOX_PORT:-23}"
    STORAGEBOX_PATH="${STORAGEBOX_PATH:-./backups}"

    echo "=== Syncing to Hetzner Storage Box ==="

    ssh -p "$STORAGEBOX_PORT" "${STORAGEBOX_USER}@${STORAGEBOX_HOST}" "mkdir -p ${STORAGEBOX_PATH}/${TIMESTAMP}"

    rsync -avz --progress \
        -e "ssh -p ${STORAGEBOX_PORT}" \
        "$BACKUP_DIR/" \
        "${STORAGEBOX_USER}@${STORAGEBOX_HOST}:${STORAGEBOX_PATH}/${TIMESTAMP}/"

    echo ">>> Offsite sync complete"

    # Clean up old remote backups (keep last 30 days)
    ssh -p "$STORAGEBOX_PORT" "${STORAGEBOX_USER}@${STORAGEBOX_HOST}" \
        "find ${STORAGEBOX_PATH} -maxdepth 1 -type d -name '20*' -mtime +30 -exec rm -rf {} \;" \
        2>/dev/null || echo ">>> Remote cleanup skipped"

    echo "=== Offsite backup complete ==="
else
    echo ">>> Skipping offsite backup (STORAGEBOX_USER/STORAGEBOX_HOST not set in .env)"
fi

# Cleanup old local backups (keep last 7 days locally, 30 days on storage box)
find "${PROJECT_DIR}/backups" -maxdepth 1 -type d -name "20*" -mtime +7 -exec rm -rf {} \;
echo ">>> Old local backups cleaned up (keeping 7 days locally)"
