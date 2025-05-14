#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Environment variable to control which environment to use
ENV=${ENV:-production}
COMPOSE_FILE="docker-compose.yml"
if [ "$ENV" = "development" ]; then
    COMPOSE_FILE="docker-compose.dev.yml"
fi

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_message "$RED" "Error: Docker is not running"
        exit 1
    fi
}

# Start the services
start() {
    print_message "$GREEN" "Starting services in $ENV environment..."
    docker-compose -f $COMPOSE_FILE up -d
    print_message "$GREEN" "Services started"
    if [ "$ENV" = "development" ]; then
        print_message "$YELLOW" "Development URLs:"
        print_message "$YELLOW" "Application: http://localhost:8080"
        print_message "$YELLOW" "Health check: http://localhost:2114"
        print_message "$YELLOW" "Metrics: http://localhost:2112"
        print_message "$YELLOW" "Prometheus: http://localhost:9090"
        print_message "$YELLOW" "Grafana: http://localhost:3000 (admin/secret)"
        print_message "$YELLOW" "Node Exporter: http://localhost:9100"
    else
        print_message "$YELLOW" "Application URL: http://localhost:8080"
    fi
}

# Stop the services
stop() {
    print_message "$GREEN" "Stopping services in $ENV environment..."
    docker-compose -f $COMPOSE_FILE down
    print_message "$GREEN" "Services stopped"
}

# Restart the services
restart() {
    print_message "$GREEN" "Restarting services in $ENV environment..."
    docker-compose -f $COMPOSE_FILE restart
    print_message "$GREEN" "Services restarted"
}

# Show logs
logs() {
    if [ "$2" ]; then
        docker-compose -f $COMPOSE_FILE logs -f $2
    else
        docker-compose -f $COMPOSE_FILE logs -f
    fi
}

# Build the images
build() {
    print_message "$GREEN" "Building images for $ENV environment..."
    docker-compose -f $COMPOSE_FILE build --no-cache
    print_message "$GREEN" "Build complete"
}

# Show status
status() {
    print_message "$YELLOW" "Status for $ENV environment:"
    docker-compose -f $COMPOSE_FILE ps
}

# Clean up
clean() {
    print_message "$YELLOW" "Cleaning up $ENV environment..."
    docker-compose -f $COMPOSE_FILE down -v --remove-orphans
    print_message "$GREEN" "Clean up complete"
}

# Show help
show_help() {
    echo "Usage: ENV=[production|development] $0 {start|stop|restart|logs|build|status|clean}"
    echo "Commands:"
    echo "  start   - Start the services"
    echo "  stop    - Stop the services"
    echo "  restart - Restart the services"
    echo "  logs    - Show logs (optionally specify service name)"
    echo "  build   - Build the images"
    echo "  status  - Show status"
    echo "  clean   - Clean up containers and volumes"
    echo ""
    echo "Environment:"
    echo "  ENV=production   - Use production configuration (default)"
    echo "  ENV=development  - Use development configuration with monitoring"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start production environment"
    echo "  ENV=development $0 start    # Start development environment"
    echo "  $0 logs roadrunner          # Show logs for roadrunner service"
}

# Main script
check_docker

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    logs)
        logs "$@"
        ;;
    build)
        build
        ;;
    status)
        status
        ;;
    clean)
        clean
        ;;
    *)
        show_help
        exit 1
        ;;
esac

exit 0
