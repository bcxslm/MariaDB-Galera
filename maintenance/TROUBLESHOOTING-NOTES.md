# MariaDB Galera Cluster - Troubleshooting Notes

## Issue Resolution Summary (2025-10-21)

### Problem: SST Failures After Server Patching

After server patching and reboots, the Galera cluster experienced persistent SST (State Snapshot Transfer) failures on node2, preventing it from joining the cluster.

---

## Root Causes Identified

### 1. Stale SST PID Files
**Symptom**: "Previous SST is not completed, waiting for it to exit"

**Cause**: SST scripts create PID files that persist after crashes:
- `rsync_sst.pid` - rsync SST process ID
- `rsync_sst.conf` - rsync SST configuration
- `wsrep_sst.pid` - Generic SST process ID
- `sst_in_progress` - SST status flag
- `gvwstate.dat` - Galera view state

These files survive container restarts and even volume recreations if not explicitly deleted.

**Solution**: Always clean these files after unclean shutdowns:
```bash
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine sh -c "
    rm -f /data/rsync_sst.conf
    rm -f /data/rsync_sst.pid
    rm -f /data/sst_in_progress
    rm -f /data/wsrep_sst.pid
    rm -f /data/gvwstate.dat
"
```

---

### 2. Docker Network Configuration
**Symptom**: "Failed to open IST listener at tcp://10.87.2.23:4568', asio error 'Failed to listen: bind: Cannot assign requested address: System error: 99"

**Cause**: Galera needs to bind to the actual host IP addresses (10.87.2.22 and 10.87.2.23) for IST/SST to work. When using Docker bridge networking with custom IPs (172.20.0.10, 172.20.0.11), the container cannot bind to the host IPs.

**Solution**: Use `network_mode: host` in docker-compose files:
```yaml
services:
  mariadb-node1:
    image: mariadb:lts
    network_mode: host
    # Remove ports section - not needed with host networking
    # Remove networks section - not compatible with host mode
```

**Important**: 
- Remove the `ports:` section (not needed with host networking)
- Remove the `networks:` section at the bottom of the file
- This gives the container direct access to the host's network interfaces

---

### 3. Special Characters in Passwords
**Symptom**: SST scripts fail silently or with parsing errors

**Cause**: Service account passwords containing special characters like `%`, `@`, `$` cause issues when passed as command-line arguments to SST scripts.

**Original problematic passwords**:
```bash
SST_PASSWORD=hdazus1%frjp@AtD        # Contains % and @
MONITOR_PASSWORD=9MD0@Yetu4B9CGSe    # Contains @
REPL_PASSWORD=xZL%Oxx2u$R@REHd       # Contains %, @, and $
```

**Solution**: Use alphanumeric passwords with only simple special characters:
```bash
SST_PASSWORD=SstPassword123
MONITOR_PASSWORD=MonitorPassword123
REPL_PASSWORD=ReplPassword123
```

**Recommendation**: Avoid `%`, `@`, `$`, `!` in SST/service account passwords. Use `-`, `_` if special characters are required.

---

## Configuration Changes Made

### 1. Docker Compose Files
**Changed**:
- Added `network_mode: host` to all service definitions
- Removed `ports:` section (not needed with host networking)
- Removed `networks:` section (not compatible with host mode)
- Changed SST method from `mariabackup` to `rsync`
- Updated image to `mariadb:lts` (11.8.3)

**Files updated**:
- `docker-compose-host1.yml`
- `docker-compose-host1-bootstrap.yml`
- `docker-compose-host2.yml`
- `docker-compose-host2-bootstrap.yml`

### 2. MariaDB Configuration Files
**Changed**:
- `wsrep_sst_method = rsync` (was `mariabackup`)
- `wsrep_sst_auth = "sst_user:SstPassword123"` (removed special characters)

**Files updated**:
- `galera-prd1.cnf`
- `galera-prd2.cnf`

### 3. Environment Files
**Changed**:
- Simplified all service account passwords to remove special characters

**Files updated**:
- `.prd1.env`
- `.prd2.env`

---

## Current Working Configuration

### MariaDB Version
- **Image**: `mariadb:lts` (11.8.3)
- **Galera Version**: 26.4.23 (included)

### SST Method
- **Method**: `rsync` (more reliable than mariabackup for this setup)
- **Port**: 4444

### Network Configuration
- **Mode**: `network_mode: host`
- **Node1 IP**: 10.87.2.22 (srv042036)
- **Node2 IP**: 10.87.2.23 (srv042037)

### Ports Used
- **3306**: MySQL/MariaDB
- **4567**: Galera cluster replication
- **4568**: Incremental State Transfer (IST)
- **4444**: State Snapshot Transfer (SST)

---

## Lessons Learned

### 1. Always Clean Stale Files After Crashes
After any unclean shutdown (crash, forced reboot, signal 11), always clean:
- `rsync_sst.conf`
- `rsync_sst.pid`
- `sst_in_progress`
- `wsrep_sst.pid`
- `gvwstate.dat`

### 2. Host Networking is Required for Galera
Bridge networking with custom IPs does not work reliably with Galera's IST/SST mechanisms. Use `network_mode: host`.

### 3. Avoid Special Characters in Service Passwords
SST scripts are sensitive to special characters in passwords. Keep them simple.

### 4. Configuration Consistency is Critical
Ensure docker-compose command flags match the .cnf file settings:
- SST method must match in both places
- SST passwords must match in both places

### 5. Bootstrap Flag Management
The `--wsrep-new-cluster` flag should:
- Only be on node1's Portainer stack
- Only be used during initial setup or recovery
- Be removed once cluster is healthy (optional but recommended)

---

## Recovery Procedure (Final Working Version)

### After Unclean Shutdown

1. **Stop both nodes**:
   ```bash
   docker stop mariadb-galera-node1
   docker stop mariadb-galera-node2
   ```

2. **Clean stale SST files on both nodes**:
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

3. **Set safe_to_bootstrap on node1**:
   ```bash
   docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
       sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
   ```

4. **Start node1** (ensure `--wsrep-new-cluster` is in Portainer stack):
   ```bash
   docker start mariadb-galera-node1
   ```

5. **Wait for node1 to be PRIMARY** (30-60 seconds):
   ```bash
   docker exec mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "
       SHOW STATUS LIKE 'wsrep_cluster_status';"
   ```
   Should show: `Primary`

6. **Start node2**:
   ```bash
   docker start mariadb-galera-node2
   ```

7. **Verify cluster health**:
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
   Expected:
   - `wsrep_cluster_size = 2`
   - `wsrep_cluster_status = Primary`
   - `wsrep_ready = ON`
   - `wsrep_local_state_comment = Synced`

---

## Testing Performed

### Version Testing
Tested multiple MariaDB versions to isolate the issue:
- ✅ MariaDB 11.8.3 (lts) - **Working with host networking**
- ❌ MariaDB 11.4 - Same SST issues with bridge networking
- ❌ MariaDB 10.11 - Same SST issues with bridge networking

**Conclusion**: The issue was not version-specific but configuration-specific.

### SST Method Testing
- ❌ `mariabackup` - Had PID file race condition issues
- ✅ `rsync` - More reliable, simpler, no PID file issues

### Network Testing
- ❌ Bridge network with custom IPs (172.20.0.x) - Cannot bind to host IPs
- ✅ Host networking - Direct access to host IPs, IST/SST works

---

## Backup and Restore

### Create Backup
```bash
docker exec mariadb-galera-node1 mariadb-dump -uroot -p'pHIbY#22we@0Y^BB' \
    --all-databases --single-transaction > /data/docker_configs/mariadb_galera/backup/backup-$(date +%Y%m%d).sql
```

### Restore Backup
```bash
# Cluster must be running and healthy
docker exec -i mariadb-galera-node1 mariadb -uroot -p'pHIbY#22we@0Y^BB' < /data/docker_configs/mariadb_galera/backup/backup.sql

# Verify replication to node2
docker exec mariadb-galera-node2 mariadb -uroot -p'pHIbY#22we@0Y^BB' -e "SHOW DATABASES;"
```

---

## Future Recommendations

1. **Monitor SST file cleanup**: Add monitoring to detect stale SST files
2. **Automate recovery**: Consider adding health checks that auto-clean stale files
3. **Password policy**: Document password requirements for service accounts
4. **Network documentation**: Clearly document why host networking is required
5. **Pre-patch checklist**: Always run pre-patch-shutdown.sh before maintenance
6. **Post-patch verification**: Always verify cluster health after maintenance

---

**Last Updated**: 2025-10-21  
**Status**: Cluster operational and stable  
**Configuration**: MariaDB 11.8.3 LTS with rsync SST and host networking

