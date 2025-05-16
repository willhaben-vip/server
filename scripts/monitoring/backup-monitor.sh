#!/bin/bash
# Backup Monitoring Script
# This script provides continuous monitoring of the backup system,
# checking for successful completion, integrity, and security of backups.

set -e

# Configuration
PROMETHEUS_URL=${PROMETHEUS_URL:-"http://localhost:9090"}
METRICS_PATH=${METRICS_PATH:-"/var/lib/node_exporter/textfile/backup_monitoring.prom"}
CHECK_INTERVAL=${CHECK_INTERVAL:-"5m"}
ALERT_THRESHOLD=${ALERT_THRESHOLD:-"24h"}
BACKUP_DIR=${BACKUP_DIR:-"/var/backups"}
LOG_FILE="/var/log/monitoring/backup-monitor.log"

# Create directories if they don't exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$METRICS_PATH")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    # Export error metric
    update_metric "backup_monitor_error" "1" "reason=\"$1\""
    return 1
}

# Function to update a Prometheus metric
update_metric() {
    local name="$1"
    local value="$2"
    local labels="${3:-}"
    
    # Create metrics file if it doesn't exist
    if [ ! -f "$METRICS_PATH" ]; then
        touch "$METRICS_PATH"
    fi
    
    # Remove existing metric if it exists
    if grep -q "^$name{$labels}" "$METRICS_PATH" 2>/dev/null; then
        sed -i "/^$name{$labels}/d" "$METRICS_PATH"
    elif grep -q "^$name " "$METRICS_PATH" 2>/dev/null && [ -z "$labels" ]; then
        sed -i "/^$name /d" "$METRICS_PATH"
    fi
    
    # Add the new metric
    if [ -z "$labels" ]; then
        echo "$name $value" >> "$METRICS_PATH"
    else
        echo "$name{$labels} $value" >> "$METRICS_PATH"
    fi
}

# Initialize metrics
initialize_metrics() {
    log "Initializing metrics"
    
    # Create metrics file with headers
    cat > "$METRICS_PATH" << EOF
# HELP backup_last_success_timestamp_seconds Timestamp of the last successful backup
# TYPE backup_last_success_timestamp_seconds gauge
# HELP backup_last_verification_timestamp_seconds Timestamp of the last successful verification
# TYPE backup_last_verification_timestamp_seconds gauge
# HELP backup_last_encryption_timestamp_seconds Timestamp of the last successful encryption
# TYPE backup_last_encryption_timestamp_seconds gauge
# HELP backup_age_seconds Age of the most recent backup in seconds
# TYPE backup_age_seconds gauge
# HELP backup_size_bytes Size of the most recent backup in bytes
# TYPE backup_size_bytes gauge
# HELP backup_count Total number of backups available
# TYPE backup_count gauge
# HELP backup_success Whether the last backup was successful (1) or failed (0)
# TYPE backup_success gauge
# HELP backup_verification_success Whether the last verification was successful (1) or failed (0)
# TYPE backup_verification_success gauge
# HELP backup_encryption_success Whether the last encryption was successful (1) or failed (0)
# TYPE backup_encryption_success gauge
# HELP backup_monitor_error Whether there is a monitoring error (1) or not (0)
# TYPE backup_monitor_error gauge
# HELP backup_monitor_up Whether the backup monitor is running (1) or not (0)
# TYPE backup_monitor_up gauge
EOF
    
    # Set monitor up metric
    update_metric "backup_monitor_up" "1"
    update_metric "backup_monitor_error" "0"
}

# Check if backups exist
check_backup_existence() {
    log "Checking for existing backups"
    
    # Count prometheus backups
    PROMETHEUS_BACKUPS=$(find "$BACKUP_DIR" -name "prometheus*.tar.gz" -type f | wc -l)
    
    # Count grafana backups
    GRAFANA_BACKUPS=$(find "$BACKUP_DIR" -name "grafana*.tar.gz" -type f | wc -l)
    
    # Total backups
    TOTAL_BACKUPS=$((PROMETHEUS_BACKUPS + GRAFANA_BACKUPS))
    
    update_metric "backup_count" "$TOTAL_BACKUPS" "type=\"total\""
    update_metric "backup_count" "$PROMETHEUS_BACKUPS" "type=\"prometheus\""
    update_metric "backup_count" "$GRAFANA_BACKUPS" "type=\"grafana\""
    
    if [ "$TOTAL_BACKUPS" -eq 0 ]; then
        error "No backups found"
        return 1
    fi
    
    return 0
}

# Check backup recency
check_backup_recency() {
    log "Checking backup recency"
    
    # Find the most recent backup
    NEWEST_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -exec ls -t {} \; | head -n1)
    
    if [ -z "$NEWEST_BACKUP" ]; then
        error "No backups found when checking recency"
        return 1
    fi
    
    # Get the backup creation time
    BACKUP_TIME=$(stat -c %Y "$NEWEST_BACKUP")
    CURRENT_TIME=$(date +%s)
    BACKUP_AGE=$((CURRENT_TIME - BACKUP_TIME))
    
    # Update metrics
    update_metric "backup_age_seconds" "$BACKUP_AGE"
    update_metric "backup_last_success_timestamp_seconds" "$BACKUP_TIME"
    
    # Get backup size
    BACKUP_SIZE=$(stat -c %s "$NEWEST_BACKUP")
    update_metric "backup_size_bytes" "$BACKUP_SIZE"
    
    # Check if backup is too old (alert threshold exceeded)
    ALERT_SECONDS=$(echo "$ALERT_THRESHOLD" | sed 's/h/*3600/g' | bc)
    if [ "$BACKUP_AGE" -gt "$ALERT_SECONDS" ]; then
        error "Most recent backup is too old: $BACKUP_AGE seconds (threshold: $ALERT_SECONDS seconds)"
        return 1
    fi
    
    log "Most recent backup is $BACKUP_AGE seconds old"
    return 0
}

# Check verification status
check_verification_status() {
    log "Checking verification status"
    
    # Check if verification log exists
    VERIFICATION_LOG="/var/log/monitoring/backup-verify.log"
    if [ ! -f "$VERIFICATION_LOG" ]; then
        error "Verification log not found"
        update_metric "backup_verification_success" "0"
        return 1
    fi
    
    # Check if last verification was successful
    if grep -q "verification completed successfully" "$VERIFICATION_LOG" | tail -n 10; then
        LAST_SUCCESS=$(grep "verification completed successfully" "$VERIFICATION_LOG" | tail -n 1)
        TIMESTAMP=$(echo "$LAST_SUCCESS" | awk '{print $1 " " $2}' | xargs -I{} date -d "{}" +%s)
        
        update_metric "backup_verification_success" "1"
        update_metric "backup_last_verification_timestamp_seconds" "$TIMESTAMP"
        
        log "Last verification was successful at $(date -d @$TIMESTAMP)"
        return 0
    else
        error "Last verification was not successful"
        update_metric "backup_verification_success" "0"
        return 1
    fi
}

# Check encryption status
check_encryption_status() {
    log "Checking encryption status"
    
    # Check if encrypted backups exist
    ENCRYPTED_BACKUPS=$(find "$BACKUP_DIR" -name "*.enc" -type f | wc -l)
    
    update_metric "backup_count" "$ENCRYPTED_BACKUPS" "type=\"encrypted\""
    
    if [ "$ENCRYPTED_BACKUPS" -eq 0 ]; then
        error "No encrypted backups found"
        update_metric "backup_encryption_success" "0"
        return 1
    fi
    
    # Find most recent encrypted backup
    NEWEST_ENCRYPTED=$(find "$BACKUP_DIR" -name "*.enc" -type f -exec ls -t {} \; | head -n1)
    
    # Get the encryption time
    ENCRYPTION_TIME=$(stat -c %Y "$NEWEST_ENCRYPTED")
    
    update_metric "backup_encryption_success" "1"
    update_metric "backup_last_encryption_timestamp_seconds" "$ENCRYPTION_TIME"
    
    log "Encryption status is good, last encrypted backup at $(date -d @$ENCRYPTION_TIME)"
    return 0
}

# Health check function
check_backup_health() {
    log "Running backup health check"
    
    HEALTH_SCORE=100
    
    # Check backup existence
    if ! check_backup_existence; then
        HEALTH_SCORE=$((HEALTH_SCORE - 50))
    fi
    
    # Check backup recency
    if ! check_backup_recency; then
        HEALTH_SCORE=$((HEALTH_SCORE - 20))
    fi
    
    # Check verification status
    if ! check_verification_status; then
        HEALTH_SCORE=$((HEALTH_SCORE - 15))
    fi
    
    # Check encryption status
    if ! check_encryption_status; then
        HEALTH_SCORE=$((HEALTH_SCORE - 15))
    fi
    
    # Update health score metric
    update_metric "backup_health_score" "$HEALTH_SCORE"
    
    if [ "$HEALTH_SCORE" -lt 50 ]; then
        error "Backup system is unhealthy. Score: $HEALTH_SCORE/100"
        return 1
    elif [ "$HEALTH_SCORE" -lt 80 ]; then
        log "WARNING: Backup system health is degraded. Score: $HEALTH_SCORE/100"
        return 0
    else
        log "Backup system is healthy. Score: $HEALTH_SCORE/100"
        return 0
    fi
}

# Main monitoring loop
main() {
    log "Starting backup monitoring service"
    
    # Initialize metrics
    initialize_metrics
    
    # Initial health check
    check_backup_health
    
    # Continuous monitoring loop
    while true; do
        # Run health check
        check_backup_health
        
        # Wait for next check interval
        SLEEP_SECONDS=$(echo "$CHECK_INTERVAL" | sed 's/m/*60/g' | bc)
        log "Sleeping for $SLEEP_SECONDS seconds until next check"
        sleep "$SLEEP_SECONDS"
    done
}

# Handle script termination
cleanup() {
    log "Backup monitoring service shutting down"
    update_metric "backup_monitor_up" "0"
    exit 0
}

# Set up trap for proper shutdown
trap cleanup SIGTERM SIGINT

# Start monitoring
main

