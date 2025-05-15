#!/usr/bin/env bash

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
# Features:
# - Automatically excludes files and directories listed in .gitignore and .dockerignore
# - Always preserves the public/member directory
# - Handles version management and deployment to the production server
#
# =========================================================

# Exit on error
set -e

# Detect shell environment
SHELL_NAME=$(basename "$SHELL")

# Configuration
SERVER="nikolaos@alonnisos.willhaben.vip"
REMOTE_DIR="/var/www/willhaben.vip"
VERSION_FILE="VERSION"
ROADRUNNER_SERVICE="roadrunner"
REMOTE_TEMP_DIR="/home/nikolaos/willhaben_deploy_tmp"
REMOTE_BACKUP_DIR="${REMOTE_DIR}_backup_$(date +%Y%m%d%H%M%S)"
LOG_FILE="deployment_$(date +%Y%m%d%H%M%S).log"

# Initialize log
echo "=== Deployment started at $(date) ===" > "$LOG_FILE"

# Log shell information
log "Detected shell: $SHELL_NAME"

# =========================================================
# Helper Functions
# =========================================================

# Parse ignore files (.gitignore and .dockerignore) and convert patterns to rsync-compatible exclude options
# Returns an array of rsync exclude options
parse_ignore_files() {
    local excludes=()
    local gitignore=".gitignore"
    local dockerignore=".dockerignore"
    local files=("$gitignore" "$dockerignore")
    local file line pattern
    
    # Add critical exclusions that should always be present
    excludes+=("--exclude=deploy.sh")
    excludes+=("--exclude=$LOG_FILE")
    
    # Process each ignore file
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Processing exclusion patterns from $file"
            
            # Read the file line by line
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Skip empty lines and comments
                if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
                    continue
                fi
                
                # Trim whitespace
                line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                
                # Skip if empty after trim
                if [[ -z "$line" ]]; then
                    continue
                fi
                
                # Handle negation patterns (patterns starting with !)
                if [[ "$line" == !* ]]; then
                    # For rsync, we need to convert negated patterns differently
                    # We first remove the ! and prepare for using --include instead
                    pattern="${line#!}"
                    excludes+=("--include=$pattern")
                    continue
                fi
                
                # Handle directory-specific patterns
                if [[ "$line" == */ ]]; then
                    # Already ends with /, keep as is
                    excludes+=("--exclude=$line")
                elif [[ "$line" == /* ]]; then
                    # Remove leading / as rsync treats patterns as relative to the source dir
                    pattern="${line#/}"
                    excludes+=("--exclude=$pattern")
                else
                    # Regular pattern
                    excludes+=("--exclude=$line")
                fi
            done < "$file"
        else
            log "Warning: $file not found, skipping its patterns"
        fi
    done
    
    # Return the excludes array
    echo "${excludes[@]}"
}

# Create a temporary file with merged exclusion rules
# Returns the path to the created temporary file
create_exclude_file() {
    local temp_file
    
    # Create temporary file
    temp_file=$(mktemp /tmp/rsync-excludes.XXXXXX)
    
    # Add critical exclusions
    echo "- deploy.sh" >> "$temp_file"
    echo "- $LOG_FILE" >> "$temp_file"
    
    # Get exclusion patterns from ignore files and process them directly
    parse_ignore_files | tr ' ' '\n' | while read -r option pattern; do
        # Skip empty lines
        if [[ -z "$option" ]]; then
            continue
        fi
        
        # Extract the pattern part
        if [[ "$option" == "--exclude=" ]]; then
            echo "- ${option#--exclude=}${pattern}" >> "$temp_file"
        elif [[ "$option" == "--include=" ]]; then
            echo "+ ${option#--include=}${pattern}" >> "$temp_file"
        elif [[ "$option" == "--exclude"* ]]; then
            echo "- ${option#--exclude=}" >> "$temp_file"
        elif [[ "$option" == "--include"* ]]; then
            echo "+ ${option#--include=}" >> "$temp_file"
        fi
    done
    
    # Add special inclusion for public/member directory
    echo "+ */public/member/**" >> "$temp_file"
    
    # Print the temp file path
    echo "$temp_file"
}

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

# Initialize and update git submodules
init_update_submodules() {
    log "Initializing and updating git submodules"
    
    # Check if submodules exist
    if [ -f ".gitmodules" ]; then
        # Initialize submodules if not already done
        git submodule init || error "Failed to initialize git submodules"
        
        # Update submodules to latest commit on their tracked branch
        git submodule update --remote --recursive || error "Failed to update git submodules"
        
        log "Git submodules initialized and updated successfully"
    else
        log "No git submodules found (.gitmodules file not present)"
    fi
}

# Check if git submodules are properly initialized and updated
check_submodules() {
    log "Checking git submodule status"
    
    # Check if submodules exist
    if [ -f ".gitmodules" ]; then
        # Get submodule status and check for issues
        local submodule_status=$(git submodule status)
        
        # Check for uninitialized submodules (those with a "-" prefix)
        if echo "$submodule_status" | grep -q "^-"; then
            error "Uninitialized git submodules found. Run 'git submodule init && git submodule update' first."
        fi
        
        # Check for modified submodules (those with a "+" prefix)
        if echo "$submodule_status" | grep -q "^+"; then
            log "Warning: Some submodules have modified content. This might not match the tracked commit."
            log "Submodule status: \n$submodule_status"
            log "Continuing with deployment, but consider running 'git submodule update' first for consistency."
        else
            log "Git submodules are properly initialized and at the correct commits"
        fi
    else
        log "No git submodules found (.gitmodules file not present)"
    fi
}

# Check if git working tree is clean
check_git_clean() {
    check_git
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        error "Git working tree is not clean. Please commit or stash your changes before deploying."
    fi
    
    # Check if submodules are in a clean state
    git submodule foreach 'if [ -n "$(git status --porcelain)" ]; then exit 1; fi' > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        error "One or more git submodules have uncommitted changes. Please commit or stash these changes before deploying."
    fi
    
    log "Git working tree and submodules are clean. Proceeding with deployment."
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

# Create temporary directory with proper permissions
create_temp_directory() {
    log "Creating temporary directory on remote server"
    
    # Remove existing temp directory if it exists
    ssh "$SERVER" "rm -rf $REMOTE_TEMP_DIR" || log "Warning: Could not remove existing temporary directory"
    
    # Create new temp directory with proper permissions
    ssh "$SERVER" "mkdir -p $REMOTE_TEMP_DIR && chmod 755 $REMOTE_TEMP_DIR" || error "Failed to create temporary directory with proper permissions"
    
    # Verify directory was created and has proper permissions
    if ! ssh "$SERVER" "[ -d $REMOTE_TEMP_DIR ] && [ -w $REMOTE_TEMP_DIR ]"; then
        error "Temporary directory does not exist or is not writable"
    fi
    
    log "Temporary directory created successfully"
}

# Deploy files to server using rsync
deploy_files() {
    local version=$(get_current_version)
    local exclude_file
    
    log "Deploying version $version to $SERVER:$REMOTE_DIR"
    
    # Create temporary directory on remote server
    create_temp_directory
    
    # Create a temporary file with exclusion patterns from .gitignore and .dockerignore
    exclude_file=$(create_exclude_file)
    
    log "Using the following exclusion rules for deployment:"
    cat "$exclude_file" | while read line; do
        log "  $line"
    done
    
    # Sync files to temporary directory first, preserving submodules
    log "Starting rsync to temporary directory..."
    
    # Set a higher timeout for rsync to prevent timeouts on slow connections
    rsync_result=0
    rsync -avz --delete --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
        --timeout=300 \
        --filter="merge $exclude_file" \
        . "$SERVER:$REMOTE_TEMP_DIR/" || rsync_result=$?
    
    # Clean up temporary file regardless of rsync result
    rm -f "$exclude_file"
    
    # Check rsync result
    if [ $rsync_result -ne 0 ]; then
        error "Rsync failed with exit code $rsync_result. Please check your connection and try again."
    fi
    
    log "Files synced to temporary directory on server"
    
    # Verify files were successfully transferred to temp directory
    if ! ssh "$SERVER" "[ -d $REMOTE_TEMP_DIR ] && [ -f $REMOTE_TEMP_DIR/VERSION ]"; then
        error "Files were not successfully transferred to the temporary directory"
    fi
    
    # Backup existing installation if it exists
    ssh "$SERVER" "if [ -d $REMOTE_DIR ]; then sudo cp -a $REMOTE_DIR $REMOTE_BACKUP_DIR && sudo chown -R nikolaos:nikolaos $REMOTE_BACKUP_DIR; fi"
    
    # Ensure target directory exists with correct permissions
    ssh "$SERVER" "sudo mkdir -p $REMOTE_DIR && sudo chown nikolaos:nikolaos $REMOTE_DIR"
    
    # Move files from temp directory to actual directory
    ssh "$SERVER" "sudo rsync -a --delete --no-perms $REMOTE_TEMP_DIR/ $REMOTE_DIR/ && sudo chown -R nikolaos:nikolaos $REMOTE_DIR && rm -rf $REMOTE_TEMP_DIR"
    
    # Report the deployed submodule status
    log "Verifying deployed submodule content"
    ssh "$SERVER" "cd $REMOTE_DIR && find . -type d -name '.git' -path '*/public/member/*' | while read gitdir; do echo \"Submodule: \${gitdir%/.git}\"; done"
    
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

# Prepare submodules for deployment
prepare_submodules_for_deployment() {
    log "Preparing git submodules for deployment"
    
    # Initialize and update submodules
    init_update_submodules
    
    # Verify submodule status
    check_submodules
    
    # Create a list of submodule paths and their current commits for logging
    local submodule_info=$(git submodule status)
    log "Deploying with the following submodule versions: \n$submodule_info"
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
    
    # Prepare submodules for deployment
    prepare_submodules_for_deployment
    
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

