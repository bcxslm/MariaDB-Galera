# Quick Recovery Guide - MariaDB Galera Cluster

## TL;DR - Fast Recovery After Reboot

### On Node1 (10.87.2.22):

```bash
# 1. Stop the container
docker stop mariadb-galera-node1

# 2. Set safe_to_bootstrap
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
  sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat

# 3. Enable bootstrap mode
sed -i 's/BOOTSTRAP_NODE1=no/BOOTSTRAP_NODE1=yes/' .prd1.env

# 4. Start node1
docker compose --env-file .prd1.env -f docker-compose-host1.yml up -d

# 5. Watch logs until "ready for connections"
docker logs -f mariadb-galera-node1
```

### On Node2 (10.87.2.23):

```bash
# 1. Clean up SST markers
docker stop mariadb-galera-node2
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine \
  sh -c "rm -f /data/sst_in_progress /data/wsrep_sst.pid"

# 2. Start node2 (BOOTSTRAP_NODE2 should be 'no')
docker compose --env-file .prd2.env -f docker-compose-host2.yml up -d

# 3. Watch logs
docker logs -f mariadb-galera-node2
```

### After Both Nodes Are Running:

```bash
# On node1: Disable bootstrap mode
docker stop mariadb-galera-node1
sed -i 's/BOOTSTRAP_NODE1=yes/BOOTSTRAP_NODE1=no/' .prd1.env
docker compose --env-file .prd1.env -f docker-compose-host1.yml up -d
```

## Verify Cluster Health

```bash
docker exec mariadb-galera-node1 mysql -uroot -p'pHIbY#22we@0Y^BB' -e "
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_ready';
SHOW STATUS LIKE 'wsrep_connected';
"
```

Expected output:
```
wsrep_cluster_size = 2
wsrep_ready = ON
wsrep_connected = ON
```

## Environment Variable Reference

Edit `.prd1.env` or `.prd2.env`:

```bash
# Normal operation (default)
BOOTSTRAP_NODE1=no
BOOTSTRAP_NODE2=no

# Disaster recovery (set ONE node only)
BOOTSTRAP_NODE1=yes  # <-- Enable bootstrap on node1
BOOTSTRAP_NODE2=no
```

## Common Commands

### Start with specific env file
```bash
docker compose --env-file .prd1.env -f docker-compose-host1.yml up -d
```

### Check grastate.dat
```bash
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine cat /data/grastate.dat
```

### Force safe_to_bootstrap
```bash
docker run --rm -v mariadb-galera-node1_mariadb_data:/data alpine \
  sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /data/grastate.dat
```

### Enable/Disable Bootstrap
```bash
# Enable
sed -i 's/BOOTSTRAP_NODE1=no/BOOTSTRAP_NODE1=yes/' .prd1.env

# Disable
sed -i 's/BOOTSTRAP_NODE1=yes/BOOTSTRAP_NODE1=no/' .prd1.env
```

### View logs
```bash
docker logs -f mariadb-galera-node1
docker logs --tail 100 mariadb-galera-node1
```

## Troubleshooting

### Node2 SST Failure
```bash
# Remove node2 data and force full resync
docker stop mariadb-galera-node2
docker run --rm -v mariadb-galera-node2_mariadb_data:/data alpine rm -rf /data/*
docker compose --env-file .prd2.env -f docker-compose-host2.yml up -d
```

### Port Binding Issues
```bash
# Check if ports are in use
netstat -tulpn | grep -E '3306|4567|4568|4444'
```

### Check Container Network
```bash
docker inspect mariadb-galera-node1 | grep IPAddress
docker inspect mariadb-galera-node2 | grep IPAddress
```

## Graceful Shutdown (Prevent Future Issues)

```bash
# Always stop in this order:
# 1. Stop node2 first
docker stop mariadb-galera-node2

# 2. Wait 10 seconds
sleep 10

# 3. Stop node1 last
docker stop mariadb-galera-node1
```

This ensures node1 is marked as `safe_to_bootstrap: 1` automatically.

