# MariaDB Galera Cluster - Maintenance Scripts

This directory contains maintenance and recovery scripts for the MariaDB Galera cluster.

## Overview

The cluster consists of two nodes:
- **Node1 (srv042036)**: 10.87.2.22 - Primary bootstrap node
- **Node2 (srv042037)**: 10.87.2.23 - Secondary node

## Scripts

### 1. pre-patch-shutdown.sh
**Purpose**: Gracefully shut down the cluster before server maintenance/patching

**Usage**:
```bash
# On node2 (srv042037) - ALWAYS STOP NODE2 FIRST
./pre-patch-shutdown.sh

# Then on node1 (srv042036)
./pre-patch-shutdown.sh
```

**What it does**:
- Checks current cluster status
- Performs graceful shutdown
- Verifies `grastate.dat` is in good state
- Records shutdown timestamp

**When to use**:
- Before any server patching/updates
- Before planned reboots
- Before any maintenance that requires stopping the cluster

---

### 2. post-patch-startup.sh
**Purpose**: Safely restart the cluster after server maintenance

**Usage**:
```bash
# On node1 (srv042036) - ALWAYS START NODE1 FIRST
./post-patch-startup.sh

# Wait for node1 to be PRIMARY, then on node2 (srv042037)
./post-patch-startup.sh
```

**What it does**:
- Checks `grastate.dat` status
- Sets `safe_to_bootstrap: 1` on node1 if needed
- Starts the container
- Waits for database to be ready
- Verifies cluster status
- Records startup timestamp

**When to use**:
- After server patching/updates
- After planned reboots
- After any maintenance that required stopping the cluster

---

### 3. emergency-recovery.sh
**Purpose**: Recover cluster after unclean shutdown (crash, forced reboot, etc.)

**Usage**:
```bash
# ONLY run on node1 (srv042036)
./emergency-recovery.sh
```

**What it does**:
- Stops both nodes
- Checks `grastate.dat` on both nodes
- Determines which node has the most recent data (highest seqno)
- Sets `safe_to_bootstrap: 1` on the appropriate node
- Cleans up stale SST files (`sst_in_progress`, `wsrep_sst.pid`, `gvwstate.dat`)
- Starts bootstrap node first
- Starts the other node to join
- Verifies cluster status

**When to use**:
- After unexpected server crashes
- After forced reboots (e.g., power failure)
- When both nodes show `safe_to_bootstrap: 0`
- When cluster won't start normally

**⚠ Important**: This script requires SSH access from node1 to node2

---

## Common Scenarios

### Scenario 1: Planned Maintenance (Patching)

**Before patching**:
1. Run `pre-patch-shutdown.sh` on **node2** first
2. Run `pre-patch-shutdown.sh` on **node1** second
3. Proceed with server patching/reboots

**After patching**:
1. Run `post-patch-startup.sh` on **node1** first
2. Wait for node1 to show `cluster_status = Primary`
3. Run `post-patch-startup.sh` on **node2**
4. Verify both nodes show `cluster_size = 2`

---

### Scenario 2: Unplanned Reboot (Crash/Power Failure)

**After servers come back online**:
1. Check if containers auto-started
2. If cluster is not healthy, run `emergency-recovery.sh` on **node1**
3. Follow the script prompts
4. Verify cluster status on both nodes

---

### Scenario 3: SST Failures ("Previous SST is not completed")

**Symptoms**:
- Node2 shows "previous SST script still running"
- Error: "Failed to open IST listener at tcp://10.87.2.23:4568"
- Error: "Cannot assign requested address: System error: 99"
- Node2 can't join the cluster

**Root Causes**:
1. **Stale PID files** - `rsync_sst.pid`, `wsrep_sst.pid`, `sst_in_progress` files persist after crashes
2. **Network binding issues** - Container cannot bind to host IP for IST/SST (requires `network_mode: host`)
3. **Special characters in passwords** - Characters like `%`, `@`, `$` in SST passwords cause script failures

**Recovery**:
1. Stop both nodes:
   ```bash
   docker stop mariadb-galera-node2  # On srv042037
   docker stop mariadb-galera-node1  # On srv042036
   ```

2. Clean stale SST files on both nodes:
   ```bash
   # On srv042036 (node1)
   docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine sh -c "
       rm -f /data/rsync_sst.conf
       rm -f /data/rsync_sst.pid
       rm -f /data/sst_in_progress
       rm -f /data/wsrep_sst.pid
       rm -f /data/gvwstate.dat
   "

   # On srv042037 (node2)
   docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine sh -c "
       rm -f /data/rsync_sst.conf
       rm -f /data/rsync_sst.pid
       rm -f /data/sst_in_progress
       rm -f /data/wsrep_sst.pid
       rm -f /data/gvwstate.dat
   "
   ```

3. Set safe_to_bootstrap on node1:
   ```bash
   docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
       sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
   ```

4. Start node1 first:
   ```bash
   docker start mariadb-galera-node1
   ```

5. Wait for node1 to be PRIMARY (30-60 seconds)

6. Start node2:
   ```bash
   docker start mariadb-galera-node2
   ```

7. Monitor logs: `docker logs -f mariadb-galera-node2`

---

## Manual Commands Reference

### Check Cluster Status
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

### Check grastate.dat
```bash
# Node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat

# Node2
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine cat /data/grastate.dat
```

### Set safe_to_bootstrap
```bash
# Node1
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat

# Node2
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine \
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

### View Logs
```bash
# Node1
docker logs -f mariadb-galera-node1

# Node2
docker logs -f mariadb-galera-node2

# Last 100 lines
docker logs --tail 100 mariadb-galera-node1
```

---

## Important Notes

### Shutdown Order
**Always stop node2 first, then node1**
- Node2 is the secondary node
- Node1 is the bootstrap node and should be the last to stop

### Startup Order
**Always start node1 first, then node2**
- Node1 should bootstrap the cluster
- Node2 joins the existing cluster

### Bootstrap Flag
- The `--wsrep-new-cluster` flag should **only** be present on node1's Portainer stack
- This flag should **only** be used during initial setup or recovery
- **Remove this flag** once the cluster is healthy and both nodes are synced
- Leaving it in place long-term can cause issues

### safe_to_bootstrap Flag
- Only **one node** should have `safe_to_bootstrap: 1` at a time
- This should be the node with the most recent data (highest seqno)
- After graceful shutdown, the last node to stop will have `safe_to_bootstrap: 1`
- After unclean shutdown, both nodes may have `safe_to_bootstrap: 0`

### Stale SST Files
These files can persist after crashes and prevent SST from working:
- `rsync_sst.conf` - rsync SST configuration file
- `rsync_sst.pid` - PID file for rsync SST process
- `sst_in_progress` - Indicates SST is in progress
- `wsrep_sst.pid` - Generic PID file for SST process
- `gvwstate.dat` - Galera view state (last node to leave)

**Always clean these files** after unclean shutdowns before attempting recovery.

### Network Configuration
The cluster uses `network_mode: host` in docker-compose files to allow Galera to bind directly to host IP addresses (10.87.2.22 and 10.87.2.23). This is **required** for IST/SST to work properly.

**Do NOT use bridge networking** - it will cause "Cannot assign requested address" errors during SST.

### Password Requirements
Service account passwords (SST_PASSWORD, MONITOR_PASSWORD, REPL_PASSWORD) should **avoid special characters** like `%`, `@`, `$` as they can cause issues with SST scripts when passed as command-line arguments.

Use alphanumeric passwords with simple special characters like `-`, `_` only.

---

## Troubleshooting

### Cluster won't start after reboot
1. Check `grastate.dat` on both nodes
2. Run `emergency-recovery.sh` on node1
3. Follow the script prompts

### SST fails with "Previous SST is not completed"
1. Stop both nodes
2. Clean stale SST files on both nodes (including `rsync_sst.pid`)
3. Set `safe_to_bootstrap: 1` on node1
4. Start node1 first, wait for PRIMARY
5. Start node2
6. If still failing, verify `network_mode: host` is set in docker-compose files
7. Check that SST passwords don't contain special characters like `%`, `@`, `$`

### Both nodes show cluster_size = 1
1. Check network connectivity between nodes (ports 4567, 4568, 4444)
2. Check firewall rules
3. Check `wsrep_cluster_address` in docker-compose files
4. Restart node2 to force rejoin

### wsrep_ready = OFF
1. Check logs for errors
2. Verify `safe_to_bootstrap: 1` on bootstrap node
3. Verify `--wsrep-new-cluster` flag is present on bootstrap node
4. Restart the node

---

## Backup and Restore

### Create Backup
```bash
# Logical backup (SQL dump)
docker exec mariadb-galera-node1 mariadb-dump -uroot -p'pHIbY#22we@0Y^BB' \
    --all-databases --single-transaction > /data/docker_configs/mariadb_galera/backup/backup-$(date +%Y%m%d).sql

# Physical backup (mariadb-backup)
docker exec mariadb-galera-node1 mariadb-backup --backup \
    --target-dir=/data/docker_configs/mariadb_galera/backup/physical-$(date +%Y%m%d) \
    --user=root \
    --password='pHIbY#22we@0Y^BB'
```

### Restore from Backup
```bash
# Restore SQL dump (cluster must be running)
# Data will automatically replicate to node2
docker exec -i mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' < /data/docker_configs/mariadb_galera/backup/backup.sql

# Or restore to specific database
docker exec -i mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' dcsautomation < /data/docker_configs/mariadb_galera/backup/backup.sql

# Verify restoration
docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "SHOW DATABASES;"
docker exec mariadb-galera-node2 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "SHOW DATABASES;"
```

---

## Version Information

- **MariaDB Version**: 11.8.3 LTS (currently deployed)
- **Galera Version**: 26.4.23 (included with MariaDB)
- **Docker Image**: `mariadb:lts`
- **SST Method**: `rsync` (more reliable than mariabackup for this setup)

### Version Notes
- MariaDB 11.8.3 LTS is currently deployed and working with `network_mode: host`
- SST method changed from `mariabackup` to `rsync` for better reliability
- Host networking is required for proper IST/SST functionality

---

## Support

For issues or questions:
1. Check logs: `docker logs mariadb-galera-node1`
2. Check cluster status (see commands above)
3. Review this README for common scenarios
4. Consult MariaDB Galera documentation: https://mariadb.com/kb/en/galera-cluster/

---

**Last Updated**: 2025-10-21
**Maintained By**: DCS Automation Team

