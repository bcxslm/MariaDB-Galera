# MariaDB Galera Cluster - Quick Reference Card

## 🚀 Quick Commands

### Check Cluster Status
```bash
./check-cluster-status.sh
```

### Before Patching (Planned Maintenance)
```bash
# On node2 (srv042037) - FIRST
./pre-patch-shutdown.sh

# On node1 (srv042036) - SECOND
./pre-patch-shutdown.sh
```

### After Patching (Planned Maintenance)
```bash
# On node1 (srv042036) - FIRST
./post-patch-startup.sh

# On node2 (srv042037) - SECOND
./post-patch-startup.sh
```

### Emergency Recovery (After Crash)
```bash
# ONLY on node1 (srv042036)
./emergency-recovery.sh
```

---

## 📊 Manual Status Checks

### Quick Status
```bash
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

### Expected Healthy Output
```
wsrep_cluster_size          2
wsrep_cluster_status        Primary
wsrep_ready                 ON
wsrep_local_state_comment   Synced
```

---

## 🔧 Common Manual Fixes

### Check grastate.dat
```bash
# Node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat

# Node2
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine cat /data/grastate.dat
```

### Set safe_to_bootstrap (Node1 only)
```bash
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
```

### Clean Stale SST Files
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
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine sh -c "
    rm -f /data/rsync_sst.conf
    rm -f /data/rsync_sst.pid
    rm -f /data/sst_in_progress
    rm -f /data/wsrep_sst.pid
    rm -f /data/gvwstate.dat
"
```

### Restart Sequence
```bash
# 1. Stop both nodes
docker stop mariadb-galera-node1
docker stop mariadb-galera-node2

# 2. Set safe_to_bootstrap on node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat

# 3. Start node1 (ensure --wsrep-new-cluster is in Portainer stack)
docker start mariadb-galera-node1

# 4. Wait for node1 to be PRIMARY (30 seconds)
sleep 30

# 5. Start node2
docker start mariadb-galera-node2

# 6. Verify cluster
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

---

## 📝 View Logs

### Follow Logs (Real-time)
```bash
# Node1
docker logs -f mariadb-galera-node1

# Node2
docker logs -f mariadb-galera-node2
```

### Last 100 Lines
```bash
docker logs --tail 100 mariadb-galera-node1
docker logs --tail 100 mariadb-galera-node2
```

### Search Logs for Errors
```bash
docker logs mariadb-galera-node1 2>&1 | grep -i error
docker logs mariadb-galera-node2 2>&1 | grep -i error
```

---

## 💾 Backup Commands

### Quick SQL Backup
```bash
docker exec mariadb-galera-node1 mariadb-dump -uroot -p'pHIbY#22we@0Y^BB' \
    --all-databases --single-transaction > /data/docker_configs/mariadb_galera/backup/backup-$(date +%Y%m%d).sql
```

### Physical Backup
```bash
docker exec mariadb-galera-node1 mariadb-backup --backup \
    --target-dir=/data/docker_configs/mariadb_galera/backup/physical-$(date +%Y%m%d) \
    --user=root \
    --password='pHIbY#22we@0Y^BB'
```

---

## ⚠️ Important Rules

### Shutdown Order
1. **Node2 FIRST** (srv042037)
2. **Node1 SECOND** (srv042036)

### Startup Order
1. **Node1 FIRST** (srv042036) - Bootstrap node
2. **Node2 SECOND** (srv042037) - Joining node

### Bootstrap Flag
- `--wsrep-new-cluster` should **ONLY** be on node1
- **ONLY** during initial setup or recovery
- **REMOVE** after cluster is healthy

### safe_to_bootstrap
- **ONLY ONE NODE** should have `safe_to_bootstrap: 1`
- Usually the node with highest `seqno`
- After graceful shutdown: last node to stop
- After crash: check both nodes and choose highest seqno

---

## 🚨 Troubleshooting Quick Guide

### Problem: Cluster won't start after reboot
**Solution**: Run `./emergency-recovery.sh` on node1

### Problem: SST fails with "Previous SST is not completed"
**Solution**:
1. Stop both nodes
2. Clean stale SST files on both nodes (including `rsync_sst.pid`)
3. Set `safe_to_bootstrap: 1` on node1
4. Start node1, wait for PRIMARY
5. Start node2

### Problem: Both nodes show cluster_size = 1
**Solution**:
1. Check network connectivity (ports 4567, 4568, 4444)
2. Restart node2 to force rejoin

### Problem: wsrep_ready = OFF
**Solution**:
1. Check logs for errors
2. Verify `safe_to_bootstrap: 1` on bootstrap node
3. Verify `--wsrep-new-cluster` flag on bootstrap node
4. Restart the node

### Problem: "Cannot assign requested address" during SST
**Solution**:
1. Verify `network_mode: host` is set in docker-compose files
2. Verify no bridge network configuration exists
3. Restart both nodes

---

## 📞 Node Information

| Node | Hostname | IP Address | Container Name | Role |
|------|----------|------------|----------------|------|
| Node1 | srv042036 | 10.87.2.22 | mariadb-galera-node1 | Bootstrap/Primary |
| Node2 | srv042037 | 10.87.2.23 | mariadb-galera-node2 | Secondary |

### Ports
- **3306**: MySQL/MariaDB
- **4567**: Galera replication
- **4568**: Incremental State Transfer (IST)
- **4444**: State Snapshot Transfer (SST)

---

## 📚 Documentation

- **Full Documentation**: `README.md`
- **Recovery Procedures**: `RECOVERY.md` (in parent directory)
- **Quick Recovery**: `QUICK-RECOVERY.md` (in parent directory)

---

**Last Updated**: 2025-10-21

