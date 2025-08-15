#!/bin/bash

# MariaDB Galera Cluster Deployment Script
# This script helps deploy the cluster configuration to your servers

set -e

echo "=== MariaDB Galera Cluster Deployment Script ==="
echo

# Configuration - UPDATE THESE VALUES FOR YOUR ENVIRONMENT
SRV1="your-host1-name"
SRV2="your-host2-name"
CONFIG_PATH="/path/to/your/config/directory"
USER="your-deployment-user"

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

# Get IP addresses
echo "Please enter the IP addresses for your servers:"
echo

while true; do
    read -p "$SRV1 IP address: " SRV1_IP
    if validate_ip "$SRV1_IP"; then
        break
    else
        echo "Invalid IP address format. Please try again."
    fi
done

while true; do
    read -p "$SRV2 IP address: " SRV2_IP
    if validate_ip "$SRV2_IP"; then
        break
    else
        echo "Invalid IP address format. Please try again."
    fi
done

echo
echo "Configuration Summary:"
echo "$SRV1 IP: $SRV1_IP"
echo "$SRV2 IP: $SRV2_IP"
echo "Config Path: $CONFIG_PATH"
echo "User: $USER"
echo

read -p "Is this correct? (y/n): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Deployment cancelled."
    exit 1
fi

echo
echo "Updating configuration files with IP addresses..."

# Create temporary copies with updated IPs
cp galera-prd1.cnf galera-prd1.cnf.tmp
cp galera-prd2.cnf galera-prd2.cnf.tmp
cp docker-compose-host1.yml docker-compose-host1.yml.tmp
cp docker-compose-host2.yml docker-compose-host2.yml.tmp

# Update IP addresses in config files
sed -i "s/HOST1_IP/$SRV1_IP/g" galera-prd1.cnf.tmp
sed -i "s/HOST2_IP/$SRV2_IP/g" galera-prd1.cnf.tmp
sed -i "s/HOST1_IP/$SRV1_IP/g" galera-prd2.cnf.tmp
sed -i "s/HOST2_IP/$SRV2_IP/g" galera-prd2.cnf.tmp

# Update docker-compose files
sed -i "s/HOST1_IP/$SRV1_IP/g" docker-compose-host1.yml.tmp
sed -i "s/HOST2_IP/$SRV2_IP/g" docker-compose-host1.yml.tmp
sed -i "s/HOST1_IP/$SRV1_IP/g" docker-compose-host2.yml.tmp
sed -i "s/HOST2_IP/$SRV2_IP/g" docker-compose-host2.yml.tmp

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s/192.168.1.100/$SRV1_IP/g" .env
    sed -i "s/192.168.1.101/$SRV2_IP/g" .env
    echo "Created .env file with your IP addresses."
fi

echo "✅ Configuration files updated successfully!"
echo

# Function to deploy to a server
deploy_to_server() {
    local server=$1
    local compose_file=$2
    local config_file=$3
    
    echo "Deploying to $server..."
    
    # Check if we can connect to the server
    if ! ping -c 1 "$server" &> /dev/null; then
        echo "⚠️  Warning: Cannot ping $server. Please ensure the server is accessible."
        read -p "Continue anyway? (y/n): " continue_deploy
        if [[ $continue_deploy != [yY] ]]; then
            return 1
        fi
    fi
    
    # Create directory structure on remote server
    echo "Creating directory structure on $server..."
    ssh "$USER@$server" "mkdir -p $CONFIG_PATH/{init-scripts,logs,data} && \
                         chmod -R 750 $CONFIG_PATH"
    
    # Copy files to server
    echo "Copying files to $server..."
    scp "$compose_file" "$USER@$server:$CONFIG_PATH/"
    scp "$config_file" "$USER@$server:$CONFIG_PATH/"
    scp .env "$USER@$server:$CONFIG_PATH/"
    scp -r init-scripts "$USER@$server:$CONFIG_PATH/"

    # Set proper permissions
    ssh "$USER@$server" "cd $CONFIG_PATH && \
                         chmod 640 *.cnf .env && \
                         chmod 644 docker-compose-*.yml && \
                         chmod 640 init-scripts/*.sql && \
                         chmod 750 init-scripts"
    
    echo "✅ Deployment to $server completed!"
    return 0
}

# Ask if user wants to deploy automatically
echo "Do you want to automatically deploy to the servers via SSH?"
echo "This requires:"
echo "1. SSH access to both servers as user '$USER'"
echo "2. Write access to $CONFIG_PATH directory"
echo "3. SSH key authentication (recommended)"
echo

read -p "Deploy automatically? (y/n): " auto_deploy

if [[ $auto_deploy == [yY] ]]; then
    echo
    echo "Starting automatic deployment..."
    
    # Deploy to Host 1
    if deploy_to_server "$SRV1" "docker-compose-host1.yml.tmp" "galera-node1.cnf.tmp"; then
        echo
        echo "To start the primary node on $SRV1:"
        echo "ssh $USER@$SRV1 'cd $CONFIG_PATH && docker compose -f docker-compose-host1.yml up -d'"
    fi

    echo

    # Deploy to Host 2
    if deploy_to_server "$SRV2" "docker-compose-host2.yml.tmp" "galera-node2.cnf.tmp"; then
        echo
        echo "To start the secondary node on $SRV2 (after primary is running):"
        echo "ssh $USER@$SRV2 'cd $CONFIG_PATH && docker compose -f docker-compose-host2.yml up -d'"
    fi
    
else
    echo
    echo "Manual deployment instructions:"
    echo
    echo "1. Copy files to $SRV1:$CONFIG_PATH/"
    echo "   - docker-compose-host1.yml.tmp (rename to docker-compose-host1.yml)"
    echo "   - galera-prd1.cnf.tmp (rename to galera-prd1.cnf)"
    echo "   - .env"
    echo "   - init-scripts/ (entire directory)"
    echo
    echo "2. Copy files to $SRV2:$CONFIG_PATH/"
    echo "   - docker-compose-host2.yml.tmp (rename to docker-compose-host2.yml)"
    echo "   - galera-node2.cnf.tmp (rename to galera-node2.cnf)"
    echo "   - .env"
    echo "   - init-scripts/ (entire directory)"
    echo
    echo "3. Set proper permissions (umask=0027):"
    echo "   chmod 640 *.cnf .env"
    echo "   chmod 644 docker-compose-*.yml"
    echo "   chmod 640 init-scripts/*.sql"
fi

echo
echo "Next steps after deployment:"
echo "1. Start primary node: ssh $USER@$SRV1 'cd $CONFIG_PATH && docker compose -f docker-compose-host1.yml up -d'"
echo "2. Wait for primary to initialize (check logs)"
echo "3. Start secondary node: ssh $USER@$SRV2 'cd $CONFIG_PATH && docker compose -f docker-compose-host2.yml up -d'"
echo "4. Verify cluster: ssh $USER@$SRV1 'docker exec -it mariadb-galera-node1 mysql -u root -p -e \"SHOW STATUS LIKE \\\"wsrep_cluster_size\\\";\"'"
echo
echo "See DEPLOYMENT.md for detailed instructions and troubleshooting."

# Cleanup temporary files
rm -f *.tmp

echo
echo "🎉 Deployment preparation complete!"
