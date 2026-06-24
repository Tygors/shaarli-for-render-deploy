#!/usr/bin/env sh
set -e

# ──────────────────────────────────────────────────
# Shaarli MinIO backup/restore for SQLite persistence
# ──────────────────────────────────────────────────

DATA_DIR="/var/www/shaarli/data"
BACKUP_BUCKET="${MINIO_BACKUP_BUCKET:-shaarli-backup}"
TRIGGER_FILE="/tmp/shaarli-backup-trigger"

do_backup() {
    if [ ! -d "$DATA_DIR" ]; then
        echo "DEBUG: DATA_DIR $DATA_DIR not found" >&2
        return 0
    fi
    echo "DEBUG: Backing up $DATA_DIR/ (dir listing: $(ls $DATA_DIR/ 2>/dev/null | tr '\n' ' '))"
    # Find the database file (sqlite or flat file)
    DB_FILE=""
    for f in datastore.sqlite datastore.php; do
        [ -f "$DATA_DIR/$f" ] && DB_FILE="$DATA_DIR/$f" && break
    done
    if [ -z "$DB_FILE" ]; then
        echo "DEBUG: No database file found in $DATA_DIR" >&2
        return 0
    fi
    size=$(wc -c < "$DB_FILE")
    echo "Backing up $DB_FILE (${size}b)..."
    if echo "$DB_FILE" | grep -q '\.sqlite$'; then
        sqlite3 "$DB_FILE" ".backup $DATA_DIR/.backup_tmp" && \
        mc cp "$DATA_DIR/.backup_tmp" "shaarli-backup/$BACKUP_BUCKET/datastore.sqlite" >/dev/null 2>&1 && \
        rm -f "$DATA_DIR/.backup_tmp" && echo "Backup OK (${size}b)" || echo "WARNING: backup failed" >&2
    else
        # Flat file - copy directly
        mc cp "$DB_FILE" "shaarli-backup/$BACKUP_BUCKET/datastore.php" >/dev/null 2>&1 && echo "Backup OK (${size}b)" || echo "WARNING: backup failed" >&2
    fi
}

# MinIO backup/restore
if command -v mc >/dev/null 2>&1 && [ -n "$MINIO_ENDPOINT" ]; then
    if mc alias set shaarli-backup "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1; then
        echo "MinIO backup alias configured for bucket: $BACKUP_BUCKET"
    else
        echo "WARNING: Failed to configure MinIO backup alias" >&2
    fi

    # Check if any local database file exists; if not, try restore
    if ! ls "$DATA_DIR/datastore.sqlite" "$DATA_DIR/datastore.php" 2>/dev/null | head -1 | grep -q .; then
        for remote in datastore.sqlite datastore.php; do
            if mc stat "shaarli-backup/$BACKUP_BUCKET/$remote" >/dev/null 2>&1; then
                echo "Restoring $remote from backup..."
                mkdir -p "$DATA_DIR"
                mc cp "shaarli-backup/$BACKUP_BUCKET/$remote" "$DATA_DIR/$remote" >/dev/null 2>&1 && echo "Restore complete ($remote)" && break || echo "WARNING: restore failed ($remote)" >&2
            fi
        done
    fi

    # Initial backup 30s after startup (catches databases created by Shaarli)
    (
        sleep 30
        echo "DEBUG: Running initial backup..."
        do_backup && echo "DEBUG: Initial backup done" || echo "WARNING: initial backup failed" >&2
    ) &

    # Scheduled backup (every 12 minutes)
    (
        while true; do
            sleep "${MINIO_BACKUP_INTERVAL:-720}"
            do_backup && echo "Scheduled backup complete" || echo "WARNING: scheduled backup failed" >&2
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

    echo "Backup system started (initial: 90s, scheduled: ${MINIO_BACKUP_INTERVAL:-720}s, trigger: 60s)"
fi

# Run s6 service manager in background so we can trap shutdown signals
/usr/bin/s6-svscan /etc/services.d &
S6_PID=$!

# Trap SIGTERM to run final backup before shutdown
trap 'echo "Shutting down, running final backup..."; do_backup; echo "Final backup complete"; kill $S6_PID 2>/dev/null; exit 0' TERM INT

wait $S6_PID
