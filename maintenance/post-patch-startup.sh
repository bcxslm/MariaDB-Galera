#!/bin/bash
################################################################################
# MariaDB Galera Cluster - Post-Patch Startup Script
################################################################################
# Purpose: Safely restart the Galera cluster after server maintenance
# Usage: Run on node1 first, then on node2
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

# Configuration
NODE1_CONTAINER="mariadb-galera-node1"
NODE2_CONTAINER="mariadb-galera-node2"
NODE1_VOLUME="mariadb-galera-node1_mariadb_data"
NODE2_VOLUME="mariadb-galera-node2_mariadb_data"
MYSQL_ROOT_PASSWORD="pHIbY#22we@0Y^BB"

# Determine which node we're on
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == "srv042036" ]]; then
    CURRENT_NODE="node1"
    CONTAINER_NAME="$NODE1_CONTAINER"
    VOLUME_NAME="$NODE1_VOLUME"
    OTHER_NODE="node2"
elif [[ "$HOSTNAME" == "srv042037" ]]; then
    CURRENT_NODE="node2"
    CONTAINER_NAME="$NODE2_CONTAINER"
    VOLUME_NAME="$NODE2_VOLUME"
    OTHER_NODE="node1"
else
    echo -e "${RED}ERROR: Unknown hostname. This script should run on srv042036 or srv042037${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MariaDB Galera Post-Patch Startup${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Current Node: ${GREEN}$CURRENT_NODE${NC} ($HOSTNAME)"
echo -e "Container: ${GREEN}$CONTAINER_NAME${NC}"
echo ""

# Function to check if container is running
is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^$1$"
}

# Function to wait for database to be ready
wait_for_database() {
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}Waiting for database to be ready...${NC}"
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$CONTAINER_NAME" mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
            echo -e "${GREEN}✓ Database is ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo -e "${RED}✗ Database did not become ready in time${NC}"
    return 1
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
        );" 2>/dev/null
}

# Step 1: Check current status
echo -e "${YELLOW}Step 1: Checking current status...${NC}"
if is_container_running "$CONTAINER_NAME"; then
    echo -e "${GREEN}✓ Container is already running${NC}"
    ALREADY_RUNNING=true
else
    echo -e "${YELLOW}Container is stopped${NC}"
    ALREADY_RUNNING=false
fi
echo ""

# Step 2: Check grastate.dat
echo -e "${YELLOW}Step 2: Checking grastate.dat...${NC}"
GRASTATE=$(docker run --rm -v "$VOLUME_NAME":/data alpine cat /data/grastate.dat 2>/dev/null || echo "ERROR")
if [[ "$GRASTATE" == "ERROR" ]]; then
    echo -e "${RED}⚠ Cannot read grastate.dat${NC}"
else
    echo "$GRASTATE"
    SAFE_TO_BOOTSTRAP=$(echo "$GRASTATE" | grep "safe_to_bootstrap:" | awk '{print $2}')
    echo ""
    if [[ "$SAFE_TO_BOOTSTRAP" == "0" ]]; then
        echo -e "${YELLOW}⚠ safe_to_bootstrap is 0${NC}"
        if [[ "$CURRENT_NODE" == "node1" ]]; then
            echo -e "${YELLOW}Setting safe_to_bootstrap to 1 for node1...${NC}"
            docker run --rm -v "$VOLUME_NAME":/data alpine \
                sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
            echo -e "${GREEN}✓ safe_to_bootstrap set to 1${NC}"
        else
            echo -e "${YELLOW}⚠ Node2 should not bootstrap. Ensure node1 is started first!${NC}"
        fi
    else
        echo -e "${GREEN}✓ safe_to_bootstrap is already 1${NC}"
    fi
fi
echo ""

# Step 3: Start the container
if [[ "$ALREADY_RUNNING" == false ]]; then
    echo -e "${YELLOW}Step 3: Starting container...${NC}"
    
    if [[ "$CURRENT_NODE" == "node1" ]]; then
        echo -e "${BLUE}Starting node1 (bootstrap node)...${NC}"
        docker start "$CONTAINER_NAME"
    else
        echo -e "${BLUE}Starting node2 (joining node)...${NC}"
        echo -e "${YELLOW}⚠ Ensure node1 is already running and in PRIMARY state!${NC}"
        read -p "Is node1 running and PRIMARY? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo -e "${RED}Aborting. Please start node1 first.${NC}"
            exit 1
        fi
        docker start "$CONTAINER_NAME"
    fi
    
    echo -e "${GREEN}✓ Container started${NC}"
    echo ""
else
    echo -e "${YELLOW}Step 3: Container already running, skipping start${NC}"
    echo ""
fi

# Step 4: Wait for database to be ready
echo -e "${YELLOW}Step 4: Waiting for database...${NC}"
if ! wait_for_database; then
    echo -e "${RED}ERROR: Database failed to start properly${NC}"
    echo -e "${YELLOW}Check logs with: docker logs $CONTAINER_NAME${NC}"
    exit 1
fi
echo ""

# Step 5: Check cluster status
echo -e "${YELLOW}Step 5: Checking cluster status...${NC}"
sleep 5  # Give Galera a moment to initialize
CLUSTER_STATUS=$(get_cluster_status)
echo "$CLUSTER_STATUS"
echo ""

# Parse status
CLUSTER_SIZE=$(echo "$CLUSTER_STATUS" | grep wsrep_cluster_size | awk '{print $2}')
CLUSTER_STATUS_VAL=$(echo "$CLUSTER_STATUS" | grep wsrep_cluster_status | awk '{print $2}')
WSREP_READY=$(echo "$CLUSTER_STATUS" | grep wsrep_ready | awk '{print $2}')
LOCAL_STATE=$(echo "$CLUSTER_STATUS" | grep wsrep_local_state_comment | awk '{print $2}')

# Evaluate status
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cluster Status Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Cluster Size: ${GREEN}$CLUSTER_SIZE${NC}"
echo -e "Cluster Status: ${GREEN}$CLUSTER_STATUS_VAL${NC}"
echo -e "WSREP Ready: ${GREEN}$WSREP_READY${NC}"
echo -e "Local State: ${GREEN}$LOCAL_STATE${NC}"
echo ""

if [[ "$WSREP_READY" == "ON" ]] && [[ "$CLUSTER_STATUS_VAL" == "Primary" ]]; then
    echo -e "${GREEN}✓ Node is healthy and in PRIMARY state!${NC}"
    
    if [[ "$CURRENT_NODE" == "node1" ]] && [[ "$CLUSTER_SIZE" == "1" ]]; then
        echo -e "${YELLOW}⚠ Node1 is running alone. Start node2 next.${NC}"
    elif [[ "$CLUSTER_SIZE" == "2" ]]; then
        echo -e "${GREEN}✓ Both nodes are in the cluster!${NC}"
    fi
else
    echo -e "${RED}⚠ Node is not in optimal state${NC}"
    echo -e "${YELLOW}Check logs with: docker logs $CONTAINER_NAME${NC}"
fi
echo ""

# Step 6: Record startup timestamp
echo -e "${YELLOW}Step 6: Recording startup timestamp...${NC}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "$TIMESTAMP" > "/tmp/galera_startup_${CURRENT_NODE}.timestamp"
echo -e "${GREEN}✓ Startup timestamp recorded: $TIMESTAMP${NC}"
echo ""

# Final instructions
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Post-patch startup complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [[ "$CURRENT_NODE" == "node1" ]] && [[ "$CLUSTER_SIZE" == "1" ]]; then
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Run this script on node2 (srv042037)"
    echo "2. Verify both nodes show cluster_size = 2"
    echo "3. Test database connectivity"
elif [[ "$CURRENT_NODE" == "node2" ]]; then
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Verify cluster_size = 2 on both nodes"
    echo "2. Test database connectivity"
    echo "3. Monitor logs for any issues"
fi
echo ""

