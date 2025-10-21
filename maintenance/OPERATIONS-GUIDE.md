# MariaDB Galera Cluster - Operations Guide

## Pre-Patch Shutdown

**Order: Node2 → Node1**

### Node2 (srv042037)
```bash
docker stop mariadb-galera-node2
```

### Node1 (srv042036)
```bash
docker stop mariadb-galera-node1
```

### Verify
```bash
# Check grastate.dat on node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat
```

**Look for**: `safe_to_bootstrap: 1` on at least one node

---

## Post-Patch Startup

**Order: Node1 → Node2**

### Node1 (srv042036)
```bash
# Set safe_to_bootstrap if needed
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat

# Start node1 (ensure --wsrep-new-cluster is in Portainer stack)
docker start mariadb-galera-node1

# Wait 30 seconds
sleep 30

# Check status
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
    SELECT VARIABLE_NAME, VARIABLE_VALUE 
    FROM information_schema.GLOBAL_STATUS 
    WHERE VARIABLE_NAME IN ('wsrep_cluster_status', 'wsrep_ready');"
```

**Look for**: 
- `wsrep_cluster_status = Primary`
- `wsrep_ready = ON`

### Node2 (srv042037)
```bash
# Start node2
docker start mariadb-galera-node2

# Wait 30 seconds
sleep 30

# Check status
docker exec mariadb-galera-node2 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
    SELECT VARIABLE_NAME, VARIABLE_VALUE 
    FROM information_schema.GLOBAL_STATUS 
    WHERE VARIABLE_NAME IN ('wsrep_cluster_size', 'wsrep_local_state_comment');"
```

**Look for**:
- `wsrep_cluster_size = 2`
- `wsrep_local_state_comment = Synced`

---

## Cluster Health Check

```bash
# Run on either node
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
    SELECT VARIABLE_NAME, VARIABLE_VALUE 
    FROM information_schema.GLOBAL_STATUS 
    WHERE VARIABLE_NAME IN (
        'wsrep_cluster_size',
        'wsrep_cluster_status',
        'wsrep_ready',
        'wsrep_local_state_comment'
    );"
```

### Healthy Output
```
wsrep_cluster_size          2
wsrep_cluster_status        Primary
wsrep_ready                 ON
wsrep_local_state_comment   Synced
```

### Check Logs
```bash
# Last 50 lines
docker logs --tail 50 mariadb-galera-node1
docker logs --tail 50 mariadb-galera-node2

# Search for errors
docker logs mariadb-galera-node1 2>&1 | grep -i error
```

---

## Emergency Recovery (After Crash)

**Run from Node1 (srv042036)**

### Step 1: Stop Both Nodes
```bash
# Local (node1)
docker stop mariadb-galera-node1

# Remote (node2)
ssh srv042037 "docker stop mariadb-galera-node2"
```

### Step 2: Check grastate.dat
```bash
# Node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat

# Node2
ssh srv042037 "docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine cat /data/grastate.dat"
```

**Look for**: 
- `seqno` value (higher = more recent)
- `safe_to_bootstrap` (1 = safe, 0 = unsafe)

**Decision**: Bootstrap from node with highest `seqno` OR `safe_to_bootstrap: 1`

### Step 3: Clean Stale SST Files
```bash
# Node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine sh -c "
    rm -f /data/rsync_sst.conf
    rm -f /data/rsync_sst.pid
    rm -f /data/sst_in_progress
    rm -f /data/wsrep_sst.pid
    rm -f /data/gvwstate.dat
"

# Node2
ssh srv042037 "docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine sh -c '
    rm -f /data/rsync_sst.conf
    rm -f /data/rsync_sst.pid
    rm -f /data/sst_in_progress
    rm -f /data/wsrep_sst.pid
    rm -f /data/gvwstate.dat
'"
```

### Step 4: Set Bootstrap Node (Usually Node1)
```bash
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
```

### Step 5: Start Node1
```bash
# Ensure --wsrep-new-cluster is in Portainer stack
docker start mariadb-galera-node1

# Wait and verify
sleep 30
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
    SHOW STATUS LIKE 'wsrep_cluster_status';"
```

**Look for**: `Primary`

### Step 6: Start Node2
```bash
ssh srv042037 "docker start mariadb-galera-node2"

# Wait and verify
sleep 30
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
    SHOW STATUS LIKE 'wsrep_cluster_size';"
```

**Look for**: `2`

### Step 7: Remove Bootstrap Flag
Once both nodes are synced, remove `--wsrep-new-cluster` from node1's Portainer stack and redeploy.

---

## Common Issues

### Issue: SST fails with "Previous SST is not completed"
```bash
# Stop both nodes
docker stop mariadb-galera-node1
ssh srv042037 "docker stop mariadb-galera-node2"

# Clean stale SST files on both nodes (see Step 3 above)

# Set safe_to_bootstrap on node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat

# Start node1
docker start mariadb-galera-node1

# Wait for PRIMARY
sleep 30

# Start node2
ssh srv042037 "docker start mariadb-galera-node2"
```

### Issue: "Cannot assign requested address" during SST
```bash
# Verify network_mode: host is set in docker-compose files
# Verify no bridge network configuration exists
# Restart both nodes in order (node1 → node2)
```

### Issue: wsrep_ready = OFF
```bash
# Check logs for errors
docker logs mariadb-galera-node1

# Verify safe_to_bootstrap: 1
# Verify --wsrep-new-cluster flag present
# Restart the node
```

### Issue: cluster_size = 1 (should be 2)
```bash
# Check network connectivity
ping 10.87.2.22  # node1
ping 10.87.2.23  # node2

# Check ports
sudo lsof -i :4567
sudo lsof -i :4568
sudo lsof -i :4444

# Restart node2 to force rejoin
docker restart mariadb-galera-node2
```

---

## Backup and Restore

### Create Backup
```bash
# SQL dump
docker exec mariadb-galera-node1 mariadb-dump -uroot -p'pHIbY#22we@0Y^BB' \
    --all-databases --single-transaction > /data/docker_configs/mariadb_galera/backup/backup-$(date +%Y%m%d).sql
```

### Restore Backup
```bash
# Restore SQL dump (cluster must be running)
# Data will automatically replicate to node2
docker exec -i mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' < /data/docker_configs/mariadb_galera/backup/backup.sql

# Verify restoration on both nodes
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "SHOW DATABASES;"
docker exec mariadb-galera-node2 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "SHOW DATABASES;"
```

---

## Key Rules

1. **Shutdown**: Node2 first, Node1 second
2. **Startup**: Node1 first, Node2 second
3. **Bootstrap**: Only Node1, only during recovery
4. **safe_to_bootstrap**: Only one node at a time
5. **Stale SST files**: Always clean after crashes (including `rsync_sst.pid`)
6. **Network mode**: Must use `network_mode: host` (not bridge)
7. **Passwords**: Avoid special characters (`%`, `@`, `$`) in SST passwords

---

## Node Info

| Node | Host | IP | Container |
|------|------|-------|-----------|
| Node1 | srv042036 | 10.87.2.22 | mariadb-galera-node1 |
| Node2 | srv042037 | 10.87.2.23 | mariadb-galera-node2 |

**Ports**: 3306 (MySQL), 4567 (Galera), 4568 (IST), 4444 (SST)

