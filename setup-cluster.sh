#!/bin/bash

# MariaDB Galera Cluster Setup Script
# This script helps configure the cluster with proper IP addresses

set -e

# -----------------------------
# Helpers
# -----------------------------
info(){ echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok(){ echo -e "\033[1;32m[OK]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err(){ echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

info "=== MariaDB Galera Cluster Setup ==="

# Configuration - Working directory on remote servers
WORKDIR="/opt/mariadb_galera"
SSH_USER="${SSH_USER:-root}"
COMPOSE_DEFAULT="docker compose"

generate_password() {
    # 20 chars with symbols, letters, digits
    LC_ALL=C tr -dc 'A-Za-z0-9-_=' </dev/urandom | head -c 16 || echo "P@ssw0rdi23hsb78go"
}

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    echo "WORKDIR=$WORKDIR" >> .env
    echo "SSH_USER=$SSH_USER" >> .env
    ok "Created .env file with your IP addresses."
fi

read -p "The cluster name [default: galera_cluster]: " CLUSTER_NAME
read -p "The root password [default: random]: " MYSQL_ROOT_PASSWORD
read -p "The database user [default: galera_user]: " MYSQL_USER
read -p "The database user password [default: random]: " MYSQL_PASSWORD
read -p "The database name [default: test]: " MYSQL_DATABASE


# Use docker or podman?
read -p "Use docker or podman? (docker/podman)[default: docker]: " container_engine
if [[ $container_engine == "podman" ]]; then
    COMPOSE_EXEC="podman-compose"
    info "Using podman-compose"
    echo "COMPOSE_EXEC=$COMPOSE_EXEC" >> .env
else
    COMPOSE_EXEC="$COMPOSE_DEFAULT"
    info "Using docker compose"
    echo "COMPOSE_EXEC=$COMPOSE_EXEC" >> .env
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
info "Please enter the IP addresses for your cluster nodes:"

while true; do
    read -p "Host 1 IP address: " HOST1_IP
    if validate_ip "$HOST1_IP"; then
        break
    else
        err "Invalid IP address format. Please try again."
    fi
done

while true; do
    read -p "Host 2 IP address: " HOST2_IP
    if validate_ip "$HOST2_IP"; then
        break
    else
        err "Invalid IP address format. Please try again."
    fi
done

# Set default values if not provided in .env
CLUSTER_NAME=${CLUSTER_NAME:-galera_cluster}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-$(generate_password)}
MYSQL_USER=${MYSQL_USER:-galera_cluster}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-$(generate_password)}
MYSQL_DATABASE=${MYSQL_DATABASE:-test}
SST_PASSWORD=${SST_PASSWORD:-$(generate_password)}
MONITOR_PASSWORD=${MONITOR_PASSWORD:-$(generate_password)}
REPL_PASSWORD=${REPL_PASSWORD:-$(generate_password)}

info "Configuration Summary:"
echo "Cluster Name: $CLUSTER_NAME"
echo "Root Password: $MYSQL_ROOT_PASSWORD"
echo "Database User: $MYSQL_USER"
echo "Database Password: $MYSQL_PASSWORD"
echo "Database Name: $MYSQL_DATABASE"
echo "SST Password: $SST_PASSWORD"
echo "Monitor Password: $MONITOR_PASSWORD"
echo "Replication Password: $REPL_PASSWORD"
echo "Host 1 IP: $HOST1_IP"
echo "Host 2 IP: $HOST2_IP"

read -p "Is this correct? (y/n): " confirm
if [[ $confirm != [yY] ]]; then
    warn "Setup cancelled."
    exit 1
fi

info "Updating configuration files..."
sed -i "s/__CLUSTER_NAME_PLACEHOLDER__/$CLUSTER_NAME/g" .env
sed -i "s/__MYSQL_ROOT_PASSWORD_PLACEHOLDER__/$MYSQL_ROOT_PASSWORD/g" .env
sed -i "s/__MYSQL_USER_PLACEHOLDER__/$MYSQL_USER/g" .env
sed -i "s/__MYSQL_PASSWORD_PLACEHOLDER__/$MYSQL_PASSWORD/g" .env
sed -i "s/__MYSQL_DATABASE_PLACEHOLDER__/$MYSQL_DATABASE/g" .env
sed -i "s/__SST_PASSWORD_PLACEHOLDER__/$SST_PASSWORD/g" .env
sed -i "s/__MONITOR_PASSWORD_PLACEHOLDER__/$MONITOR_PASSWORD/g" .env
sed -i "s/__REPL_PASSWORD_PLACEHOLDER__/$REPL_PASSWORD/g" .env
sed -i "s/__HOST1_IP_PLACEHOLDER__/$HOST1_IP/g" .env
sed -i "s/__HOST2_IP_PLACEHOLDER__/$HOST2_IP/g" .env
ok "✅ Updated .env file with IP addresses."

# Source .env file to get credentials
source .env

# Generate initialization scripts with environment variables
info "Generating initialization scripts..."
chmod +x generate-init-scripts.sh
./generate-init-scripts.sh

echo
ok "✅ Configuration files updated successfully!"
echo

# Function to deploy files to a server
deploy_to_server() {
    local server_ip=$1
    local server_name=$2
    local compose_file=$3
    local config_file=$4

    info "Deploying to $server_name ($server_ip)..."

    # Check if we can connect to the server
    if ! ping -c 1 "$server_ip" &> /dev/null; then
        warn "⚠️  Warning: Cannot ping $server_ip. Please ensure the server is accessible."
        read -p "Continue anyway? (y/n): " continue_deploy
        if [[ $continue_deploy != [yY] ]]; then
            return 1
        fi
    fi

    # Create directory structure on remote server
    info "Creating directory structure on $server_name..."
    ssh "$SSH_USER@$server_ip" "mkdir -p $WORKDIR/{init-scripts,logs,data,conf} && \
                         chmod -R 750 $WORKDIR" || {
        err "❌ Failed to create directories on $server_name"
        return 1
    }

    # Copy files to server
    info "Copying files to $server_name..."
    scp "$compose_file" "$SSH_USER@$server_ip:$WORKDIR/docker-compose.yml" || {
        err "❌ Failed to copy docker-compose file to $server_name"
        return 1
    }
    scp "$config_file" "$SSH_USER@$server_ip:$WORKDIR/conf" || {
        err "❌ Failed to copy config file to $server_name"
        return 1
    }
    scp .env "$SSH_USER@$server_ip:$WORKDIR/" || {
        err "❌ Failed to copy .env file to $server_name"
        return 1
    }
    scp -r init-scripts "$SSH_USER@$server_ip:$WORKDIR/" || {
        err "❌ Failed to copy init-scripts to $server_name"
        return 1
    }

    # Set proper permissions
    info "Setting permissions on $server_name..."
    ssh "$SSH_USER@$server_ip" "cd $WORKDIR && \
                         chown -R 999:999 data logs init-scripts conf && \
                         chmod 640 conf/*.cnf .env && \
                         chmod 644 docker-compose*.yml && \
                         chmod 640 init-scripts/*.sql && \
                         chmod 750 init-scripts" || {
        warn "⚠️  Warning: Failed to set some permissions on $server_name"
    }

    ok "✅ Deployment to $server_name completed!"
    return 0
}

# Ask if user wants to deploy automatically
info "Do you want to automatically deploy files to the servers via SCP?"
info "This requires:"
info "1. SSH access to both servers as user '$SSH_USER'"
info "2. Write access to $WORKDIR directory"
info "3. SSH key authentication (recommended)"
info "Working directory on servers: $WORKDIR"

read -p "Deploy automatically? (y/n): " auto_deploy

if [[ $auto_deploy == [yY] ]]; then
    info "Starting automatic deployment..."

    # Deploy to Host 1
    if deploy_to_server "$HOST1_IP" "Host1" "docker-compose-host1.yml" "galera-prd1.cnf"; then
        ok "✅ Host 1 deployment successful!"
        info "To start the primary node on Host 1:"
        info "ssh $SSH_USER@$HOST1_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
        ssh $SSH_USER@$HOST1_IP "cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d"
    else
        err "❌ Host 1 deployment failed!"
    fi

    info "Pausing for 10 seconds before deploying to Host 2..."
    sleep 10

    # Deploy to Host 2
    if deploy_to_server "$HOST2_IP" "Host2" "docker-compose-host2.yml" "galera-prd2.cnf"; then
        ok "✅ Host 2 deployment successful!"
        info "To start the secondary node on Host 2 (after primary is running):"
        info "ssh $SSH_USER@$HOST2_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
        ssh $SSH_USER@$HOST2_IP "cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d"
    else
        err "❌ Host 2 deployment failed!"
    fi

    info "Remove bootstrap flag from both nodes after initial startup:"
    info "ssh $SSH_USER@$HOST1_IP 'cd $WORKDIR && sed -i \"s/BOOTSTRAP_NODE1=yes/BOOTSTRAP_NODE1=/\" .env'"
    info "ssh $SSH_USER@$HOST2_IP 'cd $WORKDIR && sed -i \"s/BOOTSTRAP_NODE2=yes/BOOTSTRAP_NODE2=/\" .env'"
    ssh $SSH_USER@$HOST1_IP "cd $WORKDIR && sed -i 's/BOOTSTRAP_NODE1=yes/BOOTSTRAP_NODE1=/' .env"
    ssh $SSH_USER@$HOST2_IP "cd $WORKDIR && sed -i 's/BOOTSTRAP_NODE2=yes/BOOTSTRAP_NODE2=/' .env"

    info "Next steps after deployment:"
    info "1. Start primary node: ssh $SSH_USER@$HOST1_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
    info "2. Wait for primary to initialize (check logs)"
    info "3. Start secondary node: ssh $SSH_USER@$HOST2_IP 'cd $WORKDIR && $COMPOSE_EXEC -f docker-compose.yml up -d'"
    info "4. Verify cluster: ssh $SSH_USER@$HOST1_IP 'docker exec -it mariadb-galera-prd1 mysql -u mariadb -p -e \"SHOW STATUS LIKE \\\"wsrep_cluster_size\\\";\"'"

else
    info "Manual deployment instructions:"
    info "Next steps for your environment:"
    info "0. Set selinux to permissive: setenforce 0"
    info "1. Copy files to $HOST1_IP:$WORKDIR/"
    info "   - docker-compose-host1.yml, galera-prd1.cnf, .env, init-scripts/"
    info "2. Copy files to $HOST2_IP:$WORKDIR/"
    info "   - docker-compose-host2.yml, galera-prd2.cnf, .env, init-scripts/"
    info "3. On Host 1, run: $COMPOSE_EXEC -f docker-compose-host1.yml up -d"
    info "4. Wait for Host 1 to fully initialize"
    info "5. On Host 2, run: $COMPOSE_EXEC -f docker-compose-host2.yml up -d"
    info "To verify the cluster is working:"
    info "$COMPOSE_EXEC exec -it mariadb-galera-prd1 mysql -u mariadb -p -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\""
    info "The cluster size should show '2' when both nodes are connected."
    info "Remove bootstrap flag from both nodes after initial startup:"
    info "sed -i 's/BOOTSTRAP_NODE1=yes/BOOTSTRAP_NODE1=/' .env"
    info "sed -i 's/BOOTSTRAP_NODE2=yes/BOOTSTRAP_NODE2=/' .env"
fi

info "See DEPLOYMENT.md for detailed deployment instructions."
info "🎉 Setup complete!"
