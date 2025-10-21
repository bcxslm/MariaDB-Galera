# MariaDB Galera Cluster Recovery Guide

## Overview

This guide covers how to recover your MariaDB Galera cluster after an unclean shutdown (e.g., server reboots, power loss).

## Bootstrap Configuration

Bootstrap mode is controlled via environment variables in the `.prd1.env` and `.prd2.env` files:

```bash
# Bootstrap Configuration (set to 'yes' only for disaster recovery)
BOOTSTRAP_NODE1=no
BOOTSTRAP_NODE2=no
```

**Normal Operation:** Both set to `no`
**Disaster Recovery:** Set ONE node to `yes` (usually node1)

This is much simpler than maintaining separate docker-compose files!

## Recovery Procedure After Unclean Shutdown

### Step 1: Assess the Situation

Check if any nodes are still running:

```bash
# On each server
docker ps | grep mariadb
```

If at least one node is running, skip to **Step 5** (join remaining nodes).

### Step 2: Determine Which Node to Bootstrap

On each server, check the `grastate.dat` file:

```bash
# On node1 (10.87.2.22)
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat

# On node2 (10.87.2.23)
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine cat /data/grastate.dat
```

Look for the `seqno` value:
- **Highest seqno** = Most recent data, bootstrap this node
- **seqno: -1** = Unclean shutdown, check `gvwstate.dat`
- **Empty file or missing** = Unclean shutdown

If both have `seqno: -1` or empty files, check for `gvwstate.dat`:

```bash
# On node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/gvwstate.dat

# On node2
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine cat /data/gvwstate.dat
```

**Decision tree:**
1. If one node has higher seqno → Bootstrap that node
2. If both have seqno: -1 → Check gvwstate.dat, bootstrap the one with it
3. If neither has gvwstate.dat → Bootstrap node1 (primary node)

### Step 3: Set safe_to_bootstrap Flag

On the node you've chosen to bootstrap (let's assume node1):

```bash
# Stop the container if running
docker stop mariadb-galera-node1

# Check current grastate.dat
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat

# Set safe_to_bootstrap to 1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat

# Verify the change
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat
```

You should see:
```
safe_to_bootstrap: 1
```

### Step 4: Bootstrap the First Node

On the bootstrap node (node1 in this example):

```bash
cd /path/to/mariadb-galera

# Edit .prd1.env and set BOOTSTRAP_NODE1=yes
sed -i 's/BOOTSTRAP_NODE1=no/BOOTSTRAP_NODE1=yes/' .prd1.env

# Start with bootstrap enabled
docker compose --env-file .prd1.env -f docker-compose-host1.yml up -d

# Watch the logs
docker logs -f mariadb-galera-node1
```

Wait for these messages:
- ✅ `WSREP: Synchronized with group, ready for connections`
- ✅ `ready for connections`

Verify cluster status:
```bash
docker exec mariadb-galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

Should show: `wsrep_cluster_size = 1`

### Step 5: Join Remaining Nodes

Once the bootstrap node is running, start the other nodes (BOOTSTRAP_NODE2 should already be 'no'):

```bash
# On node2 (10.87.2.23)
cd /path/to/mariadb-galera

# Verify BOOTSTRAP_NODE2=no in .prd2.env
grep BOOTSTRAP_NODE2 .prd2.env

# Start node2 (it will join the cluster)
docker compose --env-file .prd2.env -f docker-compose-host2.yml up -d

# Watch the logs
docker logs -f mariadb-galera-node2
```

Node2 should automatically join the cluster via SST (State Snapshot Transfer).

### Step 6: Verify Cluster Health

On any node:

```bash
docker exec mariadb-galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_ready';
SHOW STATUS LIKE 'wsrep_connected';
SHOW STATUS LIKE 'wsrep_local_state_comment';
"
```

Expected output:
```
wsrep_cluster_size = 2
wsrep_ready = ON
wsrep_connected = ON
wsrep_local_state_comment = Synced
```

### Step 7: Switch Bootstrap Node Back to Normal Mode

**IMPORTANT:** After recovery, switch the bootstrap node back to normal mode:

```bash
# On node1 (the bootstrap node)
docker stop mariadb-galera-node1

# Set BOOTSTRAP_NODE1 back to 'no'
sed -i 's/BOOTSTRAP_NODE1=yes/BOOTSTRAP_NODE1=no/' .prd1.env

# Restart with normal mode
docker compose --env-file .prd1.env -f docker-compose-host1.yml up -d

# Verify it rejoins the cluster
docker logs -f mariadb-galera-node1
```

The cluster should remain operational during this switch since node2 is already running.

### Step 8: Clean Up SST Markers (Optional)

If you see `sst_in_progress` or `wsrep_sst.pid` files, clean them up:

```bash
# On each node
docker exec mariadb-galera-node1 rm -f /var/lib/mysql/sst_in_progress /var/lib/mysql/wsrep_sst.pid
docker exec mariadb-galera-node2 rm -f /var/lib/mysql/sst_in_progress /var/lib/mysql/wsrep_sst.pid
```

## Graceful Shutdown Procedure

To avoid recovery issues, always shut down gracefully:

```bash
# Stop nodes in reverse order (node2 first, node1 last)
# On node2
docker stop mariadb-galera-node2

# Wait 10 seconds
sleep 10

# On node1
docker stop mariadb-galera-node1
```

This ensures node1 is marked as `safe_to_bootstrap: 1` automatically.

## Common Issues

### Issue: "It may not be safe to bootstrap"
**Solution:** Follow Step 3 to set `safe_to_bootstrap: 1`

### Issue: Node won't join cluster (stuck in SST)
**Solution:** 
1. Check SST user credentials in environment variables
2. Verify network connectivity between nodes (ports 4567, 4568, 4444)
3. Check logs for specific errors
4. Remove SST markers and restart

### Issue: Split-brain scenario
**Solution:**
1. Stop ALL nodes
2. Determine which node has most recent data (highest seqno)
3. Bootstrap that node only
4. Join other nodes one by one

### Issue: Both nodes have seqno: -1
**Solution:**
1. Check `gvwstate.dat` on both nodes
2. Bootstrap the node that has this file
3. If neither has it, bootstrap node1 (primary)

## Quick Reference Commands

### Check cluster status
```bash
docker exec mariadb-galera-node1 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep%';"
```

### Check grastate.dat
```bash
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat
```

### Force bootstrap
```bash
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
```

### View logs
```bash
docker logs -f mariadb-galera-node1
docker logs -f mariadb-galera-node2
```

## Contact

For issues not covered in this guide, consult:
- MariaDB Galera documentation: https://mariadb.com/kb/en/galera-cluster/
- Docker logs for specific error messages

