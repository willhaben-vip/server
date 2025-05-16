#!/bin/bash
# Prometheus Data Restore Script
# This script restores Prometheus data from a backup file.

set -e

# Configuration
PROMETHEUS_URL=${PROMETHEUS_URL:-"http://prometheus:9090"}
BACKUP_DIR=${BACKUP_DIR:-"/var/backups/prometheus"}
PROMETHEUS_DATA_DIR="/prometheus"
LOG_FILE="/var/log/monitoring/prometheus-restore.log"

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
    echo "Restore Prometheus data from backup"
    echo ""
    echo "Options:"
    echo "  -b, --backup BACKUP_FILE  Specify backup file to restore from (required)"
    echo "  -t, --type TYPE           Specify backup type (full or snapshot), will be auto-detected if not specified"
    echo "  -f, --force               Force restore without confirmation"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Parse command line arguments
BACKUP_FILE=""
BACKUP_TYPE=""
FORCE=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -b|--backup)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -t|--type)
            BACKUP_TYPE="$2"
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

# Auto-detect backup type if not specified
if [ -z "$BACKUP_TYPE" ]; then
    if [[ "$BACKUP_FILE" == *"full_"* ]]; then
        BACKUP_TYPE="full"
    elif [[ "$BACKUP_FILE" == *"snapshot_"* ]]; then
        BACKUP_TYPE="snapshot"
    else
        error "Could not auto-detect backup type. Please specify with -t option."
    fi
    log "Auto-detected backup type: $BACKUP_TYPE"
fi

log "Starting Prometheus data restore from $BACKUP_FILE (type: $BACKUP_TYPE)"

# Confirm restore if not forced
if [ "$FORCE" != true ]; then
    echo "WARNING: This will restore Prometheus data and overwrite existing data."
    echo "Prometheus will be stopped during the restore process."
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore aborted by user"
        exit 0
    fi
fi

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
if [ -f "$EXTRACTED_DIR/backup_metadata.json" ]; then
    log "Backup metadata:"
    cat "$EXTRACTED_DIR/backup_metadata.json" | tee -a "$LOG_FILE"
else
    log "Warning: No metadata file found in backup"
fi

# Stop Prometheus
log "Stopping Prometheus service"
docker-compose stop prometheus || error "Failed to stop Prometheus"

# Wait for Prometheus to stop completely
sleep 5

# Backup current data dir before restoring (just in case)
CURRENT_BACKUP="$PROMETHEUS_DATA_DIR.bak.$(date +%Y%m%d_%H%M%S)"
log "Backing up current Prometheus data to $CURRENT_BACKUP"
mv "$PROMETHEUS_DATA_DIR" "$CURRENT_BACKUP" || error "Failed to backup current data"
mkdir -p "$PROMETHEUS_DATA_DIR"

# Restore data based on backup type
if [ "$BACKUP_TYPE" = "full" ]; then
    log "Restoring from full backup"
    # Copy all data except the backup metadata file
    find "$EXTRACTED_DIR" -mindepth 1 -not -name "backup_metadata.json" -exec cp -r {} "$PROMETHEUS_DATA_DIR/" \; || 
        error "Failed to restore Prometheus data"
elif [ "$BACKUP_TYPE" = "snapshot" ]; then
    log "Restoring from snapshot backup"
    # Find the snapshot directory
    SNAPSHOT_DIR=$(find "$EXTRACTED_DIR" -type d -name "*.snapshot" | head -n1)
    
    if [ -z "$SNAPSHOT_DIR" ]; then
        error "No snapshot directory found in backup"
    fi
    
    # Create snapshots directory if it doesn't exist
    mkdir -p "$PROMETHEUS_DATA_DIR/snapshots"
    
    # Copy snapshot
    cp -r "$SNAPSHOT_DIR" "$PROMETHEUS_DATA_DIR/snapshots/" || 
        error "Failed to restore Prometheus snapshot"
else
    error "Unknown backup type: $BACKUP_TYPE"
fi

# Set correct permissions
chmod -R 777 "$PROMETHEUS_DATA_DIR" || log "Warning: Failed to set permissions on data directory"

# Start Prometheus
log "Starting Prometheus service"
docker-compose start prometheus || error "Failed to start Prometheus"

# Wait for Prometheus to start
sleep 10

# Verify Prometheus is running
if ! curl -s "$PROMETHEUS_URL/-/healthy" | grep -q "Prometheus"; then
    log "Warning: Prometheus may not be running after restore, rolling back"
    
    # Stop Prometheus
    docker-compose stop prometheus
    
    # Roll back
    rm -rf "$PROMETHEUS_DATA_DIR"
    mv "$CURRENT_BACKUP" "$PROMETHEUS_DATA_DIR"
    
    # Restart Prometheus
    docker-compose start prometheus
    
    error "Prometheus failed to start after restore, rolled back to previous state"
fi

# Cleanup
log "Removing backup of current data"
rm -rf "$CURRENT_BACKUP"

# Export metrics for monitoring (if Prometheus node_exporter textfile collector is enabled)
if [ -d "/var/lib/node_exporter/textfile" ]; then
    METRICS_FILE="/var/lib/node_exporter/textfile/prometheus_restore.prom"
    
    echo "# HELP prometheus_restore_success Whether the last restore succeeded (1) or failed (0)" > "$METRICS_FILE"
    echo "# TYPE prometheus_restore_success gauge" >> "$METRICS_FILE"
    echo "prometheus_restore_success{type=\"$BACKUP_TYPE\"} 1" >> "$METRICS_FILE"
    
    echo "# HELP prometheus_restore_timestamp_seconds Timestamp of the last restore" >> "$METRICS_FILE"
    echo "# TYPE prometheus_restore_timestamp_seconds gauge" >> "$METRICS_FILE"
    echo "prometheus_restore_timestamp_seconds{type=\"$BACKUP_TYPE\"} $(date +%s)" >> "$METRICS_FILE"
    
    log "Metrics exported to $METRICS_FILE"
fi

log "Restore process completed successfully"

