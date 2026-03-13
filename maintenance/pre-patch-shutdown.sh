#!/bin/bash
################################################################################
# MariaDB Galera Cluster - Pre-Patch Graceful Shutdown Script
################################################################################
# Purpose: Gracefully shut down the Galera cluster before server maintenance
# Usage: Run this script on BOTH nodes before patching/rebooting servers
# Author: DCS Automation Team
# Date: 2025-10-21
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables from .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo -e "${RED}ERROR: .env file not found at $ENV_FILE${NC}"
    echo "Please create .env from .env.example in the parent directory."
    exit 1
fi

# Validate required variables
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is not set in .env}"
: "${NODE1_HOST:?NODE1_HOST is not set in .env}"
: "${NODE2_HOST:?NODE2_HOST is not set in .env}"

# Configuration
NODE1_CONTAINER="mariadb-galera-node1"
NODE2_CONTAINER="mariadb-galera-node2"
NODE1_VOLUME="mariadb-galera-node1_mariadb_data"
NODE2_VOLUME="mariadb-galera-node2_mariadb_data"

# Determine which node we're on
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == "$NODE1_HOST" ]]; then
    CURRENT_NODE="node1"
    CONTAINER_NAME="$NODE1_CONTAINER"
    VOLUME_NAME="$NODE1_VOLUME"
elif [[ "$HOSTNAME" == "$NODE2_HOST" ]]; then
    CURRENT_NODE="node2"
    CONTAINER_NAME="$NODE2_CONTAINER"
    VOLUME_NAME="$NODE2_VOLUME"
else
    echo -e "${RED}ERROR: Unknown hostname. This script should run on $NODE1_HOST or $NODE2_HOST${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MariaDB Galera Pre-Patch Shutdown${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Current Node: ${GREEN}$CURRENT_NODE${NC} ($HOSTNAME)"
echo -e "Container: ${GREEN}$CONTAINER_NAME${NC}"
echo ""

# Function to check if container is running
is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^$1$"
}

# Function to get cluster status
get_cluster_status() {
    docker exec "$CONTAINER_NAME" mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
        SELECT VARIABLE_NAME, VARIABLE_VALUE 
        FROM information_schema.GLOBAL_STATUS 
        WHERE VARIABLE_NAME IN (
            'wsrep_cluster_size',
            'wsrep_cluster_status',
            'wsrep_ready',
            'wsrep_local_state_comment'
        );" 2>/dev/null || echo "ERROR"
}

# Step 1: Check if container is running
echo -e "${YELLOW}Step 1: Checking container status...${NC}"
if ! is_container_running "$CONTAINER_NAME"; then
    echo -e "${GREEN}✓ Container is already stopped${NC}"
    exit 0
fi
echo -e "${GREEN}✓ Container is running${NC}"
echo ""

# Step 2: Get current cluster status
echo -e "${YELLOW}Step 2: Getting cluster status...${NC}"
CLUSTER_STATUS=$(get_cluster_status)
if [[ "$CLUSTER_STATUS" == "ERROR" ]]; then
    echo -e "${RED}⚠ Cannot connect to database, but will proceed with shutdown${NC}"
else
    echo "$CLUSTER_STATUS"
fi
echo ""

# Step 3: Graceful shutdown
echo -e "${YELLOW}Step 3: Performing graceful shutdown...${NC}"
if [[ "$CURRENT_NODE" == "node2" ]]; then
    echo -e "${BLUE}This is node2 - shutting down first (recommended order)${NC}"
    docker stop "$CONTAINER_NAME"
    echo -e "${GREEN}✓ Node2 stopped gracefully${NC}"
elif [[ "$CURRENT_NODE" == "node1" ]]; then
    echo -e "${YELLOW}⚠ This is node1 - ensure node2 is stopped first!${NC}"
    read -p "Has node2 been stopped? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${RED}Aborting. Please stop node2 first.${NC}"
        exit 1
    fi
    docker stop "$CONTAINER_NAME"
    echo -e "${GREEN}✓ Node1 stopped gracefully${NC}"
fi
echo ""

# Step 4: Verify grastate.dat
echo -e "${YELLOW}Step 4: Verifying grastate.dat...${NC}"
GRASTATE=$(docker run --rm -v "$VOLUME_NAME":/data alpine cat /data/grastate.dat 2>/dev/null || echo "ERROR")
if [[ "$GRASTATE" == "ERROR" ]]; then
    echo -e "${RED}⚠ Cannot read grastate.dat${NC}"
else
    echo "$GRASTATE"
    if echo "$GRASTATE" | grep -q "safe_to_bootstrap: 1"; then
        echo -e "${GREEN}✓ safe_to_bootstrap is set to 1 (good for recovery)${NC}"
    else
        echo -e "${YELLOW}⚠ safe_to_bootstrap is 0 (may need manual intervention after reboot)${NC}"
    fi
fi
echo ""

# Step 5: Create shutdown timestamp
echo -e "${YELLOW}Step 5: Recording shutdown timestamp...${NC}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "$TIMESTAMP" > "/tmp/galera_shutdown_${CURRENT_NODE}.timestamp"
echo -e "${GREEN}✓ Shutdown timestamp recorded: $TIMESTAMP${NC}"
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Pre-patch shutdown complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Proceed with server patching/maintenance"
echo "2. After reboot, use post-patch-startup.sh to restart the cluster"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "- Node1 should be started first after patching"
echo "- Node2 should be started second"
echo "- Check cluster status after both nodes are up"
echo ""

