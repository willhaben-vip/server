#!/usr/bin/env bash
#
# Willhaben.VIP Production Deployment Script
# -----------------------------------------
# This script deploys the Willhaben.VIP application to the production server
# at alonissos.willhaben.vip. It handles Docker container deployment, volume
# management, networking, and health checks.
#
# Usage:
#   ./deploy-docker.sh [options]
#
# Options:
#   -e, --environment     Target environment (default: production)
#   -v, --version         Version tag to deploy (default: latest)
#   -f, --force           Force deployment even if validation fails
#   -b, --backup          Create backup before deployment (default: true)
#   --no-backup           Skip backup creation
#   -h, --help            Show this help message
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Script constants
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
readonly LOG_FILE="${SCRIPT_DIR}/logs/deploy-${TIMESTAMP}.log"

# Server configuration
readonly REMOTE_USER="nikolaos"
readonly REMOTE_HOST="alonissos.willhaben.vip"
readonly REMOTE_DIR="/opt/willhaben.vip"
readonly COMPOSE_FILE_LOCAL="docker-compose.prod.yml"
readonly COMPOSE_FILE_REMOTE="${REMOTE_DIR}/docker-compose.yml"

# Docker configuration
readonly DOCKER_REGISTRY="ghcr.io"
readonly DOCKER_ORG="willhaben-vip"
readonly APP_IMAGE="${DOCKER_REGISTRY}/${DOCKER_ORG}/roadrunner"
readonly NGINX_IMAGE="nginx:stable-alpine"
readonly REDIS_IMAGE="redis:alpine"

# Container names
readonly APP_CONTAINER="willhaben_app"
readonly NGINX_CONTAINER="willhaben_nginx"
readonly REDIS_CONTAINER="willhaben_storage"

# Default values
ENVIRONMENT="production"
VERSION="latest"
FORCE_DEPLOY=false
CREATE_BACKUP=true

# Create logs directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/logs"

# Set up logging
log() {
  local level=$1
  local message=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
  log "INFO" "$1"
}

warn() {
  log "WARNING" "$1"
}

error() {
  log "ERROR" "$1"
  echo "ERROR: $1" >&2
}

success() {
  log "SUCCESS" "$1"
  echo "✓ $1"
}

# Function to display usage information
show_usage() {
  cat << EOF
Usage: ${SCRIPT_NAME} [options]

Deploy the Willhaben.VIP application to the production server.

Options:
  -e, --environment     Target environment (default: production)
  -v, --version         Version tag to deploy (default: latest)
  -f, --force           Force deployment even if validation fails
  -b, --backup          Create backup before deployment (default: true)
  --no-backup           Skip backup creation
  -h, --help            Show this help message
EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--environment)
        ENVIRONMENT="$2"
        shift 2
        ;;
      -v|--version)
        VERSION="$2"
        shift 2
        ;;
      -f|--force)
        FORCE_DEPLOY=true
        shift
        ;;
      -b|--backup)
        CREATE_BACKUP=true
        shift
        ;;
      --no-backup)
        CREATE_BACKUP=false
        shift
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done

  # Validate environment
  if [[ "${ENVIRONMENT}" != "production" && "${ENVIRONMENT}" != "staging" && "${ENVIRONMENT}" != "testing" ]]; then
    error "Environment must be 'production', 'staging', or 'testing'"
    show_usage
    exit 1
  fi
}

# Function to execute SSH commands
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

# Function to upload files via SCP
scp_upload() {
  local local_path="$1"
  local remote_path="$2"
  
  info "Uploading: ${local_path} to ${REMOTE_HOST}:${remote_path}"
  scp "${local_path}" "${REMOTE_USER}@${REMOTE_HOST}:${remote_path}" >> "${LOG_FILE}" 2>&1
  return $?
}

# Function to check if Docker container is healthy
check_container_health() {
  local container="$1"
  local max_attempts="${2:-30}"
  local wait_seconds="${3:-2}"
  local attempts=0
  
  info "Checking health of container: ${container}"
  
  while ((attempts < max_attempts)); do
    local status=$(ssh_exec "docker inspect --format='{{.State.Health.Status}}' ${container}" true)
    
    if [[ "${status}" == "healthy" ]]; then
      info "Container ${container} is healthy"
      return 0
    elif [[ "${status}" == "starting" ]]; then
      info "Container ${container} is starting (attempt ${attempts}/${max_attempts})"
    else
      warn "Container ${container} status: ${status} (attempt ${attempts}/${max_attempts})"
    fi
    
    ((attempts++))
    sleep "${wait_seconds}"
  done
  
  error "Container ${container} did not become healthy after ${max_attempts} attempts"
  return 1
}

# Function to validate remote environment
validate_environment() {
  info "Validating remote environment..."
  
  # Check if Docker is running
  if ! ssh_exec "docker ps > /dev/null 2>&1"; then
    error "Docker is not running on remote server"
    return 1
  fi
  
  # Check if the remote directory exists
  if ! ssh_exec "test -d ${REMOTE_DIR}"; then
    error "Remote directory not found: ${REMOTE_DIR}"
    return 1
  fi
  
  # Check disk space
  local disk_usage=$(ssh_exec "df -h / | awk 'NR==2 {print \$5}'" true | tr -d '%')
  if ((disk_usage > 90)); then
    warn "Disk usage is at ${disk_usage}% on remote server"
    if [[ "${FORCE_DEPLOY}" != "true" ]]; then
      error "Deployment aborted due to low disk space. Use -f to force deployment."
      return 1
    fi
  fi
  
  # Check Docker network configuration
  if ! ssh_exec "docker network ls | grep -q app_network"; then
    info "Creating app_network..."
    ssh_exec "docker network create app_network --internal"
  fi
  
  if ! ssh_exec "docker network ls | grep -q web_network"; then
    info "Creating web_network..."
    ssh_exec "docker network create web_network"
  fi
  
  info "Environment validation successful"
  return 0
}

# Function to create backup
create_backup() {
  if [[ "${CREATE_BACKUP}" != "true" ]]; then
    info "Skipping backup as requested"
    return 0
  fi
  
  local backup_dir="${REMOTE_DIR}/backups/${TIMESTAMP}"
  info "Creating backup in ${backup_dir}..."
  
  # Create backup directory
  if ! ssh_exec "mkdir -p ${backup_dir}"; then
    error "Failed to create backup directory"
    return 1
  fi
  
  # Backup docker-compose file
  ssh_exec "cp ${COMPOSE_FILE_REMOTE} ${backup_dir}/docker-compose.yml" || true
  
  # Backup volume data
  info "Backing up volume data..."
  
  # Backup member data
  if ssh_exec "test -d ${REMOTE_DIR}/data/member" true; then
    ssh_exec "tar -czf ${backup_dir}/member-data.tar.gz -C ${REMOTE_DIR}/data member"
  fi
  
  # Backup logs
  if ssh_exec "test -d ${REMOTE_DIR}/data/logs" true; then
    ssh_exec "tar -czf ${backup_dir}/logs.tar.gz -C ${REMOTE_DIR}/data logs"
  fi
  
  # Backup config
  if ssh_exec "test -d ${REMOTE_DIR}/data/config" true; then
    ssh_exec "tar -czf ${backup_dir}/config.tar.gz -C ${REMOTE_DIR}/data config"
  fi
  
  # Backup Redis data
  if ssh_exec "test -d ${REMOTE_DIR}/data/redis" true; then
    # Stop Redis container to ensure data consistency
    local redis_running=$(ssh_exec "docker ps -q --filter name=${REDIS_CONTAINER}" true)
    if [[ -n "${redis_running}" ]]; then
      info "Stopping Redis container for consistent backup..."
      ssh_exec "docker stop ${REDIS_CONTAINER}"
      sleep 2
    fi
    
    ssh_exec "tar -czf ${backup_dir}/redis-data.tar.gz -C ${REMOTE_DIR}/data redis"
    
    # Restart Redis if it was running
    if [[ -n "${redis_running}" ]]; then
      info "Restarting Redis container..."
      ssh_exec "docker start ${REDIS_CONTAINER}"
    fi
  fi
  
  # Backup Nginx configuration
  if ssh_exec "test -d ${REMOTE_DIR}/nginx" true; then
    ssh_exec "tar -czf ${backup_dir}/nginx-config.tar.gz -C ${REMOTE_DIR} nginx"
  fi
  
  # Create backup summary
  ssh_exec "echo 'Backup created on $(date)' > ${backup_dir}/backup-info.txt"
  ssh_exec "echo 'Environment: ${ENVIRONMENT}' >> ${backup_dir}/backup-info.txt"
  ssh_exec "echo 'Version: ${VERSION}' >> ${backup_dir}/backup-info.txt"
  
  # Verify backup
  if ! ssh_exec "ls -la ${backup_dir}" true; then
    error "Backup verification failed"
    return 1
  fi
  
  success "Backup completed in ${backup_dir}"
  return 0
}

# Function to prepare remote directory structure
prepare_remote_dirs() {
  info "Preparing remote directory structure..."
  
  # Create necessary directories
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/member"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/logs"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/config"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/redis"
  ssh_exec "mkdir -p ${REMOTE_DIR}/nginx/conf.d"
  ssh_exec "mkdir -p ${REMOTE_DIR}/nginx/ssl"
  ssh_exec "mkdir -p ${REMOTE_DIR}/data/logs/nginx"
  
  # Set correct permissions
  ssh_exec "chmod -R 755 ${REMOTE_DIR}/data"
  ssh_exec "chmod -R 755 ${REMOTE_DIR}/nginx"
  
  success "Remote directory structure prepared"
  return 0
}

# Function to handle rollback
rollback() {
  local reason="$1"
  local backup_dir="${REMOTE_DIR}/backups/${TIMESTAMP}"
  
  error "Deployment failed: ${reason}"
  error "Initiating rollback procedure..."
  
  # Check if we have a backup to restore
  if [[ "${CREATE_BACKUP}" == "true" ]] && ssh_exec "test -d ${backup_dir}" true; then
    info "Restoring from backup..."
    
    # Stop running containers
    ssh_exec "cd ${REMOTE_DIR} && docker-compose down" || true
    
    # Restore docker-compose file
    if ssh_exec "test -f ${backup_dir}/docker-compose.yml" true; then
      ssh_exec "cp ${backup_dir}/docker-compose.yml ${COMPOSE_FILE_REMOTE}"
    fi
    
    # Restore volume data
    if ssh_exec "test -f ${backup_dir}/member-data.tar.gz" true; then
      ssh_exec "tar -xzf ${backup_dir}/member-data.tar.gz -C ${REMOTE_DIR}/data"
    fi
    
    if ssh_exec "test -f ${backup_dir}/config.tar.gz" true; then
      ssh_exec "tar -xzf ${backup_dir}/config.tar.gz -C ${REMOTE_DIR}/data"
    fi
    
    if ssh_exec "test -f ${backup_dir}/redis-data.tar.gz" true; then
      ssh_exec "tar -xzf ${backup_dir}/redis-data.tar.gz -C ${REMOTE_DIR}/data"
    fi
    
    if ssh_exec "test -f ${backup_dir}/nginx-config.tar.gz" true; then
      ssh_exec "tar -xzf ${backup_dir}/nginx-config.tar.gz -C ${REMOTE_DIR}"
    fi
    
    # Start containers with the restored configuration
    ssh_exec "cd ${REMOTE_DIR} && docker-compose up -d"
    
    success "Rollback completed"
  else
    warn "No backup available for rollback or backup creation was skipped"
  fi
  
  return 1
}

# Function to prepare and upload docker-compose file
prepare_compose_file() {
  info "Preparing docker-compose file..."
  
  # Create a temporary file with the correct image tags
  local temp_file="${SCRIPT_DIR}/docker-compose.temp.yml"
  
  # Replace placeholders in the compose file
  cat "${SCRIPT_DIR}/${COMPOSE_FILE_LOCAL}" | \
    sed "s|build:|image: ${APP_IMAGE}:${VERSION}\\n    # build:|g" | \
    sed "s|image: nginx:stable-alpine|image: ${NGINX_IMAGE}|g" | \
    sed "s|image: redis:alpine|image: ${REDIS_IMAGE}|g" \
    > "${temp_file}"
  
  # Upload the file to the remote server
  if ! scp_upload "${temp_file}" "${COMPOSE_FILE_REMOTE}"; then
    error "Failed to upload docker-compose file"
    rm -f "${temp_file}"
    return 1
  fi
  
  # Clean up the temporary

#!/usr/bin/env bash

# =========================================================
# Willhaben.vip Docker Deployment Script
# =========================================================
#
# This script handles Docker-based deployment for Willhaben.vip
# on the production server.
#
# Features:
# - GitHub repository pulling
# - SSL certificate setup with Let's Encrypt
# - Docker Compose deployment management
# - Backup and rollback capabilities
# - Health checks and logging
#
# Usage:
#   ./deploy-docker.sh [pull|setup|deploy|rollback]
#
# Parameters:
#   pull     - Pull latest code from GitHub
#   setup    - Initial setup (directories, certificates)
#   deploy   - Deploy the application
#   rollback - Rollback to the previous version
#
# =========================================================

# Exit on error
set -e

# Configuration
REPO_URL="https://github.com/willhaben-vip/server.git"
BRANCH="main"
BASE_DIR="/opt/willhaben.vip"
APP_DIR="${BASE_DIR}/app"
DATA_DIR="${BASE_DIR}/data"
NGINX_DIR="${BASE_DIR}/nginx"
BACKUP_DIR="${BASE_DIR}/backups"
DOMAIN="willhaben.vip"
LOG_FILE="${BASE_DIR}/deploy-$(date +%Y%m%d%H%M%S).log"
COMPOSE_FILE="docker-compose.prod.yml"
GITHUB_TOKEN_FILE="${BASE_DIR}/.github_token"

# Initialize log
mkdir -p "$(dirname "$LOG_FILE")"
echo "=== Deployment started at $(date) ===" > "$LOG_FILE"

# =========================================================
# Helper Functions
# =========================================================

# Log message to both console and log file
log() {
    local message="[$(date +"%Y-%m-%d %H:%M:%S")] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Log error and exit
error() {
    log "ERROR: $1"
    exit 1
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Docker is installed and running
check_docker() {
    if ! command_exists docker; then
        error "Docker is not installed. Please install Docker and try again."
    fi
    
    if ! docker info > /dev/null 2>&1; then
        error "Docker daemon is not running or you don't have permissions to use it."
    fi
    
    log "Docker is installed and running"
}

# Check if Docker Compose is installed
check_docker_compose() {
    if ! (command -v docker-compose > /dev/null 2>&1 || docker compose version > /dev/null 2>&1); then
        error "Docker Compose is not installed. Please install Docker Compose and try again."
    fi
    
    log "Docker Compose is installed"
}

# Create required directories
create_directories() {
    log "Creating required directories"
    
    mkdir -p "$APP_DIR"
    mkdir -p "$DATA_DIR/member"
    mkdir -p "$DATA_DIR/logs/nginx"
    mkdir -p "$DATA_DIR/logs/app"
    mkdir -p "$DATA_DIR/config"
    mkdir -p "$DATA_DIR/redis"
    mkdir -p "$NGINX_DIR/conf.d"
    mkdir -p "$NGINX_DIR/ssl"
    mkdir -p "$BACKUP_DIR"
    
    log "Directories created successfully"
}

# =========================================================
# Repository Functions
# =========================================================

# Clone or pull the GitHub repository
pull_repository() {
    log "Pulling latest code from GitHub repository"
    
    if [ -d "$APP_DIR/.git" ]; then
        # Repository already exists, pull latest changes
        cd "$APP_DIR"
        git fetch origin
        git reset --hard "origin/$BRANCH"
        log "Repository updated to latest $BRANCH"
    else
        # First time clone
        if [ -f "$GITHUB_TOKEN_FILE" ]; then
            # Use token for private repository
            TOKEN=$(cat "$GITHUB_TOKEN_FILE")
            AUTH_REPO_URL=$(echo "$REPO_URL" | sed "s|https://|https://$TOKEN@|")
            git clone -b "$BRANCH" "$AUTH_REPO_URL" "$APP_DIR"
        else
            # Public repository
            git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
        fi
        log "Repository cloned successfully"
    fi
    
    # Check out latest tag if available
    cd "$APP_DIR"
    if git tag | grep -q "^v"; then
        LATEST_TAG=$(git tag | grep "^v" | sort -V | tail -n 1)
        git checkout "$LATEST_TAG"
        log "Checked out latest tag: $LATEST_TAG"
    fi
}

# =========================================================
# SSL Certificate Functions
# =========================================================

# Setup SSL certificates using Let's Encrypt
setup_ssl() {
    log "Setting up SSL certificates with Let's Encrypt"
    
    # Check if certificates already exist
    if [ -f "$NGINX_DIR/ssl/$DOMAIN.crt" ] && [ -f "$NGINX_DIR/ssl/$DOMAIN.key" ]; then
        # Check expiration date
        EXPIRATION=$(openssl x509 -in "$NGINX_DIR/ssl/$DOMAIN.crt" -noout -enddate | cut -d= -f2)
        EXPIRATION_EPOCH=$(date -d "$EXPIRATION" +%s)
        NOW_EPOCH=$(date +%s)
        
        # If certificate expires in more than 30 days, skip renewal
        if [ $((EXPIRATION_EPOCH - NOW_EPOCH)) -gt 2592000 ]; then
            log "SSL certificate is valid until $EXPIRATION. Skipping renewal."
            return 0
        fi
    fi
    
    # Install Certbot if not already installed
    if ! command_exists certbot; then
        log "Installing Certbot"
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Obtain or renew certificate
    log "Obtaining/renewing SSL certificate for $DOMAIN"
    certbot certonly --standalone -d "$DOMAIN" -d "www.$DOMAIN" --agree-tos --non-interactive --email admin@$DOMAIN
    
    # Copy certificates to Nginx directory
    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$NGINX_DIR/ssl/$DOMAIN.crt"
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem "$NGINX_DIR/ssl/$DOMAIN.key"
    
    log "SSL certificates installed successfully"
}

# =========================================================
# Docker Deployment Functions
# =========================================================

# Copy configuration files
copy_config_files() {
    log "Copying configuration files"
    
    # Copy Nginx configuration
    cp "$APP_DIR/nginx/willhaben.vip.conf" "$NGINX_DIR/conf.d/"
    
    # Copy Docker Compose production file
    cp "$APP_DIR/docker-compose.prod.yml" "$APP_DIR/"
    
    log "Configuration files copied successfully"
}

# Create backup of current deployment
create_backup() {
    log "Creating backup of current deployment"
    
    local BACKUP_PATH="$BACKUP_DIR/backup_$(date +%Y%m%d%H%M%S)"
    
    # Create backup directory
    mkdir -p "$BACKUP_PATH"
    
    # Backup app files
    rsync -a "$APP_DIR/" "$BACKUP_PATH/app/"
    
    # Backup data
    rsync -a "$DATA_DIR/" "$BACKUP_PATH/data/"
    
    # Backup Nginx configuration
    rsync -a "$NGINX_DIR/" "$BACKUP_PATH/nginx/"
    
    log "Backup created at $BACKUP_PATH"
}

# Deploy application with Docker Compose
deploy_application() {
    log "Deploying application with Docker Compose"
    
    cd "$APP_DIR"
    
    # Pull Docker images
    if command -v docker-compose > /dev/null 2>&1; then
        docker-compose -f $COMPOSE_FILE pull
        # Build and start services
        docker-compose -f $COMPOSE_FILE up -d --build
    else
        docker compose -f $COMPOSE_FILE pull
        # Build and start services
        docker compose -f $COMPOSE_FILE up -d --build
    fi
    
    log "Application deployed successfully"
}

# Check if deployment was successful
check_deployment() {
    log "Checking deployment health"
    
    # Wait for containers to start
    sleep 10
    
    # Check if all containers are running
    cd "$APP_DIR"
    if command -v docker-compose > /dev/null 2>&1; then
        if ! docker-compose -f $COMPOSE_FILE ps | grep -q "Up"; then
            log "Warning: Some containers may not be running properly"
            docker-compose -f $COMPOSE_FILE ps
            return 1
        fi
    else
        if ! docker compose -f $COMPOSE_FILE ps | grep -q "Up"; then
            log "Warning: Some containers may not be running properly"
            docker compose -f $COMPOSE_FILE ps
            return 1
        fi
    fi
    
    # Check application health
    local MAX_RETRIES=12
    local RETRY_DELAY=5
    local RETRIES=0
    
    while [ $RETRIES -lt $MAX_RETRIES ]; do
        if curl -sf http://localhost:2114 > /dev/null; then
            log "Application health check passed"
            return 0
        fi
        
        log "Waiting for application to be healthy... (retry $((RETRIES+1))/$MAX_RETRIES)"
        RETRIES=$((RETRIES+1))
        sleep $RETRY_DELAY
    done
    
    log "Warning: Application health check failed after $MAX_RETRIES retries"
    return 1
}

# Rollback to previous deployment
rollback_deployment() {
    log "Rolling back to previous deployment"
    
    # Find the latest backup
    local LATEST_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | sort -r | head -n 1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        error "No backup found to rollback to"
    fi
    
    log "Rolling back to backup: $LATEST_BACKUP"
    
    # Stop current deployment
    cd "$APP_DIR"
    if command -v docker-compose > /dev/null 2>&1; then
        docker-compose -f $COMPOSE_FILE down
    else
        docker compose -f $COMPOSE_FILE down
    fi
    
    # Restore from backup
    rsync -a "$LATEST_BACKUP/app/" "$APP_DIR/"
    rsync -a "$LATEST_BACKUP/nginx/" "$NGINX_DIR/"
    
    # Data is not restored by default to avoid data loss
    log "Note: Data directory was not restored to avoid data loss"
    
    # Start services again
    cd "$APP_DIR"
    if command -v docker-compose > /dev/null 2>&1; then
        docker-compose -f $COMPOSE_FILE up -d
    else
        docker compose -f $COMPOSE_FILE up -d
    fi
    
    log "Rollback completed"
}

# =========================================================
# Main Functions
# =========================================================

# Initial setup
setup() {
    log "Starting initial setup"
    
    check_docker
    check_docker_compose
    create_directories
    pull_repository
    setup_ssl
    copy_config_files
    
    log "Initial setup completed successfully"
}

# Deploy the application
deploy() {
    log "Starting deployment process"
    
    # Verify Docker is running
    check_docker
    
    # Create backup before deployment
    create_backup
    
    # Pull latest code
    pull_repository
    
    # Copy configuration files
    copy_config_files
    
    # Deploy application
    deploy_application
    
    # Check deployment health
    if ! check_deployment; then
        log "Deployment health check failed. Consider rollback."
    fi
    
    log "Deployment process completed"
}

# =========================================================
# Main Script
# =========================================================

main() {
    local command="${1:-deploy}"
    
    case "$command" in
        pull)
            pull_repository
            ;;
        setup)
            setup
            ;;
        deploy)
            deploy
            ;;
        rollback)
            rollback_deployment
            ;;
        *)
            echo "Unknown command: $command"
            echo "Usage: $0 [pull|setup|deploy|rollback]"
            exit 1
            ;;
    esac
    
    log "Command '$command' completed successfully"
    echo "==============================================" | tee -a "$LOG_FILE"
    echo "See $LOG_FILE for deployment details" | tee -a "$LOG_FILE"
    echo "==============================================" | tee -a "$LOG_FILE"
}

# Run main function with provided arguments
main "$@"

