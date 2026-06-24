#!/usr/bin/env sh
set -e

# ──────────────────────────────────────────────────
# Shaarli MinIO backup/restore for SQLite persistence
# ──────────────────────────────────────────────────

DATA_DIR="/var/www/shaarli/data"
DB_FILE="$DATA_DIR/datastore.sqlite"
BACKUP_BUCKET="${MINIO_BACKUP_BUCKET:-shaarli-backup}"
TRIGGER_FILE="/tmp/shaarli-backup-trigger"

do_backup() {
    if [ ! -f "$DB_FILE" ]; then
        return 0
    fi
    sqlite3 "$DB_FILE" ".backup $DATA_DIR/.backup_tmp" && \
    mc cp "$DATA_DIR/.backup_tmp" "shaarli-backup/$BACKUP_BUCKET/datastore.sqlite" >/dev/null 2>&1 && \
    rm -f "$DATA_DIR/.backup_tmp"
}

# MinIO backup/restore
if command -v mc >/dev/null 2>&1 && [ -n "$MINIO_ENDPOINT" ]; then
    if mc alias set shaarli-backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1; then
        echo "MinIO backup alias configured for bucket: $BACKUP_BUCKET"
    else
        echo "WARNING: Failed to configure MinIO backup alias" >&2
    fi

    if [ ! -f "$DB_FILE" ]; then
        if mc stat "shaarli-backup/$BACKUP_BUCKET/datastore.sqlite" >/dev/null 2>&1; then
            echo "Restoring datastore.sqlite from backup..."
            mkdir -p "$DATA_DIR"
            mc cp "shaarli-backup/$BACKUP_BUCKET/datastore.sqlite" "$DB_FILE" >/dev/null 2>&1 && echo "Restore complete" || echo "WARNING: restore failed" >&2
        fi
    fi

    # Scheduled backup (12 minutes)
    (
        while true; do
            sleep "${MINIO_BACKUP_INTERVAL:-720}"
            do_backup && echo "Backup complete" || echo "WARNING: backup failed" >&2
        done
    ) &

    # Triggered backup (poll every 60s)
    (
        while true; do
            sleep 60
            if [ -f "$TRIGGER_FILE" ]; then
                rm -f "$TRIGGER_FILE"
                do_backup && echo "Triggered backup complete" || echo "WARNING: triggered backup failed" >&2
            fi
        done
    ) &
fi

# Run s6 service manager in background so we can trap shutdown signals
/usr/bin/s6-svscan /etc/services.d &
S6_PID=$!

# Trap SIGTERM to run final backup before shutdown
trap 'echo "Shutting down, running final backup..."; do_backup; echo "Final backup complete"; kill $S6_PID 2>/dev/null; exit 0' TERM INT

wait $S6_PID
