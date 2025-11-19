#!/bin/bash
################################################################################
# MariaDB Galera Cluster Test Environment Cleaner
################################################################################
# Purpose: Clean up test environment after running tests
# Usage: Run this script after tests to clean up test environment
# Author: DCS Automation Team
# Date: 2025-11-17
################################################################################

set -e

echo "Will clean up test environment after 5s , Ctrl+C to cancel"
sleep 5

source ../.env

ssh $USER@$HOST1_IP "cd $WORKDIR && $COMPOSE_EXEC down -v && rm -rf *"
ssh $USER@$HOST2_IP "cd $WORKDIR && $COMPOSE_EXEC down -v && rm -rf *"
