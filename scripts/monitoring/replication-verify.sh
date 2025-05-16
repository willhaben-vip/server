#!/bin/bash
# Backup Verification Script
# This script verifies the integrity, security, and completeness of backups
# including checksum validation and encryption verification.

set -e

# Configuration
BACKUP_DIR=${BACKUP_DIR:-"/var/backups"}
VERIFICATION_LEVEL=${VERIFICATION_LEVEL:-"full"} # Options: basic, standard, full
CHECKSUM_FILE=${CHECKSUM_FILE:-"/var/backups/checksums.json"}
LOG_FILE="/var/log/monitoring/backup-verify.log"
METRICS_FILE="/var/lib/node_exporter/textfile/backup_verification.prom"

# Create directories if they don't exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$METRICS_FILE")"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $1"
    # Update metrics on error
    echo "backup_verification_error{reason=\"$1\"} 1" >> "$METRICS_FILE"
    return 1
}

# Initialize metrics
initialize_metrics() {
    log "Initializing verification metrics"
    
    cat > "$METRICS_FILE" << EOF
# HELP backup_verification_total Number of backup verifications performed
# TYPE backup_verification_total counter
backup_verification_total{level="$VERIFICATION_LEVEL"} 1

# HELP backup_verification_success Whether the last verification was successful (1) or failed (0)
# TYPE backup_verification_success gauge
backup_verification_success 0

# HELP backup_verification_duration_seconds Duration of the verification process in seconds
# TYPE backup_verification_duration_seconds gauge
backup_verification_duration_seconds 0

# HELP backup_verified_files_total Number of files verified
# TYPE backup_verified_files_total gauge
backup_verified_files_total 0

# HELP backup_verification_error Whether there was an error during verification (1) or not (0)
# TYPE backup_verification_error gauge
backup_verification_error{reason="none"} 0
EOF
}

# Find all backup files to verify
find_backup_files() {
    log "Finding backup files to verify"
    
    # Find all backup archives
    BACKUP_FILES=$(find "$BACKUP_DIR" -name "*.tar.gz" -o -name "*.enc" -type f)
    
    # Count files
    BACKUP_COUNT=$(echo "$BACKUP_FILES" | wc -l)
    
    log "Found $BACKUP_COUNT backup files to verify"
    echo "backup_verified_files_total $BACKUP_COUNT" >> "$METRICS_FILE"
    
    if [ "$BACKUP_COUNT" -eq 0 ]; then
        error "No backup files found for verification"
        return 1
    fi
    
    return 0
}

# Verify file checksums
verify_checksums() {
    log "Verifying file checksums"
    
    # Create checksums file if it doesn't exist
    if [ ! -f "$CHECKSUM_FILE" ]; then
        log "Checksum file doesn't exist, creating new checksums"
        echo "{\"files\": {}}" > "$CHECKSUM_FILE"
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq is required for checksum verification but is not installed"
        return 1
    fi
    
    # Loop through backup files
    ERRORS=0
    VERIFIED=0
    
    for file in $(find "$BACKUP_DIR" -name "*.tar.gz" -o -name "*.enc" -type f); do
        filename=$(basename "$file")
        
        # Calculate current checksum
        current_checksum=$(sha256sum "$file" | awk '{print $1}')
        
        # Check if file is in the checksum database
        if jq -e ".files[\"$filename\"]" "$CHECKSUM_FILE" > /dev/null 2>&1; then
            # Get stored checksum
            stored_checksum=$(jq -r ".files[\"$filename\"].checksum" "$CHECKSUM_FILE")
            
            # Compare checksums
            if [ "$current_checksum" != "$stored_checksum" ]; then
                log "ERROR: Checksum mismatch for $filename. Expected: $stored_checksum, Got: $current_checksum"
                ERRORS=$((ERRORS + 1))
            else
                log "Checksum verified for $filename"
                VERIFIED=$((VERIFIED + 1))
                
                # Update last verified timestamp
                current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                jq --arg file "$filename" --arg time "$current_time" \
                   '.files[$file].last_verified = $time' "$CHECKSUM_FILE" > "$CHECKSUM_FILE.tmp"
                mv "$CHECKSUM_FILE.tmp" "$CHECKSUM_FILE"
            fi
        else
            # File not in database, add it
            log "Adding new file $filename to checksum database"
            current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            file_size=$(stat -c %s "$file")
            
            jq --arg file "$filename" \
               --arg sum "$current_checksum" \
               --arg time "$current_time" \
               --arg size "$file_size" \
               '.files[$file] = {"checksum": $sum, "added": $time, "last_verified": $time, "size": $size}' \
               "$CHECKSUM_FILE" > "$CHECKSUM_FILE.tmp"
            mv "$CHECKSUM_FILE.tmp" "$CHECKSUM_FILE"
            
            VERIFIED=$((VERIFIED + 1))
        fi
    done
    
    # Update metrics
    echo "backup_verified_checksums_total $VERIFIED" >> "$METRICS_FILE"
    echo "backup_checksum_errors_total $ERRORS" >> "$METRICS_FILE"
    
    log "Checksum verification completed: $VERIFIED files verified, $ERRORS errors"
    
    if [ "$ERRORS" -gt 0 ]; then
        error "Checksum verification failed for $ERRORS files"
        return 1
    fi
    
    return 0
}

# Verify archive integrity by testing extraction
verify_archive_integrity() {
    log "Verifying archive integrity"
    
    if [ "$VERIFICATION_LEVEL" = "basic" ]; then
        log "Skipping archive integrity check (verification level: basic)"
        return 0
    fi
    
    # Create temporary directory for testing extraction
    TEMP_DIR=$(mktemp -d)
    
    ERRORS=0
    VERIFIED=0
    
    for file in $(find "$BACKUP_DIR" -name "*.tar.gz" -type f); do
        filename=$(basename "$file")
        log "Testing archive integrity: $filename"
        
        # Test archive without extracting files
        if tar -tzf "$file" > /dev/null 2>&1; then
            log "Archive integrity verified for $filename"
            VERIFIED=$((VERIFIED + 1))
        else
            log "ERROR: Archive integrity check failed for $filename"
            ERRORS=$((ERRORS + 1))
        fi
    done
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    # Update metrics
    echo "backup_verified_archives_total $VERIFIED" >> "$METRICS_FILE"
    echo "backup_archive_errors_total $ERRORS" >> "$METRICS_FILE"
    
    log "Archive verification completed: $VERIFIED archives verified, $ERRORS errors"
    
    if [ "$ERRORS" -gt 0 ]; then
        error "Archive integrity verification failed for $ERRORS files"
        return 1
    fi
    
    return 0
}

# Verify encryption of encrypted files
verify_encryption() {
    log "Verifying encryption of backup files"
    
    # Only verify encryption in full mode
    if [ "$VERIFICATION_LEVEL" != "full" ]; then
        log "Skipping encryption verification (verification level: $VERIFICATION_LEVEL)"
        return 0
    fi
    
    # Check for encryption tool
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required for encryption verification but is not installed"
        return 1
    fi
    
    ERRORS=0
    VERIFIED=0
    
    for file in $(find "$BACKUP_DIR" -name "*.enc" -type f); do
        filename=$(basename "$file")
        log "Verifying encryption for $filename"
        
        # Check file header for encryption signature (openssl adds specific magic bytes)
        if hexdump -n 16 -e '4/1 "%02x"' "$file" | grep -q "Salted__"; then
            log "Encryption verified for $filename"
            VERIFIED=$((VERIFIED + 1))
        else
            log "ERROR: File $filename does not appear to be properly encrypted"
            ERRORS=$((ERRORS + 1))
        fi
    done
    
    # Update metrics
    echo "backup_verified_encrypted_total $VERIFIED" >> "$METRICS_FILE"
    echo "backup_encryption_errors_total $ERRORS" >> "$METRICS_FILE"
    
    log "Encryption verification completed: $VERIFIED files verified, $ERRORS errors"
    
    if [ "$ERRORS" -gt 0 ]; then
        error "Encryption verification failed for $ERRORS files"
        return 1
    fi
    
    return 0
}

# Verify that all required backup types exist
verify_backup_completeness() {
    log "Verifying backup completeness"
    
    # Check for Prometheus backups
    PROMETHEUS_BACKUPS=$(find "$BACKUP_DIR" -name "prometheus*.tar.gz" -type f | wc -l)
    if [ "$PROMETHEUS_BACKUPS" -eq 0 ]; then
        error "No Prometheus backups found"
        echo "backup_completeness{type=\"prometheus\"} 0" >> "$METRICS_FILE"
        return 1
    else
        echo "backup_completeness{type=\"prometheus\"} 1" >> "$METRICS_FILE"
    fi
    
    # Check for Grafana backups
    GRAFANA_BACKUPS=$(find "$BACKUP_DIR" -name "grafana*.tar.gz" -type f | wc -l)
    if [ "$GRAFANA_BACKUPS" -eq 0 ]; then
        error "No Grafana backups found"
        echo "backup_completeness{type=\"grafana\"} 0" >> "$METRICS_FILE"
        return 1
    else
        echo "backup_completeness{type=\"grafana\"} 1" >> "$METRICS_FILE"
    fi
    
    # Check for encrypted backups
    ENCRYPTED_BACKUPS=$(find "$BACKUP_DIR" -name "*.enc" -type f | wc -l)
    if [ "$ENCRYPTED_BACKUPS" -eq 0 ]; then
        error "No encrypted backups found"
        echo "backup_completeness{type=\"encrypted\"} 0" >> "$METRICS_FILE"
        return 1
    else
        echo "backup_completeness{type=\"encrypted\"} 1" >> "$METRICS_FILE"
    fi
    
    log "Backup completeness verified: All required backup types found"
    return 0
}

# Main verification function
main() {
    log "Starting backup verification process (level: $VERIFICATION_LEVEL)"
    
    # Record start time for duration calculation
    START_TIME=$(date +%s)
    
    # Initialize metrics
    initialize_metrics
    
    # Find backup files
    if ! find_backup_files; then
        error "Verification failed: Could not find backup files"
        echo "backup_verification_success 0" >> "$METRICS_FILE"
        exit 1
    fi
    
    # Verify backup completeness
    if ! verify_backup_completeness; then
        error "Verification failed: Backup set is incomplete"
        echo "backup_verification_success 0" >> "$METRICS_FILE"
        exit 1
    fi
    
    # Verify file checksums
    if ! verify_checksums; then
        error "Verification failed: Checksum verification errors"
        echo "backup_verification_success 0" >> "$METRICS_FILE"
        exit 1
    fi
    
    # Verify archive integrity
    if ! verify_archive_integrity; then
        error "Verification failed: Archive integrity errors"
        echo "backup_verification_success 0" >> "$METRICS_FILE"
        exit 1
    fi
    
    # Verify encryption
    if ! verify_encryption; then
        error "Verification failed: Encryption verification errors"
        echo "backup_verification_success 0" >> "$METRICS_FILE"
        exit 1
    fi
    
    # Calculate verification duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Update final metrics
    echo "backup_verification_success 1" >> "$METRICS_FILE"
    echo "backup_verification_duration_seconds $DURATION" >> "$METRICS_FILE"
    
    log "Backup verification completed successfully in $DURATION seconds"
    exit 0
}

# Handle script termination
cleanup() {
    log "Backup verification interrupted"
    echo "backup_verification_success 0" >> "$METRICS_FILE"
    echo "backup_verification_error{reason=\"interrupted\"} 1" >> "$METRICS_FILE"
    exit 1
}

# Set up trap for proper shutdown
trap cleanup SIGTERM SIGINT

# Start verification process
main

