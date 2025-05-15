#!/usr/bin/env bash
#
# Willhaben.vip Docker Deployment Script
# --------------------------------------
#
# This script deploys the Willhaben.vip application to production using Docker.
# It handles container management, volume setup, and health monitoring.
#
# Usage: ./deploy-docker.sh [option]
#
# Options:
#   deploy   - Deploy/update the application (default)
#   backup   - Create a backup only
#   restore  - Restore from the most recent backup
#   status   - Check the status of running containers
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Configuration
REMOTE_USER="nikolaos"
REMOTE_HOST="alonissos.willhaben.vip"
REMOTE_DIR="/opt/willhaben.vip"
COMPOSE_FILE="docker-compose.prod.yml"
LOG_FILE="deploy-$(date +%Y%m%d-%H%M%S).log"

# Docker container names from docker-compose.prod.yml
APP_CONTAINER="willhaben_app"
NGINX_CONTAINER="willhaben_nginx"
REDIS_CONTAINER="willhaben_storage"

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

# Check if a container is healthy
check_container_health() {
  local container="$1"
  local max_attempts="${2:-30}"
  local delay="${3:-2}"
  local attempt=1
  
  info "Checking health of ${container}..."
  
  while [[ $attempt -le $max_attempts ]]; do
    local status=$(ssh_exec "docker inspect --format='{{.State.Health.Status}}' ${container} 2>/dev/null || echo 'not_found'" true)
    
    if [[ "${status}" == "healthy" ]]; then
      success "Container ${container} is healthy"
      return 0
    elif [[ "${status}" == "not_found" ]]; then
      error "Container ${container} not found"
      return 1
    else
      info "Container ${container} status: ${status} (attempt ${attempt}/${max_attempts})"
      ((attempt++))
      sleep "${delay}"
    fi
  done
  
  error "Container ${container} did not become healthy after ${max_attempts} attempts"
  return 1
}

# Prepare the remote server (directories, etc.)
prepare_server() {
  info "Preparing remote server..."
  
  # Ensure Docker is running
  if ! ssh_exec "docker ps > /dev/null 2>&1"; then
    error "Docker is not running on the remote server"
    return 1
  fi
  
  # Create required directories
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/member"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/logs"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/config"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/redis"
  ssh_exec "mkdir -p ${REMOTE_DIR}/nginx/conf.d"
  ssh_exec "mkdir -p ${REMOTE_DIR}/nginx/ssl"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/logs/nginx"
  ssh_exec "mkdir -p ${REMOTE_DIR}/backups"
  
  # Set proper permissions
  ssh_exec "chmod -R 755 ${REMOTE_DIR}/data"
  ssh_exec "chmod -R 755 ${REMOTE_DIR}/nginx"
  
  # Setup Docker networks if they don't exist
  if ! ssh_exec "docker network ls | grep -q 'app_network'"; then
    ssh_exec "docker network create app_network --internal"
  fi
  
  if ! ssh_exec "docker network ls | grep -q 'web_network'"; then
    ssh_exec "docker network create web_network"
  fi
  
  success "Server preparation complete"
}

# Create a backup of the current deployment
create_backup() {
  local backup_dir="${REMOTE_DIR}/backups/backup-$(date +%Y%m%d-%H%M%S)"
  info "Creating backup in ${backup_dir}..."
  
  # Create backup directory
  ssh_exec "mkdir -p ${backup_dir}"
  
  # Backup docker-compose file
  ssh_exec "test -f ${REMOTE_DIR}/${COMPOSE_FILE} && cp ${REMOTE_DIR}/${COMPOSE_FILE} ${backup_dir}/" || true
  
  # Backup volume data
  ssh_exec "test -d ${REMOTE_DIR}/data/member && tar -czf ${backup_dir}/member-data.tar.gz -C ${REMOTE_DIR}/data member" || true
  ssh_exec "test -d ${REMOTE_DIR}/data/config && tar -czf ${backup_dir}/config-data.tar.gz -C ${REMOTE_DIR}/data config" || true
  ssh_exec "test -d ${REMOTE_DIR}/nginx && tar -czf ${backup_dir}/nginx-data.tar.gz -C ${REMOTE_DIR} nginx" || true
  
  # Backup Redis data if Redis container is running
  if ssh_exec "docker ps | grep -q ${REDIS_CONTAINER}" true; then
    info "Backing up Redis data..."
    ssh_exec "docker exec ${REDIS_CONTAINER} redis-cli SAVE" || true
    ssh_exec "test -d ${REMOTE_DIR}/data/redis && tar -czf ${backup_dir}/redis-data.tar.gz -C ${REMOTE_DIR}/data redis" || true
  fi
  
  # Create backup info file
  ssh_exec "echo 'Backup created on $(date)' > ${backup_dir}/backup-info.txt"
  ssh_exec "docker ps > ${backup_dir}/containers.txt" || true
  
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
  
  # Stop running containers
  ssh_exec "cd ${REMOTE_DIR} && docker-compose -f ${COMPOSE_FILE} down || docker compose -f ${COMPOSE_FILE} down" || true
  
  # Restore docker-compose file
  ssh_exec "test -f ${backup_dir}/${COMPOSE_FILE} && cp ${backup_dir}/${COMPOSE_FILE} ${REMOTE_DIR}/" || true
  
  # Restore data
  if ssh_exec "test -f ${backup_dir}/member-data.tar.gz" true; then
    info "Restoring member data..."
    ssh_exec "tar -xzf ${backup_dir}/member-data.tar.gz -C ${REMOTE_DIR}/data"
  fi
  
  if ssh_exec "test -f ${backup_dir}/config-data.tar.gz" true; then
    info "Restoring config data..."
    ssh_exec "tar -xzf ${backup_dir}/config-data.tar.gz -C ${REMOTE_DIR}/data"
  fi
  
  if ssh_exec "test -f ${backup_dir}/nginx-data.tar.gz" true; then
    info "Restoring Nginx configuration..."
    ssh_exec "tar -xzf ${backup_dir}/nginx-data.tar.gz -C ${REMOTE_DIR}"
  fi
  
  if ssh_exec "test -f ${backup_dir}/redis-data.tar.gz" true; then
    info "Restoring Redis data..."
    ssh_exec "tar -xzf ${backup_dir}/redis-data.tar.gz -C ${REMOTE_DIR}/data"
  fi
  
  # Start containers
  ssh_exec "cd ${REMOTE_DIR} && docker-compose -f ${COMPOSE_FILE} up -d || docker compose -f ${COMPOSE_FILE} up -d"
  
  success "Restore completed from ${backup_dir}"
}

# Deploy the application
deploy() {
  info "Starting deployment..."
  
  # Prepare server
  prepare_server
  
  # Create backup before changes
  create_backup
  
  # Upload docker-compose file
  if ! upload_file "${COMPOSE_FILE}" "${REMOTE_DIR}/${COMPOSE_FILE}"; then
    error "Failed to upload docker-compose.yml"
    return 1
  fi
  
  # Pull latest images
  info "Pulling latest Docker images..."
  ssh_exec "cd ${REMOTE_DIR} && docker-compose -f ${COMPOSE_FILE} pull || docker compose -f ${COMPOSE_FILE} pull"
  
  # Stop and remove existing containers
  info "Stopping existing containers..."
  ssh_exec "cd ${REMOTE_DIR} && docker-compose -f ${COMPOSE_FILE} down || docker compose -f ${COMPOSE_FILE} down" || true
  
  # Start containers
  info "Starting containers..."
  ssh_exec "cd ${REMOTE_DIR} && docker-compose -f ${COMPOSE_FILE} up -d || docker compose -f ${COMPOSE_FILE} up -d"
  
  # Wait for containers to be healthy
  sleep 5
  if ! check_container_health "${APP_CONTAINER}" 30 2; then
    warn "Application container not healthy, but continuing..."
  fi
  
  if ! check_container_health "${NGINX_CONTAINER}" 30 2; then
    warn "Nginx container not healthy, but continuing..."
  fi
  
  # Check deployment status
  info "Checking deployment status..."
  ssh_exec "cd ${REMOTE_DIR} && docker-compose -f ${COMPOSE_FILE} ps || docker compose -f ${COMPOSE_FILE} ps"
  
  success "Deployment completed successfully"
}

# Check status of running containers
check_status() {
  info "Checking status of containers..."
  
  ssh_exec "docker ps --filter 'name=willhaben_'"
  ssh_exec "docker stats --no-stream --filter 'name=willhaben_'"
  
  # Check health status
  local app_health=$(ssh_exec "docker inspect --format='{{.State.Health.Status}}' ${APP_CONTAINER} 2>/dev/null || echo 'not_found'" true)
  local nginx_health=$(ssh_exec "docker inspect --format='{{.State.Health.Status}}' ${NGINX_CONTAINER} 2>/dev/null || echo 'not_found'" true)
  local redis_health=$(ssh_exec "docker inspect --format='{{.State.Health.Status}}' ${REDIS_CONTAINER} 2>/dev/null || echo 'not_found'" true)
  
  info "Health status:"
  info "- Application: ${app_health}"
  info "- Nginx: ${nginx_health}"
  info "- Redis: ${redis_health}"
  
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
