#!/usr/bin/env bash
#
# Willhaben.vip Deployment Script
# ------------------------------
#
# This script deploys the Willhaben.vip application to production.
# It manages the RoadRunner service, handles backups, and monitors status.
#
# Usage: ./deploy-docker.sh [option]
#
# Options:
#   deploy   - Deploy/update the application (default)
#   backup   - Create a backup only
#   restore  - Restore from the most recent backup
#   status   - Check service status
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Configuration
REMOTE_USER="nikolaos"
REMOTE_HOST="alonnisos.willhaben.vip"
REMOTE_DIR="/var/www/willhaben.vip"
SERVICE_NAME="roadrunner"
RR_BINARY="${REMOTE_DIR}/rr"
LOG_FILE="deploy-$(date +%Y%m%d-%H%M%S).log"

# Git repository info
GIT_REPO="git@github.com:willhaben-vip/server.git"
GIT_BRANCH="main"

# Create local logs directory
mkdir -p logs
LOG_FILE="logs/${LOG_FILE}"

# Logging functions
log() {
  local level="$1"
  local message="$2"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "$1"; }
warn() { log "WARNING" "$1"; }
error() { log "ERROR" "$1"; echo "ERROR: $1" >&2; }
success() { log "SUCCESS" "$1"; echo "✓ $1"; }

# Remote command execution via SSH
ssh_exec() {
  local command="$1"
  local silent="${2:-false}"
  
  if [[ "${silent}" == "true" ]]; then
    ssh -T "${REMOTE_USER}@${REMOTE_HOST}" "${command}" >> "${LOG_FILE}" 2>&1
    return $?
  else
    info "Executing: ${command}"
    ssh -tt "${REMOTE_USER}@${REMOTE_HOST}" "${command}" 2>&1 | tee -a "${LOG_FILE}"
    return ${PIPESTATUS[0]}
  fi
}

# Upload a file to the remote server
upload_file() {
  local local_file="$1"
  local remote_path="$2"
  
  info "Uploading ${local_file} to ${REMOTE_HOST}:${remote_path}"
  scp "${local_file}" "${REMOTE_USER}@${REMOTE_HOST}:${remote_path}" >> "${LOG_FILE}" 2>&1
  if [[ $? -ne 0 ]]; then
    error "Failed to upload ${local_file}"
    return 1
  fi
  success "Upload successful"
}

# Check service status
check_service_status() {
  local service="$1"
  local max_attempts="${2:-10}"
  local delay="${3:-2}"
  local attempt=1
  
  info "Checking status of ${service} service..."
  
  while [[ $attempt -le $max_attempts ]]; do
    local status=$(ssh_exec "sudo systemctl is-active ${service} 2>/dev/null || echo 'unknown'" true)
    
    if [[ "${status}" == "active" ]]; then
      success "Service ${service} is active and running"
      return 0
    elif [[ "${status}" == "unknown" ]]; then
      error "Service ${service} not found"
      return 1
    else
      info "Service ${service} status: ${status} (attempt ${attempt}/${max_attempts})"
      ((attempt++))
      sleep "${delay}"
    fi
  done
  
  error "Service ${service} did not become active after ${max_attempts} attempts"
  return 1
}

# Prepare the remote server (directories, etc.)
prepare_server() {
  info "Preparing remote server..."
  
  # Ensure the service exists
  if ! ssh_exec "systemctl list-unit-files | grep -q ${SERVICE_NAME}.service"; then
    error "RoadRunner service (${SERVICE_NAME}) is not installed on the remote server"
    return 1
  fi
  
  # Verify RoadRunner binary exists
  if ! ssh_exec "test -f ${RR_BINARY}"; then
    error "RoadRunner binary not found at ${RR_BINARY}"
    return 1
  fi
  
  # Check RoadRunner service configuration
  local service_config=$(ssh_exec "sudo systemctl cat ${SERVICE_NAME}" true)
  if ! echo "${service_config}" | grep -q "ExecStart=${RR_BINARY}"; then
    warn "RoadRunner service may be using a different binary path than expected"
    warn "Service uses: $(echo "${service_config}" | grep 'ExecStart=' | sed 's/ExecStart=//')"
    warn "Expected: ${RR_BINARY}"
    
    # Update RR_BINARY to match service configuration
    RR_BINARY=$(echo "${service_config}" | grep 'ExecStart=' | sed 's/ExecStart=//' | awk '{print $1}')
    info "Updated RoadRunner binary path to: ${RR_BINARY}"
  fi
  
  # Create required directories
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/member"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/logs"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/config"
  ssh_exec "mkdir -p ${REMOTE_DIR}/backups"
  
  # Set proper permissions
  ssh_exec "chmod -R 755 ${REMOTE_DIR}/data"
  
  # Verify directory structure exists and is writable
  ssh_exec "mkdir -p ${REMOTE_DIR}/server"
  ssh_exec "mkdir -p ${REMOTE_DIR}/logs"
  
  # Check permissions on main directories
  local dir_perm=$(ssh_exec "ls -ld ${REMOTE_DIR}" true)
  if ! echo "${dir_perm}" | grep -q "${REMOTE_USER}"; then
    warn "Main directory not owned by ${REMOTE_USER}: ${dir_perm}"
    warn "This may cause permission issues during deployment"
  fi
  
  # Ensure we have permission to restart the service
  if ! ssh_exec "sudo -l | grep -q 'systemctl restart ${SERVICE_NAME}'"; then
    warn "You may not have permission to restart the ${SERVICE_NAME} service"
    warn "Please ensure your sudo permissions are correctly configured"
  else
    info "Verified service restart permissions"
  fi
  
  success "Server preparation complete"
}

# Create a backup of the current deployment
create_backup() {
  local backup_dir="${REMOTE_DIR}/backups/backup-$(date +%Y%m%d-%H%M%S)"
  info "Creating backup in ${backup_dir}..."
  
  # Create backup directory
  ssh_exec "mkdir -p ${backup_dir}"
  
  # Backup service configuration
  ssh_exec "sudo systemctl cat ${SERVICE_NAME} > ${backup_dir}/${SERVICE_NAME}.service" || true
  
  # Backup RoadRunner binary
  ssh_exec "test -f ${RR_BINARY} && cp ${RR_BINARY} ${backup_dir}/rr" || true
  
  # Backup application code
  ssh_exec "test -d ${REMOTE_DIR}/server && tar -czf ${backup_dir}/server-data.tar.gz -C ${REMOTE_DIR} server" || true
  
  # Backup data files
  ssh_exec "test -d ${REMOTE_DIR}/data/member && tar -czf ${backup_dir}/member-data.tar.gz -C ${REMOTE_DIR}/data member" || true
  ssh_exec "test -d ${REMOTE_DIR}/data/config && tar -czf ${backup_dir}/config-data.tar.gz -C ${REMOTE_DIR}/data config" || true
  
  # Backup logs
  ssh_exec "test -d ${REMOTE_DIR}/data/logs && tar -czf ${backup_dir}/logs.tar.gz -C ${REMOTE_DIR}/data logs" || true
  
  # Create backup info file
  ssh_exec "echo 'Backup created on $(date)' > ${backup_dir}/backup-info.txt"
  ssh_exec "sudo systemctl status ${SERVICE_NAME} > ${backup_dir}/service-status.txt" || true
  
  # Get git commit hash if available
  ssh_exec "test -d ${REMOTE_DIR}/app && cd ${REMOTE_DIR}/app && git rev-parse HEAD > ${backup_dir}/git-commit.txt" || true
  
  success "Backup created at ${backup_dir}"
}

# Restore from the most recent backup
restore_backup() {
  info "Finding the most recent backup..."
  
  # Get the most recent backup directory
  local backup_dir=$(ssh_exec "ls -td ${REMOTE_DIR}/backups/backup-* | head -1" true)
  
  if [[ -z "${backup_dir}" ]]; then
    error "No backup found"
    return 1
  fi
  
  info "Restoring from backup: ${backup_dir}"
  
  # Stop the service first
  ssh_exec "sudo systemctl stop ${SERVICE_NAME}" || true
  
  # Restore application code if backed up
  if ssh_exec "test -f ${backup_dir}/server-data.tar.gz" true; then
    info "Restoring server code..."
    ssh_exec "tar -xzf ${backup_dir}/server-data.tar.gz -C ${REMOTE_DIR}"
  fi
  
  # Restore RoadRunner binary if backed up
  if ssh_exec "test -f ${backup_dir}/rr" true; then
    info "Restoring RoadRunner binary..."
    ssh_exec "cp ${backup_dir}/rr ${RR_BINARY}"
    ssh_exec "chmod +x ${RR_BINARY}"
  fi
  
  # Restore data files
  if ssh_exec "test -f ${backup_dir}/member-data.tar.gz" true; then
    info "Restoring member data..."
    ssh_exec "tar -xzf ${backup_dir}/member-data.tar.gz -C ${REMOTE_DIR}/data"
  fi
  
  if ssh_exec "test -f ${backup_dir}/config-data.tar.gz" true; then
    info "Restoring config data..."
    ssh_exec "tar -xzf ${backup_dir}/config-data.tar.gz -C ${REMOTE_DIR}/data"
  fi
  
  # Start the service
  ssh_exec "sudo systemctl start ${SERVICE_NAME}"
  
  # Check if service started successfully
  if ! check_service_status "${SERVICE_NAME}"; then
    error "Failed to start service after restore"
    return 1
  fi
  
  success "Restore completed from ${backup_dir}"
}

# Deploy the application
deploy() {
  info "Starting deployment..."
  
  # Prepare server
  prepare_server
  
  # Create backup before changes
  create_backup
  
  # Clone or update the repository to a temporary location first
  local temp_dir="${REMOTE_DIR}/tmp_deploy"
  ssh_exec "mkdir -p ${temp_dir}"
  
  info "Fetching latest code..."
  if ssh_exec "git clone --branch ${GIT_BRANCH} --depth 1 ${GIT_REPO} ${temp_dir}" true; then
    info "Repository cloned successfully to temporary directory"
  else
    error "Failed to clone repository"
    return 1
  fi
  
  # Sync the changes to the server directory
  info "Syncing code to server directory..."
  ssh_exec "rsync -av --delete ${temp_dir}/server/ ${REMOTE_DIR}/server/"
  
  # Clean up temporary directory
  ssh_exec "rm -rf ${temp_dir}"
  
  info "Code update completed"
  
  # Copy any local configuration files if needed
  if [ -f "config.prod.json" ]; then
    info "Uploading production configuration..."
    upload_file "config.prod.json" "${REMOTE_DIR}/server/config.json"
  fi
  
  # Set proper permissions
  ssh_exec "chmod -R 755 ${REMOTE_DIR}/server"
  
  # Restart the service
  info "Restarting RoadRunner service..."
  ssh_exec "sudo systemctl restart ${SERVICE_NAME}"
  
  # Check service logs for errors immediately after restart
  info "Checking service startup logs..."
  local startup_log=$(ssh_exec "sudo journalctl -u ${SERVICE_NAME} -n 20 --no-pager" true)
  echo "${startup_log}" >> "${LOG_FILE}"
  
  if echo "${startup_log}" | grep -i "error\|failed\|fatal"; then
    warn "Potential errors found in service logs:"
    echo "${startup_log}" | grep -i "error\|failed\|fatal"
  fi
  
  # Check if service restarted successfully
  if ! check_service_status "${SERVICE_NAME}"; then
    error "Failed to restart service"
    # Try to get more detailed error information
    warn "Latest service logs:"
    ssh_exec "sudo journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
    return 1
  fi
  
  success "Deployment completed successfully"
}

# Check status of the service
check_status() {
  info "Checking service status..."
  
  # Get systemd service status
  ssh_exec "sudo systemctl status ${SERVICE_NAME}"
  
  # Check service logs
  info "Recent service logs:"
  ssh_exec "sudo journalctl -u ${SERVICE_NAME} --no-pager -n 20"
  
  # Check for any error patterns in the logs
  local error_patterns="panic:|fatal:|error:|failed:|exception"
  local error_count=$(ssh_exec "sudo journalctl -u ${SERVICE_NAME} --no-pager -n 100 | grep -iE '${error_patterns}' | wc -l" true)
  
  if [[ "${error_count}" -gt 0 ]]; then
    warn "Found ${error_count} potential error messages in recent logs:"
    ssh_exec "sudo journalctl -u ${SERVICE_NAME} --no-pager -n 100 | grep -iE '${error_patterns}'"
  fi
  
  # Check if service is running
  if check_service_status "${SERVICE_NAME}" 1 0; then
    success "Service is running correctly"
  else
    error "Service is not running properly"
    return 1
  fi
  
  success "Status check completed"
}

# Main function
main() {
  local command="${1:-deploy}"
  
  case "${command}" in
    deploy)
      deploy
      ;;
    backup)
      create_backup
      ;;
    restore)
      restore_backup
      ;;
    status)
      check_status
      ;;
    *)
      error "Unknown command: ${command}"
      echo "Usage: $0 [deploy|backup|restore|status]"
      exit 1
      ;;
  esac
}

# Execute main function
main "$@"
