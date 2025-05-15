#!/bin/bash

# =========================================================
# Willhaben.vip Deployment Script
# =========================================================
#
# This script handles version management and deployment
# for the Willhaben.vip server on alonnisos.willhaben.vip.
#
# Usage:
#   ./deploy.sh [patch|minor|major]
#
# The optional parameter specifies how to bump the version:
#   patch: Increases the patch version (1.0.0 -> 1.0.1)
#   minor: Increases the minor version (1.0.0 -> 1.1.0)
#   major: Increases the major version (1.0.0 -> 2.0.0)
#
# If no parameter is provided, a patch version bump is assumed.
#
# =========================================================

# Exit on error
set -e

# Configuration
SERVER="nikolaos@alonnisos.willhaben.vip"
REMOTE_DIR="/var/www/willhaben.vip"
VERSION_FILE="VERSION"
ROADRUNNER_SERVICE="roadrunner"
REMOTE_TEMP_DIR="/tmp/willhaben_deploy"
REMOTE_BACKUP_DIR="${REMOTE_DIR}_backup_$(date +%Y%m%d%H%M%S)"
LOG_FILE="deployment_$(date +%Y%m%d%H%M%S).log"

# Initialize log
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

# =========================================================
# Version Management Functions
# =========================================================

# Initialize VERSION file if it doesn't exist
init_version_file() {
    if [ ! -f "$VERSION_FILE" ]; then
        log "Creating VERSION file with initial version 1.0.0"
        echo "1.0.0" > "$VERSION_FILE"
    fi
}

# Get current version from VERSION file
get_current_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        error "VERSION file not found. Run init_version_file first."
    fi
    cat "$VERSION_FILE"
}

# Bump version according to semantic versioning
bump_version() {
    local current_version=$(get_current_version)
    local bump_type="${1:-patch}"
    
    # Parse version components
    local major=$(echo "$current_version" | cut -d. -f1)
    local minor=$(echo "$current_version" | cut -d. -f2)
    local patch=$(echo "$current_version" | cut -d. -f3)
    
    # Bump version based on type
    case "$bump_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            error "Invalid version bump type: $bump_type. Use 'major', 'minor', or 'patch'."
            ;;
    esac
    
    local new_version="${major}.${minor}.${patch}"
    echo "$new_version" > "$VERSION_FILE"
    log "Version bumped from $current_version to $new_version ($bump_type)"
    
    return 0
}

# =========================================================
# Git Functions
# =========================================================

# Check if git is installed
check_git() {
    if ! command_exists git; then
        error "Git is not installed. Please install git and try again."
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        error "Current directory is not a git repository."
    fi
}

# Check if git working tree is clean
check_git_clean() {
    check_git
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        error "Git working tree is not clean. Please commit or stash your changes before deploying."
    fi
    
    log "Git working tree is clean. Proceeding with deployment."
}

# Create a git tag for the current version and push it
create_and_push_tag() {
    local version=$(get_current_version)
    local tag="v$version"
    
    log "Creating git tag: $tag"
    git tag -a "$tag" -m "Release version $version"
    
    log "Pushing git tag to remote"
    git push origin "$tag"
    
    # Also push the VERSION file change
    git add "$VERSION_FILE"
    git commit -m "Bump version to $version"
    git push origin HEAD
    
    log "Git tag $tag created and pushed successfully"
}

# =========================================================
# Deployment Functions
# =========================================================

# Check SSH connection to server
check_ssh_connection() {
    log "Checking SSH connection to $SERVER"
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SERVER" exit > /dev/null 2>&1; then
        error "Cannot connect to server via SSH. Please check your SSH configuration and that alonnisos.willhaben.vip is accessible."
    fi
    log "SSH connection to $SERVER is working"
}

# Deploy files to server using rsync
deploy_files() {
    local version=$(get_current_version)
    
    log "Deploying version $version to $SERVER:$REMOTE_DIR"
    
    # Create temporary directory on remote server
    ssh "$SERVER" "mkdir -p $REMOTE_TEMP_DIR"
    
    # Sync files to temporary directory first
    rsync -avz --delete \
        --exclude=".git/" \
        --exclude="vendor/" \
        --exclude="tests/" \
        --exclude="node_modules/" \
        --exclude=".env" \
        --exclude="deploy.sh" \
        --exclude="$LOG_FILE" \
        --exclude="*.log" \
        --exclude=".gitignore" \
        --exclude=".DS_Store" \
        --exclude="*.swp" \
        . "$SERVER:$REMOTE_TEMP_DIR/" || error "Rsync failed"
    
    log "Files synced to temporary directory on server"
    
    # Backup existing installation if it exists
    ssh "$SERVER" "if [ -d $REMOTE_DIR ]; then sudo cp -a $REMOTE_DIR $REMOTE_BACKUP_DIR && sudo chown -R nikolaos:nikolaos $REMOTE_BACKUP_DIR; fi"
    
    # Ensure target directory exists with correct permissions
    ssh "$SERVER" "sudo mkdir -p $REMOTE_DIR && sudo chown nikolaos:nikolaos $REMOTE_DIR"
    
    # Move files from temp directory to actual directory
    ssh "$SERVER" "sudo rsync -a --delete $REMOTE_TEMP_DIR/ $REMOTE_DIR/ && sudo chown -R nikolaos:nikolaos $REMOTE_DIR && rm -rf $REMOTE_TEMP_DIR"
    
    log "Deployment to server completed successfully"
}

# Install or update dependencies on server
install_dependencies() {
    log "Installing/updating dependencies on server"
    
    ssh "$SERVER" "cd $REMOTE_DIR && \
        if ! command -v composer > /dev/null; then \
            curl -sS https://getcomposer.org/installer | php && \
            sudo mv composer.phar /usr/local/bin/composer; \
        fi && \
        composer clear-cache && \
        composer config --global process-timeout 2000 && \
        composer install --no-dev --optimize-autoloader"
    
    log "Dependencies installed/updated successfully"
}

# Update RoadRunner binary on server if needed
update_roadrunner() {
    log "Checking for RoadRunner updates on server"
    
    # Check current RoadRunner version and update if needed
    ssh "$SERVER" "cd $REMOTE_DIR && \
        if [ ! -f ./rr ]; then \
            curl -L https://github.com/roadrunner-server/roadrunner/releases/download/v2025.1.1/roadrunner-2025.1.1-linux-amd64.tar.gz > roadrunner.tar.gz && \
            tar -xzf roadrunner.tar.gz && \
            mv roadrunner-*/rr . && \
            rm -rf roadrunner-* roadrunner.tar.gz; \
        fi && \
        chmod +x ./rr"
    
    log "RoadRunner binary checked/updated"
}

# Restart RoadRunner service
restart_roadrunner_service() {
    log "Restarting RoadRunner service"
    
    ssh "$SERVER" "if systemctl is-active --quiet $ROADRUNNER_SERVICE; then \
            sudo systemctl restart $ROADRUNNER_SERVICE; \
        else \
            sudo systemctl start $ROADRUNNER_SERVICE; \
        fi && \
        sudo systemctl status $ROADRUNNER_SERVICE"
    
    log "RoadRunner service restarted successfully"
}

# =========================================================
# Main Deployment Process
# =========================================================

main() {
    local bump_type="${1:-patch}"
    
    log "Starting deployment process with version bump type: $bump_type"
    
    # Initialize version file if it doesn't exist
    init_version_file
    
    # Ensure git is clean
    check_git_clean
    
    # Bump version
    bump_version "$bump_type"
    
    # Create and push git tag
    create_and_push_tag
    
    # Check SSH connection
    check_ssh_connection
    
    # Deploy files
    deploy_files
    
    # Install dependencies
    install_dependencies
    
    # Update RoadRunner
    update_roadrunner
    
    # Restart RoadRunner service
    restart_roadrunner_service
    
    log "Deployment completed successfully!"
    echo "==============================================" | tee -a "$LOG_FILE"
    echo "Deployed version $(get_current_version) to $SERVER:$REMOTE_DIR" | tee -a "$LOG_FILE"
    echo "See $LOG_FILE for deployment details" | tee -a "$LOG_FILE"
    echo "==============================================" | tee -a "$LOG_FILE"
}

# Run main function with provided arguments
main "$@"

