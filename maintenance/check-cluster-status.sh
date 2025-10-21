#!/bin/bash
################################################################################
# MariaDB Galera Cluster - Status Checker
################################################################################
# Purpose: Quick health check for the Galera cluster
# Usage: Run on either node to check cluster status
# Author: DCS Automation Team
# Date: 2025-10-21
################################################################################

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
NODE1_HOST="srv042036"
NODE2_HOST="srv042037"

# Determine which node we're on
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == "$NODE1_HOST" ]]; then
    CURRENT_NODE="node1"
    LOCAL_CONTAINER="$NODE1_CONTAINER"
    LOCAL_VOLUME="$NODE1_VOLUME"
    REMOTE_CONTAINER="$NODE2_CONTAINER"
    REMOTE_VOLUME="$NODE2_VOLUME"
    REMOTE_HOST="$NODE2_HOST"
elif [[ "$HOSTNAME" == "$NODE2_HOST" ]]; then
    CURRENT_NODE="node2"
    LOCAL_CONTAINER="$NODE2_CONTAINER"
    LOCAL_VOLUME="$NODE2_VOLUME"
    REMOTE_CONTAINER="$NODE1_CONTAINER"
    REMOTE_VOLUME="$NODE1_VOLUME"
    REMOTE_HOST="$NODE1_HOST"
else
    echo -e "${RED}ERROR: Unknown hostname. This script should run on $NODE1_HOST or $NODE2_HOST${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MariaDB Galera Cluster Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Running on: ${GREEN}$CURRENT_NODE${NC} ($HOSTNAME)"
echo -e "Timestamp: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# Function to check if container is running
is_container_running() {
    docker ps --format '{{.Names}}' | grep -q "^$1$"
}

# Check local container
echo -e "${YELLOW}Local Node ($CURRENT_NODE):${NC}"
if is_container_running "$LOCAL_CONTAINER"; then
    echo -e "  Container: ${GREEN}Running${NC}"
    
    # Get cluster status
    STATUS=$(docker exec "$LOCAL_CONTAINER" mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "
        SELECT VARIABLE_NAME, VARIABLE_VALUE 
        FROM information_schema.GLOBAL_STATUS 
        WHERE VARIABLE_NAME IN (
            'wsrep_cluster_size',
            'wsrep_cluster_status',
            'wsrep_ready',
            'wsrep_local_state_comment',
            'wsrep_connected'
        );" 2>/dev/null)
    
    if [[ -n "$STATUS" ]]; then
        CLUSTER_SIZE=$(echo "$STATUS" | grep wsrep_cluster_size | awk '{print $2}')
        CLUSTER_STATUS=$(echo "$STATUS" | grep wsrep_cluster_status | awk '{print $2}')
        WSREP_READY=$(echo "$STATUS" | grep wsrep_ready | awk '{print $2}')
        LOCAL_STATE=$(echo "$STATUS" | grep wsrep_local_state_comment | awk '{print $2}')
        CONNECTED=$(echo "$STATUS" | grep wsrep_connected | awk '{print $2}')
        
        # Color code the status
        if [[ "$CLUSTER_STATUS" == "Primary" ]]; then
            CLUSTER_STATUS_COLOR="${GREEN}$CLUSTER_STATUS${NC}"
        else
            CLUSTER_STATUS_COLOR="${RED}$CLUSTER_STATUS${NC}"
        fi
        
        if [[ "$WSREP_READY" == "ON" ]]; then
            WSREP_READY_COLOR="${GREEN}$WSREP_READY${NC}"
        else
            WSREP_READY_COLOR="${RED}$WSREP_READY${NC}"
        fi
        
        if [[ "$LOCAL_STATE" == "Synced" ]]; then
            LOCAL_STATE_COLOR="${GREEN}$LOCAL_STATE${NC}"
        else
            LOCAL_STATE_COLOR="${YELLOW}$LOCAL_STATE${NC}"
        fi
        
        if [[ "$CONNECTED" == "ON" ]]; then
            CONNECTED_COLOR="${GREEN}$CONNECTED${NC}"
        else
            CONNECTED_COLOR="${RED}$CONNECTED${NC}"
        fi
        
        echo -e "  Cluster Size: ${GREEN}$CLUSTER_SIZE${NC}"
        echo -e "  Cluster Status: $CLUSTER_STATUS_COLOR"
        echo -e "  WSREP Ready: $WSREP_READY_COLOR"
        echo -e "  Local State: $LOCAL_STATE_COLOR"
        echo -e "  Connected: $CONNECTED_COLOR"
        
        # Overall health assessment
        if [[ "$WSREP_READY" == "ON" ]] && [[ "$CLUSTER_STATUS" == "Primary" ]] && [[ "$LOCAL_STATE" == "Synced" ]]; then
            echo -e "  Overall: ${GREEN}✓ Healthy${NC}"
        else
            echo -e "  Overall: ${RED}✗ Unhealthy${NC}"
        fi
    else
        echo -e "  Database: ${RED}Not accessible${NC}"
    fi
else
    echo -e "  Container: ${RED}Stopped${NC}"
fi
echo ""

# Check remote container (if accessible)
echo -e "${YELLOW}Remote Node ($REMOTE_HOST):${NC}"
REMOTE_CHECK=$(ssh -o ConnectTimeout=5 "$REMOTE_HOST" "docker ps --format '{{.Names}}' | grep -q '^$REMOTE_CONTAINER$' && echo 'running' || echo 'stopped'" 2>/dev/null)

if [[ "$REMOTE_CHECK" == "running" ]]; then
    echo -e "  Container: ${GREEN}Running${NC}"
    
    # Get remote cluster status
    REMOTE_STATUS=$(ssh "$REMOTE_HOST" "docker exec $REMOTE_CONTAINER mariadb -uroot -p'$MYSQL_ROOT_PASSWORD' -e \"
        SELECT VARIABLE_NAME, VARIABLE_VALUE 
        FROM information_schema.GLOBAL_STATUS 
        WHERE VARIABLE_NAME IN (
            'wsrep_cluster_size',
            'wsrep_cluster_status',
            'wsrep_ready',
            'wsrep_local_state_comment',
            'wsrep_connected'
        );\"" 2>/dev/null)
    
    if [[ -n "$REMOTE_STATUS" ]]; then
        REMOTE_CLUSTER_SIZE=$(echo "$REMOTE_STATUS" | grep wsrep_cluster_size | awk '{print $2}')
        REMOTE_CLUSTER_STATUS=$(echo "$REMOTE_STATUS" | grep wsrep_cluster_status | awk '{print $2}')
        REMOTE_WSREP_READY=$(echo "$REMOTE_STATUS" | grep wsrep_ready | awk '{print $2}')
        REMOTE_LOCAL_STATE=$(echo "$REMOTE_STATUS" | grep wsrep_local_state_comment | awk '{print $2}')
        REMOTE_CONNECTED=$(echo "$REMOTE_STATUS" | grep wsrep_connected | awk '{print $2}')
        
        # Color code the status
        if [[ "$REMOTE_CLUSTER_STATUS" == "Primary" ]]; then
            REMOTE_CLUSTER_STATUS_COLOR="${GREEN}$REMOTE_CLUSTER_STATUS${NC}"
        else
            REMOTE_CLUSTER_STATUS_COLOR="${RED}$REMOTE_CLUSTER_STATUS${NC}"
        fi
        
        if [[ "$REMOTE_WSREP_READY" == "ON" ]]; then
            REMOTE_WSREP_READY_COLOR="${GREEN}$REMOTE_WSREP_READY${NC}"
        else
            REMOTE_WSREP_READY_COLOR="${RED}$REMOTE_WSREP_READY${NC}"
        fi
        
        if [[ "$REMOTE_LOCAL_STATE" == "Synced" ]]; then
            REMOTE_LOCAL_STATE_COLOR="${GREEN}$REMOTE_LOCAL_STATE${NC}"
        else
            REMOTE_LOCAL_STATE_COLOR="${YELLOW}$REMOTE_LOCAL_STATE${NC}"
        fi
        
        if [[ "$REMOTE_CONNECTED" == "ON" ]]; then
            REMOTE_CONNECTED_COLOR="${GREEN}$REMOTE_CONNECTED${NC}"
        else
            REMOTE_CONNECTED_COLOR="${RED}$REMOTE_CONNECTED${NC}"
        fi
        
        echo -e "  Cluster Size: ${GREEN}$REMOTE_CLUSTER_SIZE${NC}"
        echo -e "  Cluster Status: $REMOTE_CLUSTER_STATUS_COLOR"
        echo -e "  WSREP Ready: $REMOTE_WSREP_READY_COLOR"
        echo -e "  Local State: $REMOTE_LOCAL_STATE_COLOR"
        echo -e "  Connected: $REMOTE_CONNECTED_COLOR"
        
        # Overall health assessment
        if [[ "$REMOTE_WSREP_READY" == "ON" ]] && [[ "$REMOTE_CLUSTER_STATUS" == "Primary" ]] && [[ "$REMOTE_LOCAL_STATE" == "Synced" ]]; then
            echo -e "  Overall: ${GREEN}✓ Healthy${NC}"
        else
            echo -e "  Overall: ${RED}✗ Unhealthy${NC}"
        fi
    else
        echo -e "  Database: ${RED}Not accessible${NC}"
    fi
elif [[ "$REMOTE_CHECK" == "stopped" ]]; then
    echo -e "  Container: ${RED}Stopped${NC}"
else
    echo -e "  ${YELLOW}Cannot connect to remote host${NC}"
fi
echo ""

# Check grastate.dat on local node
echo -e "${YELLOW}Local grastate.dat:${NC}"
GRASTATE=$(docker run --rm -v "$LOCAL_VOLUME":/data alpine cat /data/grastate.dat 2>/dev/null)
if [[ -n "$GRASTATE" ]]; then
    SEQNO=$(echo "$GRASTATE" | grep "seqno:" | awk '{print $2}')
    SAFE_TO_BOOTSTRAP=$(echo "$GRASTATE" | grep "safe_to_bootstrap:" | awk '{print $2}')
    
    echo -e "  seqno: ${GREEN}$SEQNO${NC}"
    if [[ "$SAFE_TO_BOOTSTRAP" == "1" ]]; then
        echo -e "  safe_to_bootstrap: ${GREEN}$SAFE_TO_BOOTSTRAP${NC}"
    else
        echo -e "  safe_to_bootstrap: ${YELLOW}$SAFE_TO_BOOTSTRAP${NC}"
    fi
else
    echo -e "  ${RED}Cannot read grastate.dat${NC}"
fi
echo ""

# Overall cluster assessment
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Overall Cluster Assessment${NC}"
echo -e "${BLUE}========================================${NC}"

if [[ "$CLUSTER_SIZE" == "2" ]] && [[ "$WSREP_READY" == "ON" ]] && [[ "$CLUSTER_STATUS" == "Primary" ]]; then
    echo -e "${GREEN}✓ Cluster is healthy!${NC}"
    echo -e "  - Both nodes are connected"
    echo -e "  - Cluster is in PRIMARY state"
    echo -e "  - WSREP is ready"
elif [[ "$CLUSTER_SIZE" == "1" ]] && [[ "$WSREP_READY" == "ON" ]] && [[ "$CLUSTER_STATUS" == "Primary" ]]; then
    echo -e "${YELLOW}⚠ Cluster is running with only one node${NC}"
    echo -e "  - Check if the other node is down"
    echo -e "  - Start the other node to restore redundancy"
else
    echo -e "${RED}✗ Cluster has issues${NC}"
    echo -e "  - Check logs: docker logs $LOCAL_CONTAINER"
    echo -e "  - Review maintenance/README.md for troubleshooting"
fi
echo ""

