#!/bin/bash
################################################################################
# MariaDB Galera Cluster - Emergency Recovery Script
################################################################################
# Purpose: Recover cluster after unclean shutdown (e.g., unexpected reboot)
# Usage: Use when cluster won't start after a crash or forced reboot
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
NODE1_HOST="srv042036"
NODE2_HOST="srv042037"

echo -e "${RED}========================================${NC}"
echo -e "${RED}MariaDB Galera Emergency Recovery${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}⚠ WARNING: This script should only be used after an unclean shutdown${NC}"
echo -e "${YELLOW}⚠ It will determine which node to bootstrap and recover the cluster${NC}"
echo ""
read -p "Continue with emergency recovery? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${RED}Aborting.${NC}"
    exit 1
fi
echo ""

# Determine which node we're on
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" != "$NODE1_HOST" ]]; then
    echo -e "${RED}ERROR: This script must be run on node1 ($NODE1_HOST)${NC}"
    exit 1
fi

echo -e "${BLUE}Step 1: Stopping both nodes...${NC}"
echo -e "${YELLOW}Stopping node1...${NC}"
docker stop "$NODE1_CONTAINER" 2>/dev/null || echo "Node1 already stopped"

echo -e "${YELLOW}Stopping node2 (if accessible)...${NC}"
ssh "$NODE2_HOST" "docker stop $NODE2_CONTAINER" 2>/dev/null || echo "Node2 already stopped or not accessible"
echo -e "${GREEN}✓ Both nodes stopped${NC}"
echo ""

echo -e "${BLUE}Step 2: Checking grastate.dat on both nodes...${NC}"
echo -e "${YELLOW}Node1 grastate.dat:${NC}"
NODE1_GRASTATE=$(docker run --rm -v "$NODE1_VOLUME":/data alpine cat /data/grastate.dat 2>/dev/null)
echo "$NODE1_GRASTATE"
NODE1_SEQNO=$(echo "$NODE1_GRASTATE" | grep "seqno:" | awk '{print $2}')
NODE1_SAFE=$(echo "$NODE1_GRASTATE" | grep "safe_to_bootstrap:" | awk '{print $2}')
echo ""

echo -e "${YELLOW}Node2 grastate.dat:${NC}"
NODE2_GRASTATE=$(ssh "$NODE2_HOST" "docker run --rm -v $NODE2_VOLUME:/data alpine cat /data/grastate.dat" 2>/dev/null)
echo "$NODE2_GRASTATE"
NODE2_SEQNO=$(echo "$NODE2_GRASTATE" | grep "seqno:" | awk '{print $2}')
NODE2_SAFE=$(echo "$NODE2_GRASTATE" | grep "safe_to_bootstrap:" | awk '{print $2}')
echo ""

echo -e "${BLUE}Step 3: Determining bootstrap node...${NC}"
echo -e "Node1 seqno: ${YELLOW}$NODE1_SEQNO${NC}, safe_to_bootstrap: ${YELLOW}$NODE1_SAFE${NC}"
echo -e "Node2 seqno: ${YELLOW}$NODE2_SEQNO${NC}, safe_to_bootstrap: ${YELLOW}$NODE2_SAFE${NC}"
echo ""

# Determine which node to bootstrap
BOOTSTRAP_NODE=""
if [[ "$NODE1_SAFE" == "1" ]]; then
    BOOTSTRAP_NODE="node1"
    echo -e "${GREEN}✓ Node1 is marked safe_to_bootstrap${NC}"
elif [[ "$NODE2_SAFE" == "1" ]]; then
    BOOTSTRAP_NODE="node2"
    echo -e "${GREEN}✓ Node2 is marked safe_to_bootstrap${NC}"
elif [[ "$NODE1_SEQNO" != "-1" ]] && [[ "$NODE2_SEQNO" != "-1" ]]; then
    # Compare seqno values
    if [[ "$NODE1_SEQNO" -ge "$NODE2_SEQNO" ]]; then
        BOOTSTRAP_NODE="node1"
        echo -e "${YELLOW}⚠ Neither node marked safe, but node1 has higher/equal seqno${NC}"
    else
        BOOTSTRAP_NODE="node2"
        echo -e "${YELLOW}⚠ Neither node marked safe, but node2 has higher seqno${NC}"
    fi
else
    # Default to node1 if seqno is -1 on both
    BOOTSTRAP_NODE="node1"
    echo -e "${YELLOW}⚠ Cannot determine from seqno, defaulting to node1${NC}"
fi

echo -e "${GREEN}Decision: Bootstrap from $BOOTSTRAP_NODE${NC}"
echo ""

echo -e "${BLUE}Step 4: Setting safe_to_bootstrap on $BOOTSTRAP_NODE...${NC}"
if [[ "$BOOTSTRAP_NODE" == "node1" ]]; then
    docker run --rm -v "$NODE1_VOLUME":/data alpine \
        sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
    echo -e "${GREEN}✓ Node1 safe_to_bootstrap set to 1${NC}"
else
    ssh "$NODE2_HOST" "docker run --rm -v $NODE2_VOLUME:/data alpine \
        sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat"
    echo -e "${GREEN}✓ Node2 safe_to_bootstrap set to 1${NC}"
fi
echo ""

echo -e "${BLUE}Step 5: Cleaning up stale SST files...${NC}"
echo -e "${YELLOW}Cleaning node1...${NC}"
docker run --rm -v "$NODE1_VOLUME":/data alpine sh -c "
    rm -f /data/rsync_sst.conf
    rm -f /data/rsync_sst.pid
    rm -f /data/sst_in_progress
    rm -f /data/wsrep_sst.pid
    rm -f /data/gvwstate.dat
" 2>/dev/null || true
echo -e "${GREEN}✓ Node1 cleaned${NC}"

echo -e "${YELLOW}Cleaning node2...${NC}"
ssh "$NODE2_HOST" "docker run --rm -v $NODE2_VOLUME:/data alpine sh -c '
    rm -f /data/rsync_sst.conf
    rm -f /data/rsync_sst.pid
    rm -f /data/sst_in_progress
    rm -f /data/wsrep_sst.pid
    rm -f /data/gvwstate.dat
'" 2>/dev/null || true
echo -e "${GREEN}✓ Node2 cleaned${NC}"
echo ""

echo -e "${BLUE}Step 6: Starting bootstrap node...${NC}"
if [[ "$BOOTSTRAP_NODE" == "node1" ]]; then
    echo -e "${YELLOW}Starting node1 with bootstrap...${NC}"
    echo -e "${RED}⚠ IMPORTANT: Ensure --wsrep-new-cluster is in the Portainer stack command!${NC}"
    echo ""
    read -p "Press Enter after confirming --wsrep-new-cluster is in place..."
    docker start "$NODE1_CONTAINER"
    echo -e "${GREEN}✓ Node1 started${NC}"
else
    echo -e "${YELLOW}Starting node2 with bootstrap...${NC}"
    echo -e "${RED}⚠ IMPORTANT: Ensure --wsrep-new-cluster is in the Portainer stack command!${NC}"
    echo ""
    read -p "Press Enter after confirming --wsrep-new-cluster is in place..."
    ssh "$NODE2_HOST" "docker start $NODE2_CONTAINER"
    echo -e "${GREEN}✓ Node2 started${NC}"
fi
echo ""

echo -e "${YELLOW}Waiting 30 seconds for bootstrap node to initialize...${NC}"
sleep 30
echo ""

echo -e "${BLUE}Step 7: Verifying bootstrap node status...${NC}"
if [[ "$BOOTSTRAP_NODE" == "node1" ]]; then
    docker exec "$NODE1_CONTAINER" mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
        SELECT VARIABLE_NAME, VARIABLE_VALUE 
        FROM information_schema.GLOBAL_STATUS 
        WHERE VARIABLE_NAME IN ('wsrep_cluster_status', 'wsrep_ready', 'wsrep_local_state_comment');"
else
    ssh "$NODE2_HOST" "docker exec $NODE2_CONTAINER mariadb -uroot -p'pHIbY#22we@0Y^BB' -e \"
        SELECT VARIABLE_NAME, VARIABLE_VALUE 
        FROM information_schema.GLOBAL_STATUS 
        WHERE VARIABLE_NAME IN ('wsrep_cluster_status', 'wsrep_ready', 'wsrep_local_state_comment');\""
fi
echo ""

echo -e "${BLUE}Step 8: Starting the other node...${NC}"
if [[ "$BOOTSTRAP_NODE" == "node1" ]]; then
    echo -e "${YELLOW}Starting node2 to join the cluster...${NC}"
    ssh "$NODE2_HOST" "docker start $NODE2_CONTAINER"
    echo -e "${GREEN}✓ Node2 started${NC}"
else
    echo -e "${YELLOW}Starting node1 to join the cluster...${NC}"
    docker start "$NODE1_CONTAINER"
    echo -e "${GREEN}✓ Node1 started${NC}"
fi
echo ""

echo -e "${YELLOW}Waiting 30 seconds for node to join...${NC}"
sleep 30
echo ""

echo -e "${BLUE}Step 9: Verifying cluster status...${NC}"
echo -e "${YELLOW}Node1 status:${NC}"
docker exec "$NODE1_CONTAINER" mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
    SELECT VARIABLE_NAME, VARIABLE_VALUE 
    FROM information_schema.GLOBAL_STATUS 
    WHERE VARIABLE_NAME IN ('wsrep_cluster_size', 'wsrep_cluster_status', 'wsrep_ready');" || echo "Node1 not accessible"
echo ""

echo -e "${YELLOW}Node2 status:${NC}"
ssh "$NODE2_HOST" "docker exec $NODE2_CONTAINER mariadb -uroot -p'pHIbY#22we@0Y^BB' -e \"
    SELECT VARIABLE_NAME, VARIABLE_VALUE 
    FROM information_schema.GLOBAL_STATUS 
    WHERE VARIABLE_NAME IN ('wsrep_cluster_size', 'wsrep_cluster_status', 'wsrep_ready');\"" || echo "Node2 not accessible"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Emergency recovery complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Verify both nodes show cluster_size = 2"
echo "2. Verify both nodes show cluster_status = Primary"
echo "3. Verify both nodes show wsrep_ready = ON"
echo "4. Remove --wsrep-new-cluster from bootstrap node's Portainer stack"
echo "5. Redeploy the stack to return to normal operation"
echo ""

