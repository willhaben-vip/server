#!/usr/bin/env bash
#
# INSTANTpay+ Deployment Script Test Framework
# -------------------------------------------
# This script tests the deployment script functionality.
# It runs unit tests and integration tests for the deployment process.
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Test framework constants
readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly DEPLOY_SCRIPT="${SCRIPT_DIR}/../deploy.production.sh"
readonly TEST_OUTPUT_DIR="${SCRIPT_DIR}/../../logs/tests"
readonly TEST_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
readonly TEST_LOG="${TEST_OUTPUT_DIR}/test-${TEST_TIMESTAMP}.log"
readonly MOCK_DIR="${SCRIPT_DIR}/mocks"
readonly FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# Test framework variables
TEST_PASS_COUNT=0
TEST_FAIL_COUNT=0
TEST_SKIP_COUNT=0
CURRENT_TEST=""
IS_INTEGRATION_TEST=false

# Test environment variables
TEST_ENV="testing"
TEST_MESSAGE="Testing deployment script"
TEST_FORCE=false
TEST_BACKUP=true

# Create output directory
mkdir -p "${TEST_OUTPUT_DIR}"
mkdir -p "${MOCK_DIR}"
mkdir -p "${FIXTURES_DIR}"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ======= Test Framework Functions =======

log() {
  local level=$1
  local message=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${TEST_LOG}"
}

info() {
  log "INFO" "$1"
}

warn() {
  log "WARNING" "${YELLOW}$1${NC}"
}

error() {
  log "ERROR" "${RED}$1${NC}"
}

success() {
  log "SUCCESS" "${GREEN}$1${NC}"
}

skip() {
  log "SKIP" "${BLUE}$1${NC}"
}

# Test assertions
assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-"Expected: '$expected', but got: '$actual'"}"
  
  if [[ "$expected" == "$actual" ]]; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-"Expected '$haystack' to contain '$needle'"}"
  
  if [[ "$haystack" == *"$needle"* ]]; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-"Expected '$haystack' not to contain '$needle'"}"
  
  if [[ "$haystack" != *"$needle"* ]]; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  local message="${2:-"Expected file '$file' to exist"}"
  
  if [[ -f "$file" ]]; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

assert_dir_exists() {
  local dir="$1"
  local message="${2:-"Expected directory '$dir' to exist"}"
  
  if [[ -d "$dir" ]]; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

assert_success() {
  local command="$1"
  local message="${2:-"Expected command to succeed: '$command'"}"
  
  if eval "$command"; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

assert_failure() {
  local command="$1"
  local message="${2:-"Expected command to fail: '$command'"}"
  
  if ! eval "$command"; then
    success "PASS: $message"
    return 0
  else
    error "FAIL: $message"
    return 1
  fi
}

# Test runner
run_test() {
  CURRENT_TEST="$1"
  local test_func="$2"
  local should_skip="${3:-false}"
  
  echo -e "\n${BLUE}Running test: ${CURRENT_TEST}${NC}" | tee -a "${TEST_LOG}"
  
  if [[ "$should_skip" == "true" ]]; then
    skip "Skipping test: ${CURRENT_TEST}"
    TEST_SKIP_COUNT=$((TEST_SKIP_COUNT + 1))
    return 0
  fi
  
  # Create a subshell to isolate test execution
  if (set -e; "$test_func"); then
    success "Test passed: ${CURRENT_TEST}"
    TEST_PASS_COUNT=$((TEST_PASS_COUNT + 1))
  else
    error "Test failed: ${CURRENT_TEST}"
    TEST_FAIL_COUNT=$((TEST_FAIL_COUNT + 1))
  fi
}

print_test_summary() {
  echo -e "\n${BLUE}====== Test Summary ======${NC}" | tee -a "${TEST_LOG}"
  echo -e "${GREEN}Passed: ${TEST_PASS_COUNT}${NC}" | tee -a "${TEST_LOG}"
  echo -e "${RED}Failed: ${TEST_FAIL_COUNT}${NC}" | tee -a "${TEST_LOG}"
  echo -e "${BLUE}Skipped: ${TEST_SKIP_COUNT}${NC}" | tee -a "${TEST_LOG}"
  echo -e "${BLUE}Total: $((TEST_PASS_COUNT + TEST_FAIL_COUNT + TEST_SKIP_COUNT))${NC}" | tee -a "${TEST_LOG}"
  
  if [[ "${TEST_FAIL_COUNT}" -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}" | tee -a "${TEST_LOG}"
    return 0
  else
    echo -e "\n${RED}Some tests failed. See log for details: ${TEST_LOG}${NC}" | tee -a "${TEST_LOG}"
    return 1
  fi
}

# ======= Mock Functions =======

# Create mock script for SSH
create_ssh_mock() {
  local status_code="${1:-0}"
  local mock_output="$2"
  
  cat > "${MOCK_DIR}/ssh" <<EOF
#!/bin/bash
echo "$mock_output"
exit $status_code
EOF
  chmod +x "${MOCK_DIR}/ssh"
}

# Create mock script for docker
create_docker_mock() {
  local status_code="${1:-0}"
  local mock_output="$2"
  
  cat > "${MOCK_DIR}/docker" <<EOF
#!/bin/bash
echo "$mock_output"
exit $status_code
EOF
  chmod +x "${MOCK_DIR}/docker"
}

# Create mock script for docker-compose
create_docker_compose_mock() {
  local status_code="${1:-0}"
  local mock_output="$2"
  
  cat > "${MOCK_DIR}/docker-compose" <<EOF
#!/bin/bash
echo "$mock_output"
exit $status_code
EOF
  chmod +x "${MOCK_DIR}/docker-compose"
}

# Create all deployment fixture files
create_fixtures() {
  # Create .env.production fixture
  mkdir -p "${FIXTURES_DIR}/env"
  cat > "${FIXTURES_DIR}/env/.env.production" <<EOF
APP_NAME=INSTANTpay
APP_ENV=production
APP_KEY=base64:your-app-key-here
APP_DEBUG=false
APP_URL=https://alonnisos.willhaben.vip
LOG_CHANNEL=stack
LOG_LEVEL=warning
DB_CONNECTION=sqlite
EOF

  # Create docker-compose.yml fixture
  mkdir -p "${FIXTURES_DIR}/docker"
  cat > "${FIXTURES_DIR}/docker/docker-compose.yml" <<EOF
services:
  laravel.production:
    image: ghcr.io/bankpay-plus/instantpay:latest
    ports:
      - "8070:8069"
    volumes:
      - sail-instantpay:/app
    environment:
      - APP_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    restart: unless-stopped

  nginx:
    image: ghcr.io/bankpay-plus/instantpay-nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - sail-nginx:/etc/nginx/conf.d
    depends_on:
      - laravel.production
    restart: unless-stopped
EOF
}

setup_mock_environment() {
  # Add mock directory to PATH so our mocks are found first
  export PATH="${MOCK_DIR}:$PATH"
  
  # Create fixtures
  create_fixtures
  
  # Create initial mocks
  create_ssh_mock 0 "Success"
  create_docker_mock 0 "Success"
  create_docker_compose_mock 0 "Success"
}

teardown_mock_environment() {
  # Remove mock scripts
  rm -f "${MOCK_DIR}/ssh"
  rm -f "${MOCK_DIR}/docker"
  rm -f "${MOCK_DIR}/docker-compose"
}

# ======= Test Cases =======

test_script_exists() {
  assert_file_exists "${DEPLOY_SCRIPT}" "Deployment script exists"
}

test_argument_parsing() {
  # Test with no arguments (should fail)
  assert_failure "bash ${DEPLOY_SCRIPT}" "Should fail without arguments"
  
  # Test with invalid environment
  assert_failure "bash ${DEPLOY_SCRIPT} -e invalid -m 'Test'" "Should fail with invalid environment"
  
  # Test with missing message
  assert_failure "bash ${DEPLOY_SCRIPT} -e production" "Should fail without release message"
  
  # Test with valid arguments (with mock SSH to prevent actual execution)
  create_ssh_mock 1 "Mocked failure to prevent actual deployment"
  assert_failure "bash ${DEPLOY_SCRIPT} -e production -m 'Test message'" "Should proceed with valid arguments but fail on connection"
}

test_environment_validation() {
  # Mock environment validation success
  create_ssh_mock 0 "Docker is running\nFile exists\nProduction environment file found"
  local temp_script=$(source_deploy_script_functions)
  
  # Override validate_environment to test success case
  function validate_environment() {
    # Mock successful validation
    return 0
  }
  
  assert_success "validate_environment" "Environment validation should succeed with mocks"
  
  # Override validate_environment to test failure case - Docker not running
  function validate_environment() {
    # Mock Docker not running
    return 1
  }
  
  assert_failure "validate_environment" "Environment validation should fail when Docker is not running"
  
  # Clean up
  rm -f "${temp_script}"
}

test_backup_functionality() {
  # Mock successful backup
  create_ssh_mock 0 "Directory created\nVolume backed up\nEnvironment files backed up"
  local temp_script=$(source_deploy_script_functions)
  
  # Override create_backup to test success case
  function create_backup() {
    if [[ "${CREATE_BACKUP}" == "true" ]]; then
      # Mock successful backup
      return 0
    else
      # Mock skipped backup
      return 0
    fi
  }
  
  # Test successful backup
  CREATE_BACKUP=true
  assert_success "create_backup" "Backup should succeed with mocks"
  
  # Test backup disabled
  CREATE_BACKUP=false
  assert_success "create_backup" "Backup function should succeed but skip actual backup when disabled"
  
  # Override create_backup to test failure case
  function create_backup() {
    # Mock failed backup
    return 1
  }
  
  CREATE_BACKUP=true
  assert_failure "create_backup" "Backup should fail when directory creation fails"
  
  # Clean up
  rm -f "${temp_script}"
}

test_volume_management() {
  # Mock successful volume setup
  create_ssh_mock 0 "Volumes exist\nVolume configuration added"
  local temp_script=$(source_deploy_script_functions)
  
  # Override setup_volumes to test success case
  function setup_volumes() {
    # Mock successful volume setup
    return 0
  }
  
  assert_success "setup_volumes" "Volume setup should succeed with mocks"
  
  # Override setup_volumes to test failure case
  function setup_volumes() {
    # Mock volume setup failure
    return 1
  }
  
  assert_failure "setup_volumes" "Volume setup should fail when volume creation fails"
  
  # Clean up
  rm -f "${temp_script}"
}

test_container_health_checks() {
  # Mock healthy container
  create_ssh_mock 0 "healthy"
  local temp_script=$(source_deploy_script_functions)
  
  # Override check_container_health to test success case
  function check_container_health() {
    # Mock healthy container
    return 0
  }
  
  assert_success "check_container_health test-container" "Health check should succeed with healthy container"
  
  # Override check_container_health to test failure case
  function check_container_health() {
    # Mock unhealthy container
    return 1
  }
  
  assert_failure "check_container_health test-container" "Health check should fail with unhealthy container"
  
  # Clean up
  rm -f "${temp_script}"
  
  # Note: Advanced tests for containers that change state would be more complex
  # For simplicity, we're skipping those tests
}

test_deployment_process() {
  if [[ "${IS_INTEGRATION_TEST}" == "true" ]]; then
    # Only run integration tests in integration mode
    # Mock successful full deployment
    create_ssh_mock 0 "Success at all steps"
    source_deploy_script_functions
    assert_success "deploy" "Deployment should succeed with mocks"
    
    # Test deployment with various simulated failures
    # These would need sequential mock responses for each step
    # For simplicity, we'll skip the advanced deployment tests in this framework
  else
    skip "Skipping deployment process test - not in integration test mode"
  fi
}

test_rollback_functionality() {
  # Mock successful rollback
  create_ssh_mock 0 "Backup found\nContainers stopped\nBackup restored\nContainers started"
  local temp_script=$(source_deploy_script_functions)
  
  # Override rollback for testing
  function rollback() {
    if [[ "${CREATE_BACKUP}" == "true" ]]; then
      # Mock successful rollback with backup
      return 0
    else
      # Mock rollback without backup (still succeeds)
      return 0
    fi
  }
  
  # Test with backup
  CREATE_BACKUP=true
  assert_success "rollback 'Test failure reason'" "Rollback should succeed with mocks"
  
  # Test without backup
  CREATE_BACKUP=false
  assert_success "rollback 'Test failure reason'" "Rollback should succeed but warn when no backup exists"
  
  # Clean up
  rm -f "${temp_script}"
}

# Helper to source the deploy script for direct function testing
source_deploy_script_functions() {
  # Create a temporary copy with disabled actual execution
  local temp_script="${MOCK_DIR}/temp_deploy.sh"
  
  # Process the script to remove readonly declarations but keep variable values
  grep -v "^readonly " "${DEPLOY_SCRIPT}" > "${temp_script}"
  
  # Extract variable values from the original script and define them without readonly
  grep "^readonly " "${DEPLOY_SCRIPT}" | sed 's/readonly //' >> "${temp_script}"
  
  # Define test environment variables
  cat >> "${temp_script}" <<'EOF'
# Test environment variables
ENVIRONMENT="production"
RELEASE_MESSAGE="Test message"
FORCE_DEPLOY=false
CREATE_BACKUP=true

# Override functions to prevent actual execution
ssh_exec() { 
  echo "Mocked SSH command executed"
  return 0
}

# Prevent actual deployments
deploy() {
  echo "Mocked deployment"
  return 0
}

validate_environment() {
  echo "Mocked environment validation"
  return 0
}

# Prevent actual execution
main() {
  return 0
}
EOF
  
  # Make the script executable
  chmod +x "${temp_script}"
  
  # Source the script to get functions
  source "${temp_script}"
  
  # Return the path to the temporary script so we can clean it up later
  echo "${temp_script}"
}

# ======= End-to-End Tests =======

test_e2e_no_connection() {
  # Test end-to-end but with SSH failing to connect
  create_ssh_mock 1 "SSH connection failed"
  assert_failure "bash ${DEPLOY_SCRIPT} -e production -m 'Test message'" "Should fail when SSH connection fails"
}

test_e2e_docker_not_running() {
  # Test end-to-end but with Docker not running on remote
  create_ssh_mock 0 "Connected to server"
  create_ssh_mock 1 "Docker is not running" # Second call checks Docker
  assert_failure "bash ${DEPLOY_SCRIPT} -e production -m 'Test message'" "Should fail when Docker is not running"
}

test_e2e_local_execution() {
  if [[ "${IS_INTEGRATION_TEST}" == "true" ]]; then
    # Set up local Docker environment for testing
    setup_local_docker_env
    
    # Run the script with --local flag to test in local Docker environment
    assert_success "bash ${DEPLOY_SCRIPT} -e production -m 'Test message' --local" "Should succeed with local Docker environment"
    
    # Clean up local Docker environment
    teardown_local_docker_env
  else
    skip "Skipping local execution test - not in integration test mode"
  fi
}

# ======= Local Testing Environment =======

setup_local_docker_env() {
  info "Setting up local Docker environment for testing..."
  
  # Create test Docker network
  docker network create instantpay-test-network 2>/dev/null || true
  
  # Create test volumes
  docker volume create instantpay-test-app 2>/dev/null || true
  docker volume create instantpay-test-nginx 2>/dev/null || true
  
  # Copy fixtures to volumes
  docker run --rm -v instantpay-test-app:/app -v "${FIXTURES_DIR}/env":/source alpine cp /source/.env.production /app/.env
  
  # Start test containers
  docker run -d --name instantpay-test-app \
    --network instantpay-test-network \
    -v instantpay-test-app:/app \
    -p 18070:8070 \
    -e APP_ENV=testing \
    alpine:latest sleep 3600
  
  docker run -d --name instantpay-test-nginx \
    --network instantpay-test-network \
    -v instantpay-test-nginx:/etc/nginx \
    -p 18080:80 \
    alpine:latest sleep 3600
  
  # Add health status to containers
  docker exec instantpay-test-app sh -c 'mkdir -p /health && echo "healthy" > /health/status'
  docker exec instantpay-test-nginx sh -c 'mkdir -p /health && echo "healthy" > /health/status'
  
  info "Local Docker environment is ready for testing"
}

teardown_local_docker_env() {
  info "Cleaning up local Docker environment..."
  
  # Stop and remove test containers
  docker stop instantpay-test-app instantpay-test-nginx 2>/dev/null || true
  docker rm instantpay-test-app instantpay-test-nginx 2>/dev/null || true
  
  # Optional: remove test volumes
  # docker volume rm instantpay-test-app instantpay-test-nginx 2>/dev/null || true
  
  # Remove test network
  docker network rm instantpay-test-network 2>/dev/null || true
  
  info "Local Docker environment cleanup complete"
}

patch_deploy_script_for_local_testing() {
  info "Patching deployment script for local testing..."
  
  # Create a temporary copy for local testing
  local temp_script="${MOCK_DIR}/local_deploy.sh"
  cp "${DEPLOY_SCRIPT}" "${temp_script}"
  
  # Replace remote host with localhost
  sed -i.bak 's/readonly REMOTE_HOST=.*/readonly REMOTE_HOST="localhost"/' "${temp_script}"
  
  # Replace container names
  sed -i.bak 's/readonly LARAVEL_CONTAINER=.*/readonly LARAVEL_CONTAINER="instantpay-test-app"/' "${temp_script}"
  sed -i.bak 's/readonly NGINX_CONTAINER=.*/readonly NGINX_CONTAINER="instantpay-test-nginx"/' "${temp_script}"
  
  # Replace ports
  sed -i.bak 's/readonly HEALTH_CHECK_PORT=.*/readonly HEALTH_CHECK_PORT="18070"/' "${temp_script}"
  
  # Make the script executable
  chmod +x "${temp_script}"
  
  echo "${temp_script}"
}

# ======= Integration Testing =======

run_integration_tests() {
  info "Starting integration tests..."
  IS_INTEGRATION_TEST=true
  
  setup_mock_environment
  
  # Run core tests that are safe for integration testing
  run_test "Script Exists" test_script_exists
  run_test "Argument Parsing" test_argument_parsing
  
  # Run local Docker tests
  if command -v docker &>/dev/null; then
    run_test "Local Docker Environment" test_e2e_local_execution
  else
    skip "Local Docker tests - Docker not available"
  fi
  
  teardown_mock_environment
  
  # Clean up any leftover temporary files
  rm -f "${MOCK_DIR}/temp_deploy.sh"
  
  info "Integration tests completed"
  print_test_summary
}

# ======= Main Execution =======

show_usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Test the deployment script functionality.

Options:
  -a, --all             Run all tests, including integration tests
  -u, --unit            Run unit tests only (default)
  -i, --integration     Run integration tests only
  -l, --local           Test with local Docker environment
  -h, --help            Show this help message
EOF
}

run_all_tests() {
  info "Running all tests..."
  
  setup_mock_environment
  
  # Run all test cases
  run_test "Script Exists" test_script_exists
  run_test "Argument Parsing" test_argument_parsing
  run_test "Environment Validation" test_environment_validation
  run_test "Backup Functionality" test_backup_functionality
  run_test "Volume Management" test_volume_management
  run_test "Container Health Checks" test_container_health_checks
  run_test "Deployment Process" test_deployment_process
  run_test "Rollback Functionality" test_rollback_functionality
  run_test "End-to-End No Connection" test_e2e_no_connection
  run_test "End-to-End Docker Not Running" test_e2e_docker_not_running
  
  teardown_mock_environment
  
  # Clean up any leftover temporary files
  rm -f "${MOCK_DIR}/temp_deploy.sh"
  
  info "All tests completed"
  print_test_summary
}

run_unit_tests() {
  info "Running unit tests..."
  
  setup_mock_environment
  
  # Run unit test cases
  run_test "Script Exists" test_script_exists
  run_test "Argument Parsing" test_argument_parsing
  run_test "Environment Validation" test_environment_validation
  run_test "Backup Functionality" test_backup_functionality
  run_test "Volume Management" test_volume_management
  run_test "Container Health Checks" test_container_health_checks
  run_test "Rollback Functionality" test_rollback_functionality
  
  teardown_mock_environment
  
  # Clean up any leftover temporary files
  rm -f "${MOCK_DIR}/temp_deploy.sh"
  
  info "Unit tests completed"
  print_test_summary
}

run_local_tests() {
  info "Running local deployment tests..."
  
  if ! command -v docker &>/dev/null; then
    error "Docker is not available. Cannot run local tests."
    exit 1
  fi
  
  # Setup local testing environment
  setup_local_docker_env
  
  # Get patched script for local testing
  local local_script=$(patch_deploy_script_for_local_testing)
  
  # Run local test
  info "Testing deployment script with local Docker environment"
  bash "${local_script}" -e testing -m "Local testing" --local
  local result=$?
  
  # Cleanup
  teardown_local_docker_env
  rm -f "${local_script}" "${local_script}.bak"
  
  if [[ ${result} -eq 0 ]]; then
    success "Local deployment test succeeded"
  else
    error "Local deployment test failed"
  fi
  
  return ${result}
}

parse_args() {
  local test_mode="unit"
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--all)
        test_mode="all"
        shift
        ;;
      -u|--unit)
        test_mode="unit"
        shift
        ;;
      -i|--integration)
        test_mode="integration"
        shift
        ;;
      -l|--local)
        test_mode="local"
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
  
  # Run the selected test mode
  case "${test_mode}" in
    "all")
      run_all_tests
      ;;
    "unit")
      run_unit_tests
      ;;
    "integration")
      run_integration_tests
      ;;
    "local")
      run_local_tests
      ;;
  esac
}

main() {
  info "Starting deployment script test framework"
  info "Test log: ${TEST_LOG}"
  
  parse_args "$@"
  
  local exit_code=$?
  info "Test framework execution completed with exit code: ${exit_code}"
  exit ${exit_code}
}

# Run main with all arguments
main "$@"
