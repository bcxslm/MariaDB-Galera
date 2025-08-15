# MariaDB Galera Cluster Setup

This directory contains the configuration files and Docker Compose setups for creating a two-node MariaDB Galera cluster running on separate hosts.

## Overview

This setup uses **MariaDB 11.8 LTS** (Long Term Support), the latest stable LTS version released in 2024.

Galera Cluster is a synchronous multi-master cluster solution for MariaDB. It provides:
- **Synchronous replication**: All nodes are always consistent
- **Multi-master**: Read and write to any node
- **Automatic failover**: No single point of failure
- **Hot standby**: No downtime during failover

## Architecture

```
Host 1 (192.168.1.100)          Host 2 (192.168.1.101)
┌─────────────────────┐         ┌─────────────────────┐
│   MariaDB Node 1    │◄────────┤   MariaDB Node 2    │
│   (Primary)         │         │   (Secondary)       │
│   Port: 3306        │         │   Port: 3306        │
│   Galera: 4567      │         │   Galera: 4567      │
└─────────────────────┘         └─────────────────────┘
```

## Files Structure

```
MariaDB/clustering/
├── docker-compose-host1.yml    # Docker Compose for Host 1 (Primary)
├── docker-compose-host2.yml    # Docker Compose for Host 2 (Secondary)
├── galera.cnf                  # Base Galera configuration
├── galera-node1.cnf            # Node 1 specific configuration
├── galera-node2.cnf            # Node 2 specific configuration
├── .env.example                # Environment variables template
├── init-scripts/               # Database initialization scripts
│   ├── 01-create-sst-user.sql.template  # SST user creation template
│   ├── 01-create-sst-user.sql  # Generated SST user creation (after setup)
│   └── 02-create-test-data.sql # Test data for verification
├── generate-init-scripts.sh    # Script to generate SQL from templates
└── README.md                   # This file
```

## Prerequisites

1. **Two separate hosts** with Docker and Docker Compose installed
2. **Network connectivity** between hosts on ports 3306, 4567, 4568, and 4444
3. **Firewall rules** configured to allow communication between hosts
4. **Sufficient resources**: At least 2GB RAM and 10GB disk space per host

## Quick Start

### Step 1: Prepare Configuration

1. Copy the clustering directory to both hosts
2. Copy `.env.example` to `.env` on both hosts
3. Edit `.env` files with your actual IP addresses:

```bash
# On Host 1
HOST1_IP=192.168.1.100  # Your Host 1 IP
HOST2_IP=192.168.1.101  # Your Host 2 IP

# On Host 2 (same values)
HOST1_IP=192.168.1.100  # Your Host 1 IP  
HOST2_IP=192.168.1.101  # Your Host 2 IP
```

### Step 2: Update Configuration Files

Replace `HOST1_IP` and `HOST2_IP` placeholders in:
- `galera-node1.cnf`
- `galera-node2.cnf`

### Step 3: Start the Cluster

**On Host 1 (Primary node):**
```bash
docker compose -f docker-compose-host1.yml up -d
```

**Wait for Host 1 to be fully initialized, then on Host 2:**
```bash
docker compose -f docker-compose-host2.yml up -d
```

### Step 4: Verify Cluster Status

Connect to any node and check cluster status:
```bash
# Check cluster status
docker exec -it mariadb-galera-node1 mysql -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size';"

# Or run the test script
chmod +x test-cluster.sh
./test-cluster.sh
```

## Important Ports

- **3306**: MySQL/MariaDB client connections
- **4567**: Galera cluster replication traffic
- **4568**: Incremental State Transfer (IST)
- **4444**: State Snapshot Transfer (SST)

## Security Considerations

1. **Change default passwords** in `.env` file
2. **Configure firewall** to restrict access to Galera ports
3. **Use SSL/TLS** for client connections (configure in galera.cnf)
4. **Regular backups** of your data

## Monitoring and Maintenance

### Health Checks
The containers include health checks that verify:
- Database connectivity
- Cluster membership
- Node synchronization

### Useful Commands

Check cluster status:
```sql
SHOW STATUS LIKE 'wsrep_%';
```

View cluster members:
```sql
SHOW STATUS LIKE 'wsrep_incoming_addresses';
```

Check node state:
```sql
SHOW STATUS LIKE 'wsrep_local_state_comment';
```

## Troubleshooting

### Common Issues

1. **Split-brain scenario**: If both nodes start independently
   - Solution: Stop both, start primary with `--wsrep-new-cluster`

2. **Network connectivity**: Nodes can't communicate
   - Check firewall rules for ports 4567, 4568, 4444
   - Verify IP addresses in configuration

3. **SST failures**: State transfer fails
   - Check SST user credentials
   - Ensure sufficient disk space

### Recovery Procedures

**Complete cluster failure:**
1. Identify the node with the most recent data
2. Start that node with `--wsrep-new-cluster`
3. Start other nodes normally

**Single node failure:**
1. Fix the failed node
2. Start it normally (it will sync automatically)

## Performance Tuning

Key parameters to adjust based on your workload:
- `innodb_buffer_pool_size`: 70-80% of available RAM
- `wsrep_slave_threads`: Number of CPU cores
- `max_connections`: Based on application requirements

## Backup Strategy

1. **Regular mysqldump**: For point-in-time recovery
2. **Galera snapshot**: For cluster-wide consistent backups
3. **Binary logs**: For incremental backups

## Automated Setup Scripts

Use the provided scripts for easier configuration and deployment:

```bash
# Make scripts executable
chmod +x setup-cluster.sh
chmod +x deploy-to-servers.sh
chmod +x generate-init-scripts.sh

# Configure IP addresses and generate scripts with your .env variables
./setup-cluster.sh

# Deploy to your Linux servers (srv042036, srv042037)
./deploy-to-servers.sh
```

## Next Steps

1. Configure SSL/TLS encryption
2. Set up monitoring with tools like Prometheus/Grafana
3. Implement automated backup procedures
4. Consider adding a third node for better fault tolerance
