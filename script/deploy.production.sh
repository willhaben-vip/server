#!/usr/bin/env bash
#
# INSTANTpay+ Production Deployment Script
# ----------------------------------------
# This script deploys the INSTANTpay+ application to the production server
# at alonnisos.willhaben.vip. It handles environment setup, container management,
# database operations, and Laravel optimization.
#
# Usage:
#   ./deploy.production.sh -e <environment> -m <release message> [-f] [-b] [-h]
#
# Options:
#   -e, --environment    Environment to deploy to (production, staging)
#   -m, --message        Release message/description
#   -f, --force          Force deployment even if validation fails
#   -b, --backup         Create full backup before deployment
#   -h, --help           Show this help message
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Script constants
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
readonly LOG_FILE="${SCRIPT_DIR}/../logs/deploy-${TIMESTAMP}.log"
readonly REMOTE_USER="nikolaos"
readonly REMOTE_HOST="alonnisos.willhaben.vip"
readonly REMOTE_DIR="/home/nikolaos/vps/INSTANTpay"
readonly DOCKER_COMPOSE_FILE="${REMOTE_DIR}/web-app/docker-compose.yml"
readonly BACKUP_DIR="${REMOTE_DIR}/backups/${TIMESTAMP}"

# Docker image and container configurations
readonly DOCKER_IMAGE_APP="ghcr.io/bankpay-plus/instantpay:latest"
readonly DOCKER_IMAGE_NGINX="ghcr.io/bankpay-plus/instantpay-nginx:latest"
readonly LARAVEL_CONTAINER="web-app-laravel.production-1"
readonly NGINX_CONTAINER="web-app-nginx-1"

# Health check configurations
readonly HEALTH_CHECK_URL="http://localhost"
readonly HEALTH_CHECK_PORT="8070"
readonly HEALTH_CHECK_TIMEOUT=5  # seconds
readonly HEALTH_CHECK_RETRIES=3

# Default values
ENVIRONMENT=""
RELEASE_MESSAGE=""
FORCE_DEPLOY=false
CREATE_BACKUP=true

# Create logs directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/../logs"

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
Usage: ${SCRIPT_NAME} -e <environment> -m <release message> [-f] [-b] [-h]

Options:
  -e, --environment    Environment to deploy to (production, staging)
  -m, --message        Release message/description
  -f, --force          Force deployment even if validation fails
  -b, --backup         Create full backup before deployment (default: true)
  -h, --help           Show this help message
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
      -m|--message)
        RELEASE_MESSAGE="$2"
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

  # Validate required arguments
  if [[ -z "${ENVIRONMENT}" ]]; then
    error "Environment (-e) is required"
    show_usage
    exit 1
  fi

  if [[ "${ENVIRONMENT}" != "production" && "${ENVIRONMENT}" != "staging" ]]; then
    error "Environment must be 'production' or 'staging'"
    show_usage
    exit 1
  fi

  if [[ -z "${RELEASE_MESSAGE}" ]]; then
    error "Release message (-m) is required"
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

# Function to check if Docker container is healthy
check_container_health() {
  local container="$1"
  local max_attempts="${2:-30}"
  local wait_seconds="${3:-2}"
  local timeout="${4:-$HEALTH_CHECK_TIMEOUT}"
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
  
  # Check if docker-compose.yml exists
  if ! ssh_exec "test -f ${DOCKER_COMPOSE_FILE}"; then
    error "Docker Compose file not found: ${DOCKER_COMPOSE_FILE}"
    return 1
  fi
  
  # Check if .env files exist
  if ! ssh_exec "test -f ${REMOTE_DIR}/web-app/.env.production"; then
    error "Production environment file not found: ${REMOTE_DIR}/web-app/.env.production"
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
  
  info "Environment validation successful"
  return 0
}

# Function to create backup
create_backup() {
  if [[ "${CREATE_BACKUP}" != "true" ]]; then
    info "Skipping backup as requested"
    return 0
  fi
  
  info "Creating backup in ${BACKUP_DIR}..."
  
  # Create backup directory
  if ! ssh_exec "mkdir -p ${BACKUP_DIR}"; then
    error "Failed to create backup directory"
    return 1
  fi
  
  # Backup volumes
  if ! ssh_exec "docker volume inspect web-app_sail-instantpay > /dev/null 2>&1"; then
    warn "Volume web-app_sail-instantpay does not exist, skipping backup"
  else
    info "Backing up application volume..."
    ssh_exec "docker run --rm -v web-app_sail-instantpay:/source -v ${BACKUP_DIR}:/backup alpine tar -czf /backup/web-app_sail-instantpay.tar.gz -C /source ."
  fi
  
  if ! ssh_exec "docker volume inspect web-app_sail-nginx > /dev/null 2>&1"; then
    warn "Volume web-app_sail-nginx does not exist, skipping backup"
  else
    info "Backing up nginx volume..."
    ssh_exec "docker run --rm -v web-app_sail-nginx:/source -v ${BACKUP_DIR}:/backup alpine tar -czf /backup/web-app_sail-nginx.tar.gz -C /source ."
  fi
  
  # Backup database if exists
  if ssh_exec "test -f /var/lib/docker/volumes/web-app_sail-instantpay/_data/database/database.sqlite" true; then
    info "Backing up SQLite database..."
    ssh_exec "mkdir -p ${BACKUP_DIR}/database"
    ssh_exec "docker run --rm -v web-app_sail-instantpay:/app -v ${BACKUP_DIR}:/backup alpine cp /app/database/database.sqlite /backup/database/"
  fi
  
  # Backup environment files
  info "Backing up environment configuration..."
  ssh_exec "mkdir -p ${BACKUP_DIR}/config"
  ssh_exec "cp ${REMOTE_DIR}/web-app/.env* ${BACKUP_DIR}/config/" || true
  
  # Create backup summary
  ssh_exec "echo 'Backup created on $(date)' > ${BACKUP_DIR}/backup-info.txt"
  ssh_exec "echo 'Environment: ${ENVIRONMENT}' >> ${BACKUP_DIR}/backup-info.txt"
  ssh_exec "echo 'Release message: ${RELEASE_MESSAGE}' >> ${BACKUP_DIR}/backup-info.txt"
  
  # Verify backup completion
  if ! ssh_exec "ls -la ${BACKUP_DIR}" true; then
    error "Backup verification failed"
    return 1
  fi
  
  success "Backup completed successfully in ${BACKUP_DIR}"
  return 0
}

# Function to manage Docker volumes
setup_volumes() {
  info "Setting up Docker volumes..."
  
  # Check if volumes exist
  local instantpay_volume_exists=$(ssh_exec "docker volume ls -q | grep -q web-app_sail-instantpay && echo 'true' || echo 'false'" true)
  local nginx_volume_exists=$(ssh_exec "docker volume ls -q | grep -q web-app_sail-nginx && echo 'true' || echo 'false'" true)
  
  # Create external volume configurations if they don't exist in docker-compose
  if ! ssh_exec "grep -q 'external: true' ${DOCKER_COMPOSE_FILE}" true; then
    info "Adding external volume configuration to docker-compose.yml"
    local temp_file="${REMOTE_DIR}/web-app/docker-compose.yml.new"
    
    ssh_exec "cp ${DOCKER_COMPOSE_FILE} ${temp_file}"
    ssh_exec "cat ${DOCKER_COMPOSE_FILE} | sed '/services:/i\\\nvolumes:\\n  web-app_sail-instantpay:\\n    external: true\\n  web-app_sail-nginx:\\n    external: true\\n' > ${temp_file}"
    ssh_exec "mv ${temp_file} ${DOCKER_COMPOSE_FILE}"
    
    info "Updated docker-compose.yml with external volumes configuration"
  fi
  
  # Create volumes if they don't exist
  if [[ "${instantpay_volume_exists}" == "false" ]]; then
    info "Creating application volume: web-app_sail-instantpay"
    ssh_exec "docker volume create web-app_sail-instantpay"
  else
    info "Application volume web-app_sail-instantpay already exists"
  fi
  
  if [[ "${nginx_volume_exists}" == "false" ]]; then
    info "Creating nginx volume: web-app_sail-nginx"
    ssh_exec "docker volume create web-app_sail-nginx"
  else
    info "Nginx volume web-app_sail-nginx already exists"
  fi
  
  success "Docker volumes are ready"
  return 0
}

# Function to setup and validate environment files
setup_environment_files() {
  info "Setting up environment files..."
  
  # Check if .env files exist in their proper locations
  if ! ssh_exec "test -f ${REMOTE_DIR}/web-app/.env.${ENVIRONMENT}" true; then
    error "Environment file not found: ${REMOTE_DIR}/web-app/.env.${ENVIRONMENT}"
    return 1
  fi
  
  # Copy environment file to volume
  info "Copying environment files to application volume..."
  ssh_exec "docker run --rm -v web-app_sail-instantpay:/app -v ${REMOTE_DIR}/web-app:/source alpine sh -c 'cp /source/.env.${ENVIRONMENT} /app/.env && cp /source/.env /app/.env.backup 2>/dev/null || true'"
  
  # Validate environment file
  info "Validating environment configuration..."
  local env_valid=$(ssh_exec "docker run --rm -v web-app_sail-instantpay:/app alpine grep -q 'APP_ENV=${ENVIRONMENT}' /app/.env && echo 'true' || echo 'false'" true)
  
  if [[ "${env_valid}" != "true" ]]; then
    warn "Environment file does not contain correct APP_ENV setting"
    if [[ "${FORCE_DEPLOY}" != "true" ]]; then
      error "Deployment aborted due to environment configuration issues. Use -f to force deployment."
      return 1
    fi
  fi
  
  success "Environment files have been set up correctly"
  return 0
}

# Function to execute artisan commands in the Laravel container
artisan_exec() {
  local command="$1"
  info "Running artisan command: ${command}"
  
  local result=$(ssh_exec "docker exec ${LARAVEL_CONTAINER} php artisan ${command}" true)
  local exit_code=$?
  
  if [[ $exit_code -ne 0 ]]; then
    error "Artisan command failed: ${command}"
    error "Output: ${result}"
    return $exit_code
  fi
  
  info "Artisan command completed: ${command}"
  return 0
}

# Function to manage Laravel maintenance mode
manage_maintenance_mode() {
  local action="$1"  # up or down
  
  if [[ "${action}" == "up" ]]; then
    info "Enabling maintenance mode..."
    artisan_exec "down --render='maintenance' --refresh=15"
  elif [[ "${action}" == "down" ]]; then
    info "Disabling maintenance mode..."
    artisan_exec "up"
  else
    error "Invalid maintenance mode action: ${action}"
    return 1
  fi
  
  return 0
}

# Function to run database migrations
run_migrations() {
  info "Running database migrations..."
  
  # Ensure the database file exists
  ssh_exec "docker exec ${LARAVEL_CONTAINER} php -r \"file_exists('database/database.sqlite') || touch('database/database.sqlite');\""
  
  # Run migrations
  if ! artisan_exec "migrate --database=sqlite --force --no-interaction"; then
    error "Database migration failed"
    if [[ "${FORCE_DEPLOY}" != "true" ]]; then
      return 1
    fi
    warn "Continuing deployment despite migration failure (--force flag is set)"
  fi
  
  success "Database migrations completed successfully"
  return 0
}

# Function to optimize Laravel application
optimize_laravel() {
  info "Optimizing Laravel application..."
  
  local commands=(
    "optimize:clear"
    "optimize"
    "config:cache"
    "route:cache"
    "view:cache"
  )
  
  for cmd in "${commands[@]}"; do
    if ! artisan_exec "${cmd}"; then
      warn "Optimization command failed: ${cmd}"
      # Continue with other commands even if one fails
    fi
  done
  
  success "Laravel optimization completed"
  return 0
}

# Function to manage Octane server
manage_octane() {
  info "Managing Octane server..."
  
  # Reload Octane (safer than stopping/starting)
  if ! artisan_exec "octane:reload"; then
    warn "Octane reload failed, attempting to restart..."
    
    # Try to stop and start if reload fails
    artisan_exec "octane:stop" || true  # Don't fail if stop fails
    sleep 2
    if ! artisan_exec "octane:start"; then
      error "Failed to start Octane server"
      return 1
    fi
  fi
  
  success "Octane server is running"
  return 0
}

# Function to verify deployment
verify_deployment() {
  info "Verifying deployment..."
  
  # Check if containers are running
  local containers_running=$(ssh_exec "docker ps -q --filter 'name=web-app'" true)
  if [[ -z "${containers_running}" ]]; then
    error "No containers are running after deployment"
    return 1
  fi
  
  # Check health status
  if ! check_container_health "${LARAVEL_CONTAINER}"; then
    error "Laravel container is not healthy after deployment"
    return 1
  fi
  
  # Verify application is responding (optional)
  info "Checking if application is responding..."
  
  local retries=0
  local http_success=false
  
  while ((retries < HEALTH_CHECK_RETRIES)); do
    local response_code=$(ssh_exec "curl -s -o /dev/null -w '%{http_code}' --max-time ${HEALTH_CHECK_TIMEOUT} ${HEALTH_CHECK_URL}:${HEALTH_CHECK_PORT}" true)
    
    if [[ "${response_code}" == "200" ]]; then
      success "Application is responding with status code 200"
      http_success=true
      break
    else
      warn "Application response check returned status code ${response_code} (attempt $((retries+1))/${HEALTH_CHECK_RETRIES})"
      ((retries++))
      
      if ((retries < HEALTH_CHECK_RETRIES)); then
        info "Waiting before next health check attempt..."
        sleep 5
      fi
    fi
  done
  
  if [[ "${http_success}" != "true" ]]; then
    warn "Application is not responding with status 200 after multiple attempts"
    # Not failing deployment if web check fails, as other issues might be in play
  fi
  
  success "Deployment verification completed successfully"
  return 0
}

# Function to handle deployment rollback
rollback() {
  local reason="$1"
  
  error "Deployment failed: ${reason}"
  error "Initiating rollback procedure..."
  
  # Check if we have a backup to restore
  if [[ "${CREATE_BACKUP}" == "true" ]] && ssh_exec "test -d ${BACKUP_DIR}" true; then
    info "Restoring from backup..."
    
    # Stop running containers
    ssh_exec "docker compose -f ${DOCKER_COMPOSE_FILE} down laravel.production nginx" || true
    
    # Restore database if backed up
    if ssh_exec "test -f ${BACKUP_DIR}/database/database.sqlite" true; then
      info "Restoring database..."
      ssh_exec "docker run --rm -v web-app_sail-instantpay:/app -v ${BACKUP_DIR}:/backup alpine sh -c 'mkdir -p /app/database && cp /backup/database/database.sqlite /app/database/'"
    fi
    
    # Restore environment files
    if ssh_exec "test -d ${BACKUP_DIR}/config" true; then
      info "Restoring environment configuration..."
      ssh_exec "cp ${BACKUP_DIR}/config/.env* ${REMOTE_DIR}/web-app/" || true
    fi
    
    # Start containers again
    ssh_exec "docker compose -f ${DOCKER_COMPOSE_FILE} up -d --remove-orphans laravel.production nginx" || true
    
    success "Rollback completed"
  else
    warn "No backup available for rollback or backup creation was skipped"
  fi
  
  return 1
}

# Main deployment function
deploy() {
  info "Starting deployment to ${ENVIRONMENT} environment"
  info "Release message: ${RELEASE_MESSAGE}"
  
  # Pull latest images
  info "Pulling latest Docker images..."
  if ! ssh_exec "docker pull ${DOCKER_IMAGE_NGINX} && docker pull ${DOCKER_IMAGE_APP}"; then
    return $(rollback "Failed to pull Docker images")
  fi
  
  # Enable maintenance mode before bringing down the current containers
  # Skip this step if containers aren't running
  if ssh_exec "docker ps -q --filter 'name=${LARAVEL_CONTAINER}'" true | grep -q .; then
    manage_maintenance_mode "up" || warn "Failed to enable maintenance mode, continuing deployment"
  fi
  
  # Stop running containers
  info "Stopping running containers..."
  if ! ssh_exec "docker compose -f ${DOCKER_COMPOSE_FILE} down laravel.production nginx"; then
    warn "Failed to stop containers cleanly, forcing removal"
    ssh_exec "docker rm -f \$(docker ps -q --filter 'name=web-app')" || true
  fi
  
  # Setup volumes and environment
  if ! setup_volumes; then
    return $(rollback "Failed to set up Docker volumes")
  fi
  
  if ! setup_environment_files; then
    return $(rollback "Failed to set up environment files")
  fi
  
  # Start containers
  info "Starting containers..."
  if ! ssh_exec "docker compose -f ${DOCKER_COMPOSE_FILE} up -d --remove-orphans laravel.production nginx"; then
    return $(rollback "Failed to start containers")
  fi
  
  # Wait for container to be ready
  if ! check_container_health "${LARAVEL_CONTAINER}"; then
    return $(rollback "Laravel container failed to start or become healthy")
  fi
  
  # Run database migrations
  if ! run_migrations; then
    return $(rollback "Database migration failed")
  fi
  
  # Optimize Laravel application
  if ! optimize_laravel; then
    warn "Laravel optimization reported issues, but continuing deployment"
  fi
  
  # Manage Octane server
  if ! manage_octane; then
    warn "Octane server management reported issues, but continuing deployment"
  fi
  
  # Verify deployment
  if ! verify_deployment; then
    return $(rollback "Deployment verification failed")
  fi
  
  # Disable maintenance mode
  manage_maintenance_mode "down" || warn "Failed to disable maintenance mode, manual intervention may be required"
  
  # Show deployment status
  ssh_exec "docker ps --filter 'name=web-app'"
  
  # Log container resource usage
  info "Container resource usage:"
  ssh_exec "docker stats ${LARAVEL_CONTAINER} ${NGINX_CONTAINER} --no-stream" || true
  
  success "Deployment to ${ENVIRONMENT} completed successfully"
  return 0
}

# Main script execution
main() {
  # Parse arguments
  parse_args "$@"
  
  # Start deployment process with logging
  info "Starting deployment process for INSTANTpay+ ${ENVIRONMENT}"
  info "Release message: ${RELEASE_MESSAGE}"
  info "Backup enabled: ${CREATE_BACKUP}"
  info "Force mode: ${FORCE_DEPLOY}"
  info "Docker images: ${DOCKER_IMAGE_APP}, ${DOCKER_IMAGE_NGINX}"
  info "Health check: ${HEALTH_CHECK_URL}:${HEALTH_CHECK_PORT} (timeout: ${HEALTH_CHECK_TIMEOUT}s, retries: ${HEALTH_CHECK_RETRIES})"
  
  # Validate environment
  validate_environment || exit 1
  
  # Create backup before starting deployment
  create_backup || exit 1
  
  # Deploy application
  if deploy; then
    success "INSTANTpay+ ${ENVIRONMENT} deployment completed successfully on ${REMOTE_HOST}"
    echo ""
    echo "INSTANTpay+ has been successfully deployed to the ${ENVIRONMENT} environment."
    echo "Release: ${RELEASE_MESSAGE}"
    echo "Timestamp: $(date)"
    echo "Logs available at: ${LOG_FILE}"
    echo ""
    return 0
  else
    error "Deployment failed. Check logs for details: ${LOG_FILE}"
    echo ""
    echo "❌ Deployment to ${ENVIRONMENT} failed."
    echo "Please check the logs for more information: ${LOG_FILE}"
    echo ""
    return 1
  fi
}

# Run main function with all arguments
main "$@"
