#!/usr/bin/env bash
# Dump the tournament_development database to BACKUP_DIR (default ~/tournament-backups)
# and prune any dump older than RETENTION_DAYS (default 7).
#
# Format: pg_dump custom (binary, compressed). Restore with:
#   docker compose exec -T db pg_restore -U postgres -d tournament_development -c < backup.dump
#
# Crontab entry for every 6 hours (4/day):
#   0 */6 * * * /path/to/repo/script/db_backup.sh >> ~/db_backup.log 2>&1
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/tournament-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DB_NAME="${DB_NAME:-tournament_development}"
DB_USER="${DB_USER:-postgres}"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-db}"

cd "$(dirname "$0")/.."

mkdir -p "$BACKUP_DIR"

ts="$(date +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/tournament-$ts.dump"

echo "[$(date -Iseconds)] Dumping $DB_NAME -> $out"
docker compose exec -T "$COMPOSE_SERVICE" \
  pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$out"

size="$(du -h "$out" | cut -f1)"
echo "[$(date -Iseconds)] Wrote $out ($size)"

echo "[$(date -Iseconds)] Pruning dumps older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'tournament-*.dump' -mtime "+$RETENTION_DAYS" -print -delete

echo "[$(date -Iseconds)] Done."
