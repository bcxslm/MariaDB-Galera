#!/bin/bash

# MariaDB Galera Cluster Setup Script
# This script helps configure the cluster with proper IP addresses

set -e

echo "=== MariaDB Galera Cluster Setup ==="
echo

# Configuration - Working directory on remote servers
WORKDIR="/opt/mariadb_galera"
SSH_USER="${SSH_USER:-root}"
COMPOSE_DEFAULT="docker compose"

# Use docker or podman?
read -p "Use docker or podman? (docker/podman)[default: docker]: " container_engine
if [[ $container_engine == "podman" ]]; then
    COMPOSE_EXEC="podman-compose"
else
    COMPOSE_EXEC="$COMPOSE_DEFAULT"
fi

# Configure Bootstrap Flags
read -p "Do you want to configure bootstrap flags? (y/n): " configure_bootstrap
if [[ $configure_bootstrap == [yY] ]]; then
    info "Configuring bootstrap flags..."
    sed -i "s/^BOOTSTRAP_NODE1=.*/BOOTSTRAP_NODE1=yes/" .env
    sed -i "s/^BOOTSTRAP_NODE2=.*/BOOTSTRAP_NODE2=/" .env
    ok "Bootstrap flags set (Host1=yes, Host2 empty)"
elif [[ $configure_bootstrap == [nN] ]]; then
    info "Skipping bootstrap flag configuration..."
    sed -i "s/^BOOTSTRAP_NODE1=.*/BOOTSTRAP_NODE1=/" .env
    sed -i "s/^BOOTSTRAP_NODE2=.*/BOOTSTRAP_NODE2=/" .env
fi


# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Get IP addresses from user
echo "Please enter the IP addresses for your cluster nodes:"
echo

while true; do
    read -p "Host 1 IP address: " HOST1_IP
    if validate_ip "$HOST1_IP"; then
        break
    else
        echo "Invalid IP address format. Please try again."
    fi
done

while true; do
    read -p "Host 2 IP address: " HOST2_IP
    if validate_ip "$HOST2_IP"; then
        break
    else
        echo "Invalid IP address format. Please try again."
    fi
done

echo
echo "Configuration Summary:"
echo "Host 1 IP: $HOST1_IP"
echo "Host 2 IP: $HOST2_IP"
echo

read -p "Is this correct? (y/n): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Setup cancelled."
    exit 1
fi

echo "Updating configuration files..."

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s/192.168.1.100/$HOST1_IP/g" .env
    sed -i "s/192.168.1.101/$HOST2_IP/g" .env
    echo "Created .env file with your IP addresses."
fi

# Source .env file to get credentials
source .env

# Set default values if not provided in .env
SST_USER=${SST_USER:-sst_user}
SST_PASSWORD=${SST_PASSWORD:-sst_password}

# Update galera-prd1.cnf
sed -i "s/HOST1_IP/$HOST1_IP/g" galera-prd1.cnf
sed -i "s/HOST2_IP/$HOST2_IP/g" galera-prd1.cnf
sed -i "s/SST_USER_PLACEHOLDER/$SST_USER/g" galera-prd1.cnf
sed -i "s/SST_PASSWORD_PLACEHOLDER/$SST_PASSWORD/g" galera-prd1.cnf

# Update galera-prd2.cnf
sed -i "s/HOST1_IP/$HOST1_IP/g" galera-prd2.cnf
sed -i "s/HOST2_IP/$HOST2_IP/g" galera-prd2.cnf
sed -i "s/SST_USER_PLACEHOLDER/$SST_USER/g" galera-prd2.cnf
sed -i "s/SST_PASSWORD_PLACEHOLDER/$SST_PASSWORD/g" galera-prd2.cnf

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s/192.168.1.100/$HOST1_IP/g" .env
    sed -i "s/192.168.1.101/$HOST2_IP/g" .env
    echo "Created .env file with your IP addresses."
fi

# Generate initialization scripts with environment variables
echo "Generating initialization scripts..."
chmod +x generate-init-scripts.sh
./generate-init-scripts.sh

echo
echo "✅ Configuration files updated successfully!"
echo

# Function to deploy files to a server
deploy_to_server() {
    local server_ip=$1
    local server_name=$2
    local compose_file=$3
    local config_file=$4

    echo "Deploying to $server_name ($server_ip)..."

    # Check if we can connect to the server
    if ! ping -c 1 "$server_ip" &> /dev/null; then
        echo "⚠️  Warning: Cannot ping $server_ip. Please ensure the server is accessible."
        read -p "Continue anyway? (y/n): " continue_deploy
        if [[ $continue_deploy != [yY] ]]; then
            return 1
        fi
    fi

    # Create directory structure on remote server
    echo "Creating directory structure on $server_name..."
    ssh "$SSH_USER@$server_ip" "mkdir -p $WORKDIR/{init-scripts,logs,data,conf} && \
                         chmod -R 750 $WORKDIR" || {
        echo "❌ Failed to create directories on $server_name"
        return 1
    }

    # Copy files to server
    echo "Copying files to $server_name..."
    scp "$compose_file" "$SSH_USER@$server_ip:$WORKDIR/docker-compose.yml" || {
        echo "❌ Failed to copy docker-compose file to $server_name"
        return 1
    }
    scp "$config_file" "$SSH_USER@$server_ip:$WORKDIR/conf" || {
        echo "❌ Failed to copy config file to $server_name"
        return 1
    }
    scp .env "$SSH_USER@$server_ip:$WORKDIR/" || {
        echo "❌ Failed to copy .env file to $server_name"
        return 1
    }
    scp -r init-scripts "$SSH_USER@$server_ip:$WORKDIR/" || {
        echo "❌ Failed to copy init-scripts to $server_name"
        return 1
    }

    # Set proper permissions
    echo "Setting permissions on $server_name..."
    ssh "$SSH_USER@$server_ip" "cd $WORKDIR && \
                         chown -R 999:999 data logs init-scripts conf && \
                         chmod 640 conf/*.cnf .env && \
                         chmod 644 docker-compose*.yml && \
                         chmod 640 init-scripts/*.sql && \
                         chmod 750 init-scripts" || {
        echo "⚠️  Warning: Failed to set some permissions on $server_name"
    }

    echo "✅ Deployment to $server_name completed!"
    return 0
}

# Ask if user wants to deploy automatically
echo "Do you want to automatically deploy files to the servers via SCP?"
echo "This requires:"
echo "1. SSH access to both servers as user '$SSH_USER'"
echo "2. Write access to $WORKDIR directory"
echo "3. SSH key authentication (recommended)"
echo
echo "Working directory on servers: $WORKDIR"
echo

read -p "Deploy automatically? (y/n): " auto_deploy

if [[ $auto_deploy == [yY] ]]; then
    echo
    echo "Starting automatic deployment..."
    echo

    # Deploy to Host 1
    if deploy_to_server "$HOST1_IP" "Host1" "docker-compose-host1.yml" "galera-prd1.cnf"; then
        echo
        echo "✅ Host 1 deployment successful!"
        echo "To start the primary node on Host 1:"
        echo "ssh $SSH_USER@$HOST1_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
        ssh $SSH_USER@$HOST1_IP "cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d"
    else
        echo "❌ Host 1 deployment failed!"
    fi

    echo "Pausing for 10 seconds before deploying to Host 2..."
    sleep 10

    # Deploy to Host 2
    if deploy_to_server "$HOST2_IP" "Host2" "docker-compose-host2.yml" "galera-prd2.cnf"; then
        echo
        echo "✅ Host 2 deployment successful!"
        echo "To start the secondary node on Host 2 (after primary is running):"
        echo "ssh $SSH_USER@$HOST2_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
        ssh $SSH_USER@$HOST2_IP "cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d"
    else
        echo "❌ Host 2 deployment failed!"
    fi

    echo
    echo "Next steps after deployment:"
    echo "1. Start primary node: ssh $SSH_USER@$HOST1_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
    echo "2. Wait for primary to initialize (check logs)"
    echo "3. Start secondary node: ssh $SSH_USER@$HOST2_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
    echo "4. Verify cluster: ssh $SSH_USER@$HOST1_IP 'docker exec -it mariadb-galera-prd1 mysql -u root -p -e \"SHOW STATUS LIKE \\\"wsrep_cluster_size\\\";\"'"

else
    echo
    echo "Manual deployment instructions:"
    echo
    echo "Next steps for your environment:"
    echo "0. Set selinux to permissive: setenforce 0"
    echo "1. Copy files to $HOST1_IP:$WORKDIR/"
    echo "   - docker-compose-host1.yml, galera-prd1.cnf, .env, init-scripts/"
    echo "2. Copy files to $HOST2_IP:$WORKDIR/"
    echo "   - docker-compose-host2.yml, galera-prd2.cnf, .env, init-scripts/"
    echo "3. On Host 1, run: $COMPOSE_EXEC -f docker-compose-host1.yml up -d"
    echo "4. Wait for Host 1 to fully initialize"
    echo "5. On Host 2, run: $COMPOSE_EXEC -f docker-compose-host2.yml up -d"
    echo
    echo "To verify the cluster is working:"
    echo "$COMPOSE_EXEC exec -it mariadb-galera-prd1 mysql -u root -p -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\""
    echo
    echo "The cluster size should show '2' when both nodes are connected."
fi

echo
echo "See DEPLOYMENT.md for detailed deployment instructions."
echo
echo "🎉 Setup complete!"
