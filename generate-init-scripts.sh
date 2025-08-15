#!/bin/bash

# Generate MariaDB initialization scripts with environment variables
# This script reads the .env file and generates SQL scripts with actual passwords

set -e

echo "Generating MariaDB initialization scripts with environment variables..."

# Source the .env file to get variables
if [ -f .env ]; then
    source .env
    echo "✅ Loaded environment variables from .env"
else
    echo "❌ .env file not found. Please create it from .env.example"
    exit 1
fi

# Set default values if not provided in .env
SST_USER=${SST_USER:-sst_user}
SST_PASSWORD=${SST_PASSWORD:-sst_password}
MONITOR_USER=${MONITOR_USER:-monitor}
MONITOR_PASSWORD=${MONITOR_PASSWORD:-monitor_password}
REPL_USER=${REPL_USER:-repl_user}
REPL_PASSWORD=${REPL_PASSWORD:-repl_password}

# Create init-scripts directory if it doesn't exist
mkdir -p init-scripts

# Generate 01-create-sst-user.sql from template
if [ -f "init-scripts/01-create-sst-user.sql.template" ]; then
    echo "Generating 01-create-sst-user.sql..."
    
    # Read template and substitute variables
    sed "s/SST_USER_PLACEHOLDER/$SST_USER/g; \
         s/SST_PASSWORD_PLACEHOLDER/$SST_PASSWORD/g; \
         s/MONITOR_USER_PLACEHOLDER/$MONITOR_USER/g; \
         s/MONITOR_PASSWORD_PLACEHOLDER/$MONITOR_PASSWORD/g; \
         s/REPL_USER_PLACEHOLDER/$REPL_USER/g; \
         s/REPL_PASSWORD_PLACEHOLDER/$REPL_PASSWORD/g" \
         init-scripts/01-create-sst-user.sql.template > init-scripts/01-create-sst-user.sql
    
    echo "✅ Generated init-scripts/01-create-sst-user.sql"
else
    echo "❌ Template file init-scripts/01-create-sst-user.sql.template not found"
    exit 1
fi

# Set proper permissions
chmod 640 init-scripts/01-create-sst-user.sql

echo
echo "✅ Initialization scripts generated successfully!"
echo
echo "Generated files:"
echo "- init-scripts/01-create-sst-user.sql (with your environment variables)"
echo
echo "Users that will be created:"
echo "- SST User: $SST_USER"
echo "- Monitor User: $MONITOR_USER" 
echo "- Replication User: $REPL_USER"
echo
echo "⚠️  Make sure to update your Galera configuration files to use these same credentials:"
echo "   wsrep_sst_auth = \"$SST_USER:$SST_PASSWORD\""
