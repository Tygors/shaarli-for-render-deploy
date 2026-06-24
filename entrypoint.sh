#!/usr/bin/env sh
set -e

# ──────────────────────────────────────────────────
# Shaarli MinIO backup/restore for flat-file persistence
# ──────────────────────────────────────────────────

DATA_DIR="/var/www/shaarli/data"
BACKUP_BUCKET="${MINIO_BACKUP_BUCKET:-shaarli-backup}"
TRIGGER_FILE="/tmp/shaarli-backup-trigger"
BACKED=""

do_backup() {
    # Find and backup datastore.php (preferred) or datastore.sqlite
    for name in datastore.php datastore.sqlite; do
        if [ -f "$DATA_DIR/$name" ]; then
            mc cp "$DATA_DIR/$name" "shaarli-backup/$BACKUP_BUCKET/$name" >/dev/null 2>&1 && \
            BACKED="yes" && echo "Backed up $name ($(wc -c < "$DATA_DIR/$name")b)" || echo "WARNING: backup failed" >&2
            return 0
        fi
    done
}

# MinIO backup/restore
if command -v mc >/dev/null 2>&1 && [ -n "$MINIO_ENDPOINT" ]; then
    mc alias set shaarli-backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1 && \
        echo "MinIO backup alias configured for bucket: $BACKUP_BUCKET" || \
        echo "WARNING: Failed to configure MinIO backup alias" >&2

    # Restore from MinIO if no local database
    if ! ls "$DATA_DIR/datastore."* 2>/dev/null | head -1 | grep -q .; then
        for name in datastore.php datastore.sqlite; do
            mc stat "shaarli-backup/$BACKUP_BUCKET/$name" >/dev/null 2>&1 && {
                echo "Restoring $name from backup..."
                mkdir -p "$DATA_DIR"
                mc cp "shaarli-backup/$BACKUP_BUCKET/$name" "$DATA_DIR/$name" >/dev/null 2>&1
                chown nginx:nginx "$DATA_DIR/$name" 2>/dev/null
                echo "Restore complete"
                break
            } 2>/dev/null
        done
    fi

    # 12-minute scheduled backup (catch-all)
    (
        while true; do
            sleep "${MINIO_BACKUP_INTERVAL:-720}"
            do_backup
        done
    ) &

    # 60-second trigger/initial backup watcher
    (
        while true; do
            sleep 60
            if [ -f "$TRIGGER_FILE" ] || [ -z "$BACKED" ] && ls "$DATA_DIR/datastore."* 2>/dev/null | head -1 | grep -q .; then
                rm -f "$TRIGGER_FILE"
                do_backup
            fi
        done
    ) &
fi

# Run s6 service manager in background, trap shutdown signals
/usr/bin/s6-svscan /etc/services.d &
S6_PID=$!

trap 'echo "Shutting down, running final backup..."; do_backup; echo "Final backup complete"; kill $S6_PID 2>/dev/null; exit 0' TERM INT

wait $S6_PID
