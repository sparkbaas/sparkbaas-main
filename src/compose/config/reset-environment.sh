#!/bin/bash
#
# SparkBaaS Environment Reset Script
# ----------------------------------
# Safely resets the SparkBaaS environment for fresh installation testing
# - Removes docker containers, volumes, and networks related to SparkBaaS
# - Backs up and removes .env file
# - Clears persistent data directories
#

set -eo pipefail

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
COMPOSE_DIR="$PROJECT_ROOT"
DATA_DIR="$COMPOSE_DIR/data"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
FORCE=0

# Display help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "SparkBaaS Environment Reset - Safely resets the SparkBaaS environment for testing"
    echo
    echo "Options:"
    echo "  -h, --help     Display this help message and exit"
    echo "  -y, --force    Skip confirmation prompt and force reset"
    echo
    echo "Examples:"
    echo "  $0             # Interactive reset with confirmation"
    echo "  $0 --force     # Force reset without confirmation"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--force)
            FORCE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Print banner
echo -e "${BLUE}"
echo "┌─────────────────────────────────────────────┐"
echo "│                                             │"
echo "│         SparkBaaS Environment Reset         │"
echo "│                                             │"
echo "└─────────────────────────────────────────────┘"
echo -e "${NC}"

# Ask for confirmation unless force flag is set
if [ $FORCE -eq 0 ]; then
    echo -e "${YELLOW}WARNING: This will remove all SparkBaaS containers, volumes, and data.${NC}"
    echo -e "This is designed for testing fresh installations and should NOT be used in production."
    echo -e "All data will be lost. Environment variables will be backed up."
    echo
    read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Reset canceled."
        exit 0
    fi
else
    echo -e "${YELLOW}Forcing environment reset. All data will be removed.${NC}"
fi

echo
echo -e "${BLUE}Starting environment reset...${NC}"
echo

# Function to check if Docker is running
check_docker() {
    if ! docker info &>/dev/null; then
        echo -e "${RED}Error: Docker is not running.${NC}"
        echo "Please start Docker and try again."
        exit 1
    fi
}

# Backup .env file if it exists
backup_env_file() {
    if [ -f "$ENV_FILE" ]; then
        BACKUP_FILE="$ENV_FILE.backup-$(date +%Y%m%d%H%M%S)"
        echo -e "${YELLOW}Backing up .env file to:${NC} $BACKUP_FILE"
        cp "$ENV_FILE" "$BACKUP_FILE"
        echo -e "${YELLOW}Removing .env file${NC}"
        rm -f "$ENV_FILE"
    else
        echo "No .env file found. Skipping backup."
    fi
}

# Stop and remove containers
remove_containers() {
    echo -e "${BLUE}Stopping and removing SparkBaaS containers...${NC}"
    cd "$COMPOSE_DIR" || exit 1
    
    if [ -f docker-compose.yml ]; then
        docker compose down --remove-orphans 2>/dev/null || true
        echo -e "${GREEN}Containers stopped and removed.${NC}"
    else
        echo "No docker-compose.yml file found. Skipping container removal."
    fi
    
    # Check for any remaining containers with sparkbaas in their name
    REMAINING=$(docker ps -a --filter "name=sparkbaas" --format "{{.Names}}" 2>/dev/null)
    if [ -n "$REMAINING" ]; then
        echo -e "${YELLOW}Removing any remaining SparkBaaS containers...${NC}"
        docker rm -f $(docker ps -a --filter "name=sparkbaas" -q) 2>/dev/null || true
    fi
}

# Remove docker volumes
remove_volumes() {
    echo -e "${BLUE}Removing SparkBaaS Docker volumes...${NC}"
    
    # Remove named volumes created by docker-compose
    VOLUMES=$(docker volume ls --filter "name=sparkbaas" -q 2>/dev/null)
    if [ -n "$VOLUMES" ]; then
        docker volume rm $VOLUMES 2>/dev/null || true
        echo -e "${GREEN}Docker volumes removed.${NC}"
    else
        echo "No SparkBaaS Docker volumes found."
    fi
}

# Remove docker networks
remove_networks() {
    echo -e "${BLUE}Removing SparkBaaS Docker networks...${NC}"
    
    # Remove networks created by docker-compose
    NETWORKS=$(docker network ls --filter "name=sparkbaas" --format "{{.Name}}" 2>/dev/null)
    if [ -n "$NETWORKS" ]; then
        for network in $NETWORKS; do
            docker network rm $network 2>/dev/null || true
        done
        echo -e "${GREEN}Docker networks removed.${NC}"
    else
        echo "No SparkBaaS Docker networks found."
    fi
}

# Check if sudo is available
has_sudo() {
    command -v sudo &> /dev/null
}

# Clear persistent data directories with permission handling
clear_data_directories() {
    echo -e "${BLUE}Clearing persistent data directories...${NC}"
    
    # Function to safely remove directory contents
    safe_remove_dir_contents() {
        local dir=$1
        if [ ! -d "$dir" ]; then
            return
        fi
        
        echo "Clearing directory: $dir"
        
        # Try standard removal first
        rm -rf "$dir"/* 2>/dev/null || {
            # If that fails, try with sudo if available
            if has_sudo; then
                echo -e "${YELLOW}Regular removal failed. Trying with sudo...${NC}"
                sudo rm -rf "$dir"/* || {
                    echo -e "${RED}Error: Failed to clear $dir even with sudo.${NC}"
                    echo "Please manually remove the contents of this directory."
                }
            else
                echo -e "${RED}Error: Cannot remove files in $dir.${NC}"
                echo "Please manually remove the contents of this directory."
            fi
        }
    }
    
    # Clear each data directory
    safe_remove_dir_contents "$DATA_DIR/postgres"
    safe_remove_dir_contents "$DATA_DIR/keycloak"
    safe_remove_dir_contents "$DATA_DIR/kong"

    # Recreate empty directories with proper permissions
    mkdir -p "$DATA_DIR/postgres" "$DATA_DIR/keycloak" "$DATA_DIR/kong"
    
    # Try to set permissions
    chmod -R 777 "$DATA_DIR" 2>/dev/null || {
        if has_sudo; then
            echo -e "${YELLOW}Setting permissions with sudo...${NC}"
            sudo chmod -R 777 "$DATA_DIR" || {
                echo -e "${RED}Warning: Failed to set permissions on data directories.${NC}"
                echo "Docker might have trouble writing to these directories."
            }
        else
            echo -e "${RED}Warning: Failed to set permissions on data directories.${NC}"
            echo "Docker might have trouble writing to these directories."
        fi
    }
    
    echo -e "${GREEN}Data directories cleared and recreated.${NC}"
}

# Main execution
check_docker
backup_env_file
remove_containers
remove_volumes
remove_networks
clear_data_directories

echo
echo -e "${GREEN}Environment reset complete!${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Generate a new environment file: ${YELLOW}./config/generate-env.sh${NC}"
echo -e "2. Start the stack: ${YELLOW}cd $COMPOSE_DIR && source ./.env && docker compose up -d${NC}"
echo