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

