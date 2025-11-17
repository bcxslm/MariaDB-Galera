# Setup Script Enhancements

## Overview
The `setup-cluster.sh` script has been enhanced with working directory configuration and automatic SCP file deployment capabilities.

## New Features

### 1. Working Directory Configuration
- **Variable**: `WORKDIR="/data/docker_configs/mariadb_galera"`
- **Purpose**: Defines the target directory on remote servers where all cluster files will be deployed
- **Customization**: You can modify this variable at the top of the script to match your environment

### 2. SSH User Configuration
- **Variable**: `SSH_USER="${SSH_USER:-root}"`
- **Purpose**: Defines the SSH user for remote connections
- **Default**: `root`
- **Customization**: Set the `SSH_USER` environment variable before running the script:
  ```bash
  export SSH_USER=your_username
  ./setup-cluster.sh
  ```

### 3. Automatic SCP Deployment
The script now includes a `deploy_to_server()` function that:
- Creates the necessary directory structure on remote servers
- Copies all required files via SCP:
  - Docker Compose files
  - Galera configuration files
  - Environment files (.env)
  - Initialization scripts
- Sets proper file permissions
- Provides error handling and feedback

## Usage

### Interactive Deployment
When you run `./setup-cluster.sh`, after configuring IP addresses, you'll be prompted:

```
Do you want to automatically deploy files to the servers via SCP?
This requires:
1. SSH access to both servers as user 'root'
2. Write access to /data/docker_configs/mariadb_galera directory
3. SSH key authentication (recommended)

Working directory on servers: /data/docker_configs/mariadb_galera

Deploy automatically? (y/n):
```

### Automatic Deployment (y)
If you choose **yes**:
1. The script will ping each server to verify connectivity
2. Create the directory structure on each server
3. Copy all necessary files via SCP
4. Set appropriate permissions
5. Provide commands to start the cluster

### Manual Deployment (n)
If you choose **no**:
- The script will display manual deployment instructions
- You can copy files manually using your preferred method

## Prerequisites for Auto-Deployment

1. **SSH Access**: Ensure you have SSH access to both servers
2. **SSH Keys**: Set up SSH key authentication (recommended):
   ```bash
   ssh-copy-id root@<host1-ip>
   ssh-copy-id root@<host2-ip>
   ```
3. **Directory Permissions**: Ensure the SSH user has write access to the working directory
4. **Network Connectivity**: Servers must be reachable from your local machine

## Files Deployed

The script automatically deploys:
- `docker-compose-host1.yml` → Host 1
- `docker-compose-host2.yml` → Host 2
- `galera-prd1.cnf` → Host 1
- `galera-prd2.cnf` → Host 2
- `.env` → Both hosts
- `init-scripts/` directory → Both hosts

## Directory Structure Created

On each remote server:
```
/data/docker_configs/mariadb_galera/
├── docker-compose-host*.yml
├── galera-prd*.cnf
├── .env
├── init-scripts/
│   ├── 01-create-sst-user.sql
│   └── 02-create-test-data.sql
├── logs/
└── data/
```

## Permissions Set

- Configuration files (*.cnf, .env): `640`
- Docker Compose files: `644`
- Init scripts (*.sql): `640`
- Init scripts directory: `750`
- Working directory: `750`

## Error Handling

The script includes robust error handling:
- Ping check before deployment
- Confirmation prompts if server is unreachable
- Error messages for failed operations
- Graceful fallback to manual instructions

## Customization

To customize the working directory or SSH user, edit the top of `setup-cluster.sh`:

```bash
# Configuration - Working directory on remote servers
WORKDIR="/your/custom/path"
SSH_USER="${SSH_USER:-your_username}"
```

## Example Output

```
✅ Configuration files updated successfully!

Do you want to automatically deploy files to the servers via SCP?
...
Deploy automatically? (y/n): y

Starting automatic deployment...

Deploying to Host1 (192.168.1.100)...
Creating directory structure on Host1...
Copying files to Host1...
Setting permissions on Host1...
✅ Deployment to Host1 completed!

✅ Host 1 deployment successful!
To start the primary node on Host 1:
ssh root@192.168.1.100 'cd /data/docker_configs/mariadb_galera && docker compose -f docker-compose-host1.yml up -d'

...

🎉 Setup complete!
```
