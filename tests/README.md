# MariaDB Galera Cluster Tests

Comprehensive test suite for validating MariaDB Galera cluster health, connectivity, and replication.

## Features

### Node Tests
- ✅ **Connectivity Test**: Verifies basic connection to both nodes
- ✅ **Node Identification**: Validates node names and addresses
- ✅ **Individual Node Health**: Checks each node's status

### Cluster Tests
- ✅ **Cluster Formation**: Verifies both nodes are in the cluster
- ✅ **Synchronization Status**: Ensures nodes are synced
- ✅ **Cluster Configuration**: Validates cluster name and settings

### Replication Tests
- ✅ **Write Replication**: Tests data replication between nodes
- ✅ **Bidirectional Writes**: Verifies writes work on both nodes
- ✅ **Concurrent Operations**: Tests simultaneous writes
- ✅ **Data Consistency**: Ensures data is identical on both nodes

## Quick Start

### Option 1: Use the Test Runner (Recommended)
```bash
cd MariaDB-Galera
./run_tests.sh
```

### Option 2: Manual Setup
```bash
cd MariaDB-Galera

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r tests/requirements.txt

# Run tests
python tests/test_galera_cluster.py
```

### Option 3: Using pytest
```bash
# After setup above
python -m pytest tests/test_galera_cluster.py -v
```

## Configuration

The tests automatically read configuration from `.prd2.env`:

```env
HOST1_IP=10.87.2.22
HOST2_IP=10.87.2.23
MYSQL_USER=dcsautuser
MYSQL_PASSWORD=RH3z4bhEJGnPx8$$q
MYSQL_DATABASE=dcsautomation
MYSQL_ROOT_PASSWORD=pHIbY#22we@0Y^BB
CLUSTER_NAME=dcsautomation_galera_cluster
```

## Test Output

### Successful Run Example:
```
🚀 Starting MariaDB Galera Cluster Tests
==================================================
Testing node connectivity...
✅ Node 1 connectivity: PASS
✅ Node 2 connectivity: PASS
------------------------------
Testing cluster status...
✅ node1 cluster status: PASS
✅ node2 cluster status: PASS
------------------------------
Testing node identification...
Node 1 name: node1
Node 2 name: node2
✅ Node identification: PASS
------------------------------
Testing write replication...
✅ Write replication: PASS
------------------------------
Testing concurrent writes...
✅ Concurrent writes: PASS
------------------------------
==================================================
📊 Test Results: 5 PASSED, 0 FAILED
🎉 All tests PASSED! Cluster is healthy.
```

## Test Details

### 1. Node Connectivity Test
- Connects to both nodes using configured credentials
- Executes simple `SELECT 1` query
- Verifies response

### 2. Cluster Status Test
- Checks `wsrep_cluster_size = 2`
- Verifies `wsrep_local_state_comment = 'Synced'`
- Confirms `wsrep_ready = 'ON'`
- Validates cluster name matches configuration

### 3. Node Identification Test
- Verifies unique node names
- Checks node IP addresses match configuration
- Ensures nodes can be distinguished

### 4. Write Replication Test
- Creates test table on Node 1
- Inserts data on Node 1, verifies on Node 2
- Inserts data on Node 2, verifies on Node 1
- Confirms bidirectional replication
- Cleans up test data

### 5. Concurrent Writes Test
- Performs simultaneous writes to both nodes
- Verifies all data is replicated correctly
- Checks data consistency across nodes
- Tests auto-increment handling

## Troubleshooting

### Connection Errors
```
Failed to connect to node1 (10.87.2.22): (2003, "Can't connect to MySQL server")
```
**Solution**: Verify containers are running and ports are accessible

### Cluster Size Issues
```
node1: Expected cluster size 2, got 1
```
**Solution**: Check if both nodes are running and can communicate

### Replication Failures
```
Data not replicated to Node 2
```
**Solution**: Check cluster sync status and network connectivity

### Environment Issues
```
Error: .prd2.env file not found!
```
**Solution**: Ensure environment file exists with correct configuration

## Dependencies

- **pymysql**: MySQL database connector
- **pytest**: Testing framework
- **python-dotenv**: Environment variable management

## Security Notes

- Tests use both regular user and root credentials
- Passwords are automatically unescaped ($$q → $q)
- Test tables are automatically cleaned up
- No persistent changes are made to the database
