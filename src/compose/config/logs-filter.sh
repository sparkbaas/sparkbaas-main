#!/bin/bash
# logs-filter.sh - Filter Docker Compose logs to show only warnings and errors

# Colors for better readability
YELLOW='\033[1;33m' # Warning
RED='\033[0;31m'    # Error
CYAN='\033[0;36m'   # Info (service name)
NC='\033[0m'        # No Color

# Help message
show_help() {
    echo "Usage: ./logs-filter.sh [options] [service...]"
    echo ""
    echo "Filter Docker Compose logs to show only warnings and errors"
    echo ""
    echo "Options:"
    echo "  -f, --follow       Follow log output (like tail -f)"
    echo "  -a, --all          Show all log levels (including INFO, DEBUG)"
    echo "  -t, --timestamps   Show timestamps"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./logs-filter.sh              # Show all services' warnings and errors"
    echo "  ./logs-filter.sh -f           # Follow all services' warnings and errors"
    echo "  ./logs-filter.sh postgres     # Show only postgres warnings and errors"
    echo "  ./logs-filter.sh -a           # Show all logs (no filtering)"
    echo ""
}

# Default options
FOLLOW=""
SERVICES=""
SHOW_ALL=0
TIMESTAMPS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--follow)
            FOLLOW="--follow"
            shift
            ;;
        -a|--all)
            SHOW_ALL=1
            shift
            ;;
        -t|--timestamps)
            TIMESTAMPS="--timestamps"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            SERVICES="$SERVICES $1"
            shift
            ;;
    esac
done

cd "$(dirname "$0")/.."

if [ $SHOW_ALL -eq 1 ]; then
    # Show all logs without filtering
    docker compose logs $FOLLOW $TIMESTAMPS $SERVICES
else
    # Filter for warnings and errors only
    docker compose logs $FOLLOW $TIMESTAMPS $SERVICES | grep --color=always -i -E "warn|error|critical|fatal|exception|fail" | 
    while IFS= read -r line; do
        # Colorize based on log level
        if [[ "$line" =~ (WARN|WARNING|WRNG) ]]; then
            echo -e "${line/WARN/$YELLOW WARN$NC}" | sed -E "s/\| ([^|]+)(WARN|WARNING|WRNG)/$CYAN| \1$YELLOW\2$NC/g"
        elif [[ "$line" =~ (ERROR|FATAL|CRITICAL|EXCEPTION|FAIL) ]]; then
            echo -e "${line/ERROR/$RED ERROR$NC}" | sed -E "s/\| ([^|]+)(ERROR|FATAL|CRITICAL|EXCEPTION|FAIL)/$CYAN| \1$RED\2$NC/g"
        else
            echo "$line"
        fi
    done
fi