#!/bin/bash
# Grafana Dashboard Restore Script
# This script restores Grafana dashboards from a backup file

set -e

# Configuration
GRAFANA_URL=${GRAFANA_URL:-"http://grafana:3000"}
GRAFANA_USER=${GRAFANA_USER:-"admin"}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-"admin"}
BACKUP_DIR=${BACKUP_DIR:-"/var/backups/grafana/dashboards"}
LOG_FILE="/var/log/monitoring/grafana-restore.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    exit 1
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Restore Grafana dashboards from backup"
    echo ""
    echo "Options:"
    echo "  -b, --backup BACKUP_FILE  Specify backup file to restore from (required)"
    echo "  -f, --force               Force overwrite of existing dashboards"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Parse command line arguments
BACKUP_FILE=""
FORCE=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -b|--backup)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$BACKUP_FILE" ]; then
    error "Backup file must be specified with -b or --backup"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    else
        error "Backup file $BACKUP_FILE does not exist"
    fi
fi

log "Starting Grafana dashboard restore from $BACKUP_FILE"

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Extract backup file
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# Find the extracted directory
EXTRACTED_DIR=$(find "$TEMP_DIR" -type d | grep -v "^$TEMP_DIR$" | head -n1)

if [ ! -d "$EXTRACTED_DIR" ]; then
    error "Failed to extract backup file"
fi

# Verify metadata
if [ -f "$EXTRACTED_DIR/metadata.json" ]; then
    log "Backup metadata:"
    cat "$EXTRACTED_DIR/metadata.json" | tee -a "$LOG_FILE"
else
    log "Warning: No metadata file found in backup"
fi

# Get Grafana auth token
AUTH_TOKEN=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"restore-script\", \"role\": \"Admin\"}" \
    "$GRAFANA_URL/api/auth/keys" \
    -u "$GRAFANA_USER:$GRAFANA_PASSWORD" | grep -o '"key":"[^"]*' | grep -o '[^"]*$')

if [ -z "$AUTH_TOKEN" ]; then
    error "Failed to get Grafana API token"
fi

log "Successfully obtained Grafana API token"

# Restore each dashboard
SUCCESS_COUNT=0
FAILED_COUNT=0

for DASHBOARD_FILE in "$EXTRACTED_DIR"/*.json; do
    # Skip metadata file
    if [[ "$DASHBOARD_FILE" == *"metadata.json" ]]; then
        continue
    fi
    
    # Read dashboard UID from filename
    DASHBOARD_UID=$(basename "$DASHBOARD_FILE" .json)
    
    log "Restoring dashboard with UID: $DASHBOARD_UID"
    
    # Prepare dashboard JSON for import
    DASHBOARD_JSON=$(cat "$DASHBOARD_FILE" | jq '.dashboard')
    
    if [ "$FORCE" = true ]; then
        # Overwrite existing dashboard
        IMPORT_JSON=$(echo "$DASHBOARD_JSON" | jq '{dashboard: ., overwrite: true, folderId: 0}')
    else
        # Don't overwrite if exists
        IMPORT_JSON=$(echo "$DASHBOARD_JSON" | jq '{dashboard: ., overwrite: false, folderId: 0}')
    fi
    
    # Import dashboard
    RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -d "$IMPORT_JSON" \
        "$GRAFANA_URL/api/dashboards/db")
    
    if echo "$RESPONSE" | grep -q "success"; then
        log "Successfully restored dashboard $DASHBOARD_UID"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log "Failed to restore dashboard $DASHBOARD_UID: $RESPONSE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

log "Restore completed: $SUCCESS_COUNT dashboards restored successfully, $FAILED_COUNT failed"

# Verify restoration
log "Verifying dashboard restoration..."
DASHBOARDS=$(curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
    "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[] | .uid')

for DASHBOARD_FILE in "$EXTRACTED_DIR"/*.json; do
    if [[ "$DASHBOARD_FILE" == *"metadata.json" ]]; then
        continue
    fi
    
    DASHBOARD_UID=$(basename "$DASHBOARD_FILE" .json)
    
    if echo "$DASHBOARDS" | grep -q "$DASHBOARD_UID"; then
        log "Verification: Dashboard $DASHBOARD_UID found in Grafana"
    else
        log "Verification: WARNING - Dashboard $DASHBOARD_UID not found in Grafana"
    fi
done

# Revoke the API token
curl -s -X DELETE -H "Authorization: Bearer $AUTH_TOKEN" \
    "$GRAFANA_URL/api/auth/keys/$AUTH_TOKEN" >/dev/null 2>&1

log "Restore process completed"

