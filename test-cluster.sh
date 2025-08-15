#!/bin/bash

# MariaDB Galera Cluster Test Script
# This script tests the cluster functionality and replication

set -e

echo "=== MariaDB Galera Cluster Test ==="
echo

# Configuration
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-rootpassword123}
NODE1_CONTAINER="mariadb-galera-node1"
NODE2_CONTAINER="mariadb-galera-node2"

# Function to execute SQL on a node
execute_sql() {
    local container=$1
    local sql=$2
    docker exec -i "$container" mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "$sql" 2>/dev/null
}

# Function to check if container is running
check_container() {
    local container=$1
    if ! docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
        echo "❌ Container $container is not running"
        return 1
    fi
    echo "✅ Container $container is running"
    return 0
}

echo "1. Checking container status..."
check_container "$NODE1_CONTAINER" || exit 1
check_container "$NODE2_CONTAINER" || exit 1

echo
echo "2. Checking cluster status..."

# Check cluster size
echo "Checking cluster size on Node 1:"
CLUSTER_SIZE=$(execute_sql "$NODE1_CONTAINER" "SHOW STATUS LIKE 'wsrep_cluster_size';" | tail -n 1 | awk '{print $2}')
echo "Cluster size: $CLUSTER_SIZE"

if [ "$CLUSTER_SIZE" != "2" ]; then
    echo "❌ Expected cluster size 2, got $CLUSTER_SIZE"
    echo "Cluster may not be properly formed"
else
    echo "✅ Cluster size is correct (2 nodes)"
fi

# Check node status
echo
echo "Checking node status:"
NODE1_STATE=$(execute_sql "$NODE1_CONTAINER" "SHOW STATUS LIKE 'wsrep_local_state_comment';" | tail -n 1 | awk '{print $2}')
NODE2_STATE=$(execute_sql "$NODE2_CONTAINER" "SHOW STATUS LIKE 'wsrep_local_state_comment';" | tail -n 1 | awk '{print $2}')

echo "Node 1 state: $NODE1_STATE"
echo "Node 2 state: $NODE2_STATE"

if [ "$NODE1_STATE" = "Synced" ] && [ "$NODE2_STATE" = "Synced" ]; then
    echo "✅ Both nodes are synced"
else
    echo "❌ Nodes are not properly synced"
fi

echo
echo "3. Testing replication..."

# Insert test data on Node1
echo "Inserting test data on Node1..."
TEST_MESSAGE="Test from Node1 at $(date)"
execute_sql "$NODE1_CONTAINER" "USE testdb; INSERT INTO cluster_test (node_name, message) VALUES ('node1', '$TEST_MESSAGE');"

# Wait a moment for replication
sleep 2

# Check if data appears on Node2
echo "Checking if data replicated to Node2..."
REPLICATED_DATA=$(execute_sql "$NODE2_CONTAINER" "USE testdb; SELECT message FROM cluster_test WHERE message = '$TEST_MESSAGE';" | tail -n 1)

if [ "$REPLICATED_DATA" = "$TEST_MESSAGE" ]; then
    echo "✅ Data successfully replicated from Node1 to Node2"
else
    echo "❌ Data replication failed"
fi

# Insert test data on Node2
echo
echo "Inserting test data on Node2..."
TEST_MESSAGE2="Test from Node2 at $(date)"
execute_sql "$NODE2_CONTAINER" "USE testdb; INSERT INTO cluster_test (node_name, message) VALUES ('node2', '$TEST_MESSAGE2');"

# Wait a moment for replication
sleep 2

# Check if data appears on Node1
echo "Checking if data replicated to Node1..."
REPLICATED_DATA2=$(execute_sql "$NODE1_CONTAINER" "USE testdb; SELECT message FROM cluster_test WHERE message = '$TEST_MESSAGE2';" | tail -n 1)

if [ "$REPLICATED_DATA2" = "$TEST_MESSAGE2" ]; then
    echo "✅ Data successfully replicated from Node2 to Node1"
else
    echo "❌ Data replication failed"
fi

echo
echo "4. Cluster information summary:"
echo "Cluster members:"
execute_sql "$NODE1_CONTAINER" "SHOW STATUS LIKE 'wsrep_incoming_addresses';" | tail -n 1

echo
echo "Node 1 UUID:"
execute_sql "$NODE1_CONTAINER" "SHOW STATUS LIKE 'wsrep_local_uuid';" | tail -n 1

echo
echo "Node 2 UUID:"
execute_sql "$NODE2_CONTAINER" "SHOW STATUS LIKE 'wsrep_local_uuid';" | tail -n 1

echo
echo "5. Performance metrics:"
echo "Node 1 - Transactions committed:"
execute_sql "$NODE1_CONTAINER" "SHOW STATUS LIKE 'wsrep_replicated';" | tail -n 1

echo "Node 2 - Transactions committed:"
execute_sql "$NODE2_CONTAINER" "SHOW STATUS LIKE 'wsrep_replicated';" | tail -n 1

echo
echo "=== Test Complete ==="
echo "If all checks show ✅, your Galera cluster is working correctly!"
