#!/bin/bash
# Prometheus Data Backup Script
# This script creates backups of Prometheus data using the snapshot API
# and manages a retention policy for old backups.

set -e

# Configuration
PROMETHEUS_URL=${PROMETHEUS_URL:-"http://prometheus:9090"}
BACKUP_DIR=${BACKUP_DIR:-"/var/backups/prometheus"}
SNAPSHOT_DIR="/prometheus/snapshots"
RETENTION_DAYS=${RETENTION_DAYS:-30}
FULL_BACKUP_DAY=${FULL_BACKUP_DAY:-"Sunday"}  # Day of the week for full backups
LOG_FILE="/var/log/monitoring/prometheus-backup.log"

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

# Function to create a snapshot via Prometheus API
create_snapshot() {
    log "Creating Prometheus snapshot via API"
    
    # Call the snapshot API
    RESPONSE=$(curl -s -X POST "$PROMETHEUS_URL/-/snapshot" 2>&1)
    
    if echo "$RESPONSE" | grep -q "success"; then
        SNAPSHOT_NAME=$(echo "$RESPONSE" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
        log "Snapshot created successfully: $SNAPSHOT_NAME"
        echo "$SNAPSHOT_NAME"
    else
        error "Failed to create snapshot: $RESPONSE"
    fi
}

# Function to perform a full backup (stopping Prometheus)
perform_full_backup() {
    log "Performing full backup of Prometheus data"
    
    # Create backup directory with timestamp
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="$BACKUP_DIR/full_$TIMESTAMP"
    mkdir -p "$BACKUP_PATH"
    
    # Stop Prometheus (this would be environment-specific)
    log "Stopping Prometheus service"
    docker-compose stop prometheus 2>&1 | tee -a "$LOG_FILE" || error "Failed to stop Prometheus"
    
    # Wait for Prometheus to stop completely
    sleep 5
    
    # Backup the data directory
    log "Copying Prometheus data directory"
    cp -r /prometheus/. "$BACKUP_PATH/" 2>&1 | tee -a "$LOG_FILE" || error "Failed to copy Prometheus data"
    
    # Create a metadata file with backup information
    cat > "$BACKUP_PATH/backup_metadata.json" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "type": "full",
    "prometheus_url": "$PROMETHEUS_URL",
    "backup_method": "full_copy"
}
EOF
    
    # Create archive
    log "Creating backup archive"
    tar -czf "$BACKUP_DIR/full_$TIMESTAMP.tar.gz" -C "$BACKUP_DIR" "full_$TIMESTAMP" 2>&1 | tee -a "$LOG_FILE" || error "Failed to create backup archive"
    
    # Cleanup temporary directory
    rm -rf "$BACKUP_PATH"
    
    # Start Prometheus
    log "Starting Prometheus service"
    docker-compose start prometheus 2>&1 | tee -a "$LOG_FILE" || error "Failed to start Prometheus"
    
    # Wait for Prometheus to start
    sleep 10
    
    # Verify Prometheus is running
    if ! curl -s "$PROMETHEUS_URL/-/healthy" | grep -q "Prometheus"; then
        error "Prometheus is not running after restart"
    fi
    
    return "$BACKUP_DIR/full_$TIMESTAMP.tar.gz"
}

# Function to copy a snapshot to the backup directory
copy_snapshot() {
    local SNAPSHOT_NAME="$1"
    
    log "Copying snapshot $SNAPSHOT_NAME to backup directory"
    
    # Create backup directory with timestamp
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="$BACKUP_DIR/snapshot_$TIMESTAMP"
    mkdir -p "$BACKUP_PATH"
    
    # Copy the snapshot
    cp -r "$SNAPSHOT_DIR/$SNAPSHOT_NAME" "$BACKUP_PATH/" || error "Failed to copy snapshot"
    
    # Create a metadata file with backup information
    cat > "$BACKUP_PATH/backup_metadata.json" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "type": "snapshot",
    "prometheus_url": "$PROMETHEUS_URL",
    "snapshot_name": "$SNAPSHOT_NAME",
    "backup_method": "snapshot"
}
EOF
    
    # Create archive
    tar -czf "$BACKUP_DIR/snapshot_$TIMESTAMP.tar.gz" -C "$BACKUP_DIR" "snapshot_$TIMESTAMP" || error "Failed to create backup archive"
    
    # Cleanup temporary directory
    rm -rf "$BACKUP_PATH"
    
    return "$BACKUP_DIR/snapshot_$TIMESTAMP.tar.gz"
}

# Determine if we should do a full backup based on the day of the week
CURRENT_DAY=$(date +%A)
if [ "$CURRENT_DAY" = "$FULL_BACKUP_DAY" ]; then
    log "Today is $FULL_BACKUP_DAY, performing full backup"
    BACKUP_FILE=$(perform_full_backup)
    BACKUP_TYPE="full"
else
    log "Today is not $FULL_BACKUP_DAY, performing snapshot backup"
    SNAPSHOT_NAME=$(create_snapshot)
    BACKUP_FILE=$(copy_snapshot "$SNAPSHOT_NAME")
    BACKUP_TYPE="snapshot"
fi

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

# Export metrics for monitoring (if Prometheus node_exporter textfile collector is enabled)
if [ -d "/var/lib/node_exporter/textfile" ]; then
    METRICS_FILE="/var/lib/node_exporter/textfile/prometheus_backup.prom"
    
    echo "# HELP prometheus_backup_success Whether the last backup succeeded (1) or failed (0)" > "$METRICS_FILE"
    echo "# TYPE prometheus_backup_success gauge" >> "$METRICS_FILE"
    echo "prometheus_backup_success{type=\"$BACKUP_TYPE\"} 1" >> "$METRICS_FILE"
    
    echo "# HELP prometheus_backup_timestamp_seconds Timestamp of the last backup" >> "$METRICS_FILE"
    echo "# TYPE prometheus_backup_timestamp_seconds gauge" >> "$METRICS_FILE"
    echo "prometheus_backup_timestamp_seconds{type=\"$BACKUP_TYPE\"} $(date +%s)" >> "$METRICS_FILE"
    
    echo "# HELP prometheus_backup_size_bytes Size of the last backup in bytes" >> "$METRICS_FILE"
    echo "# TYPE prometheus_backup_size_bytes gauge" >> "$METRICS_FILE"
    echo "prometheus_backup_size_bytes{type=\"$BACKUP_TYPE\"} $(stat -c %s "$BACKUP_FILE")" >> "$METRICS_FILE"
    
    log "Metrics exported to $METRICS_FILE"
fi

log "Backup process completed successfully"

