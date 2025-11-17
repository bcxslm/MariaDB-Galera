#!/bin/bash

# MariaDB Galera Cluster Setup Script
# This script helps configure the cluster with proper IP addresses

set -e

echo "=== MariaDB Galera Cluster Setup ==="
echo

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

echo
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

# Update docker-compose files
sed -i "s/HOST1_IP/$HOST1_IP/g" docker-compose-host1.yml
sed -i "s/HOST2_IP/$HOST2_IP/g" docker-compose-host1.yml

sed -i "s/HOST1_IP/$HOST1_IP/g" docker-compose-host2.yml
sed -i "s/HOST2_IP/$HOST2_IP/g" docker-compose-host2.yml

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
echo "Next steps for your environment:"
echo "1. Copy files to srv042036:/data/docker_configs/mariadb_galera/"
echo "   - docker-compose-host1.yml, galera-prd1.cnf, .env, init-scripts/"
echo "2. Copy files to srv042037:/data/docker_configs/mariadb_galera/"
echo "   - docker-compose-host2.yml, galera-prd2.cnf, .env, init-scripts/"
echo "3. On srv042036, run: docker compose -f docker-compose-host1.yml up -d"
echo "4. Wait for srv042036 to fully initialize"
echo "5. On srv042037, run: docker compose -f docker-compose-host2.yml up -d"
echo
echo "To verify the cluster is working:"
echo "docker exec -it mariadb-galera-prd1 mysql -u root -p -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\""
echo
echo "The cluster size should show '2' when both nodes are connected."
echo
echo "See DEPLOYMENT.md for detailed deployment instructions."
