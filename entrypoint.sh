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
    local tmp="/tmp/shaarli-backup.tar.gz"
    tar czf "$tmp" -C "$DATA_DIR" . 2>/dev/null && \
    count=$(tar tzf "$tmp" 2>/dev/null | wc -l) && \
    mc cp "$tmp" "shaarli-backup/$BACKUP_BUCKET/data.tar.gz" >/dev/null 2>&1 && \
    rm -f "$tmp" && BACKED="yes" && echo "Backed up data/ ($count files)" || \
    echo "WARNING: backup failed" >&2
}

# MinIO backup/restore
if command -v mc >/dev/null 2>&1 && [ -n "$MINIO_ENDPOINT" ]; then
    mc alias set shaarli-backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1 && \
        echo "MinIO backup alias configured for bucket: $BACKUP_BUCKET" || \
        echo "WARNING: Failed to configure MinIO backup alias" >&2

    # Restore from MinIO if no local data files
    if ! ls "$DATA_DIR/datastore."* 2>/dev/null | head -1 | grep -q .; then
        if mc stat "shaarli-backup/$BACKUP_BUCKET/data.tar.gz" >/dev/null 2>&1; then
            echo "Restoring data/ from backup..."
            mkdir -p "$DATA_DIR"
            mc cp "shaarli-backup/$BACKUP_BUCKET/data.tar.gz" "/tmp/shaarli-restore.tar.gz" >/dev/null 2>&1
            tar xzf "/tmp/shaarli-restore.tar.gz" -C "$DATA_DIR" 2>/dev/null
            chown -R nginx:nginx "$DATA_DIR" 2>/dev/null
            rm -f "/tmp/shaarli-restore.tar.gz"
            echo "Restore complete"
        fi
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
