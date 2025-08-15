# MariaDB Galera Cluster Deployment Guide

## Environment Details

### Hosts
- **Host 1 (Primary)**: your-host1-name
- **Host 2 (Secondary)**: your-host2-name

### Configuration Paths
- **Config Directory**: `/path/to/your/config/directory`
- **User**: your-deployment-user
- **Group**: your-deployment-group
- **Umask**: 0027 (recommended)

### Container Names
- **Host 1**: `mariadb-galera-node1`
- **Host 2**: `mariadb-galera-node2`

## Pre-Deployment Steps

### 1. Create Directory Structure on Both Hosts

```bash
# On both hosts (as your deployment user)
mkdir -p /path/to/your/config/directory/{init-scripts,logs,data}
chmod -R 750 /path/to/your/config/directory
```

### 2. Copy Configuration Files

**On Host 1 (Primary):**
```bash
# Copy these files to your config directory:
- docker-compose-host1.yml
- galera-node1.cnf
- .env (created from .env.example)
- init-scripts/ (entire directory)
```

**On Host 2 (Secondary):**
```bash
# Copy these files to your config directory:
- docker-compose-host2.yml
- galera-node2.cnf
- .env (created from .env.example)
- init-scripts/ (entire directory)
```

### 3. Configure Environment Variables

Before deployment, create and configure your `.env` file:

```bash
# Copy the example file
cp .env.example .env

# Edit with your actual values
nano .env
```

**Update these key variables in .env:**
```bash
# Your actual server IP addresses
HOST1_IP=your.host1.ip.address
HOST2_IP=your.host2.ip.address

# Secure passwords (replace with strong passwords)
MYSQL_ROOT_PASSWORD=your_secure_root_password
SST_PASSWORD=your_secure_sst_password
```

## Deployment Commands

### Step 1: Start Primary Node (Host 1)

```bash
cd /path/to/your/config/directory
docker compose -f docker-compose-host1.yml up -d
```

### Step 2: Verify Primary Node

```bash
# Check container status
docker ps | grep mariadb-galera-node1

# Check logs
docker logs mariadb-galera-node1

# Verify cluster initialization
docker exec -it mariadb-galera-node1 mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_ready';"
```

### Step 3: Start Secondary Node (Host 2)

```bash
cd /path/to/your/config/directory
docker compose -f docker-compose-host2.yml up -d
```

### Step 4: Verify Cluster Formation

```bash
# On either host, check cluster size
docker exec -it mariadb-galera-node1 mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"

# Should return: wsrep_cluster_size = 2
```

## Network Requirements

### Firewall Rules
Ensure these ports are open between srv042036 and srv042037:

```bash
# MySQL client connections
3306/tcp

# Galera cluster communication
4567/tcp  # Cluster replication
4568/tcp  # Incremental State Transfer
4444/tcp  # State Snapshot Transfer
```

### Example iptables rules:
```bash
# On Host 1 - allow from Host 2
iptables -A INPUT -s HOST2_IP -p tcp --dport 3306 -j ACCEPT
iptables -A INPUT -s HOST2_IP -p tcp --dport 4567 -j ACCEPT
iptables -A INPUT -s HOST2_IP -p tcp --dport 4568 -j ACCEPT
iptables -A INPUT -s HOST2_IP -p tcp --dport 4444 -j ACCEPT

# On Host 2 - allow from Host 1
iptables -A INPUT -s HOST1_IP -p tcp --dport 3306 -j ACCEPT
iptables -A INPUT -s HOST1_IP -p tcp --dport 4567 -j ACCEPT
iptables -A INPUT -s HOST1_IP -p tcp --dport 4568 -j ACCEPT
iptables -A INPUT -s HOST1_IP -p tcp --dport 4444 -j ACCEPT
```

## File Permissions

Due to umask=0027, ensure proper permissions:

```bash
# Configuration files
chmod 640 /path/to/your/config/directory/*.cnf
chmod 640 /path/to/your/config/directory/.env
chmod 644 /path/to/your/config/directory/docker-compose-*.yml

# Scripts
chmod 750 /path/to/your/config/directory/*.sh
chmod 640 /path/to/your/config/directory/init-scripts/*.sql

# Directories
chmod 750 /path/to/your/config/directory
chmod 750 /path/to/your/config/directory/init-scripts
chmod 755 /path/to/your/config/directory/logs
chmod 755 /path/to/your/config/directory/data
```

## Monitoring Commands

### Health Check
```bash
# Check if containers are running
docker ps | grep mariadb-galera

# Check cluster status
docker exec -it mariadb-galera-node1 mysql -u root -p -e "
SHOW STATUS LIKE 'wsrep_cluster_size';
SHOW STATUS LIKE 'wsrep_ready';
SHOW STATUS LIKE 'wsrep_connected';
SHOW STATUS LIKE 'wsrep_local_state_comment';
"
```

### Log Monitoring
```bash
# Container logs
docker logs -f mariadb-galera-node1
docker logs -f mariadb-galera-node2

# MySQL logs (if mounted)
tail -f /path/to/your/config/directory/logs/error.log
tail -f /path/to/your/config/directory/logs/mysql.log
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure proper permissions on your config directory
   chmod -R 750 /path/to/your/config/directory
   ```

2. **Network Connectivity Issues**
   ```bash
   # Test connectivity between hosts
   telnet HOST2_IP 4567  # From Host 1
   telnet HOST1_IP 4567  # From Host 2
   ```

3. **Split-Brain Recovery**
   ```bash
   # Stop both containers
   docker compose -f docker-compose-host1.yml down
   docker compose -f docker-compose-host2.yml down
   
   # Start primary with new cluster flag
   docker compose -f docker-compose-host1.yml up -d
   
   # Wait for primary to be ready, then start secondary
   docker compose -f docker-compose-host2.yml up -d
   ```

## Backup and Maintenance

### Regular Backup
```bash
# Create backup directory
mkdir -p /path/to/your/backups/mariadb_galera

# Backup script
docker exec mariadb-galera-node1 mysqldump -u root -p --all-databases --single-transaction --routines --triggers > /path/to/your/backups/mariadb_galera/backup_$(date +%Y%m%d_%H%M%S).sql
```

### Updates
```bash
# Pull latest image
docker pull mariadb:11.8

# Recreate containers (one at a time)
docker compose -f docker-compose-host1.yml up -d --force-recreate
```
