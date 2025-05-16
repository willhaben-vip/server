#!/bin/bash
# Grafana Dashboard Backup Script
# This script backs up all Grafana dashboards to a specified backup directory
# and maintains a retention policy for old backups.

set -e

# Configuration
GRAFANA_URL=${GRAFANA_URL:-"http://grafana:3000"}
GRAFANA_USER=${GRAFANA_USER:-"admin"}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-"admin"}
BACKUP_DIR=${BACKUP_DIR:-"/var/backups/grafana/dashboards"}
RETENTION_DAYS=${RETENTION_DAYS:-30}
LOG_FILE="/var/log/monitoring/grafana-backup.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    exit 1
}

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"
mkdir -p "$BACKUP_PATH"

log "Starting Grafana dashboard backup to $BACKUP_PATH"

# Get Grafana auth token
AUTH_TOKEN=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"backup-script\", \"role\": \"Viewer\"}" \
    "$GRAFANA_URL/api/auth/keys" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" | grep -o '"key":"[^"]*' | grep -o '[^"]*$')

if [ -z "$AUTH_TOKEN" ]; then
    error "Failed to get Grafana API token"
fi

log "Successfully obtained Grafana API token"

# Get list of dashboards
DASHBOARDS=$(curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
    "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[] | .uid')

if [ -z "$DASHBOARDS" ]; then
    log "No dashboards found"
    exit 0
fi

# Backup each dashboard
SUCCESS_COUNT=0
FAILED_COUNT=0

for UID in $DASHBOARDS; do
    log "Backing up dashboard with UID: $UID"
    
    RESPONSE=$(curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
        "$GRAFANA_URL/api/dashboards/uid/$UID")
    
    if echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
        echo "$RESPONSE" > "$BACKUP_PATH/$UID.json"
        
        # Validate JSON file
        if jq -e . "$BACKUP_PATH/$UID.json" >/dev/null 2>&1; then
            log "Successfully backed up dashboard $UID"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            log "Warning: Dashboard backup for $UID appears to be invalid JSON"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        log "Failed to backup dashboard $UID"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Create a metadata file with backup information
cat > "$BACKUP_PATH/metadata.json" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "grafana_url": "$GRAFANA_URL",
    "total_dashboards": $((SUCCESS_COUNT + FAILED_COUNT)),
    "successful_backups": $SUCCESS_COUNT,
    "failed_backups": $FAILED_COUNT
}
EOF

# Create a tar.gz archive of the backup
cd "$BACKUP_DIR"
tar -czf "$TIMESTAMP.tar.gz" "$TIMESTAMP"
rm -rf "$TIMESTAMP"

log "Backup completed: $SUCCESS_COUNT dashboards backed up successfully, $FAILED_COUNT failed"

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

# Revoke the API token
curl -s -X DELETE -H "Authorization: Bearer $AUTH_TOKEN" \
    "$GRAFANA_URL/api/auth/keys/$AUTH_TOKEN" >/dev/null 2>&1

log "Backup process completed"

