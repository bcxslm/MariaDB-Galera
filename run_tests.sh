#!/bin/bash

# MariaDB Galera Cluster Test Runner
# This script sets up the test environment and runs the cluster tests

set -e

echo "🚀 MariaDB Galera Cluster Test Runner"
echo "======================================"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📥 Installing test dependencies..."
pip install -r tests/requirements.txt

# Check if .prd2.env exists
if [ ! -f ".prd2.env" ]; then
    echo "❌ Error: .prd2.env file not found!"
    echo "Please ensure your environment file exists."
    exit 1
fi

echo "🧪 Running cluster tests..."
echo "=========================="

# Run tests with different options
echo ""
echo "Option 1: Run with pytest (detailed output)"
echo "python -m pytest tests/test_galera_cluster.py -v"
echo ""
echo "Option 2: Run directly (custom output)"
echo "python tests/test_galera_cluster.py"
echo ""

# Ask user which option to run
read -p "Choose option (1 or 2): " choice

case $choice in
    1)
        echo "Running with pytest..."
        python -m pytest tests/test_galera_cluster.py -v
        ;;
    2)
        echo "Running directly..."
        python tests/test_galera_cluster.py
        ;;
    *)
        echo "Invalid choice. Running with pytest..."
        python -m pytest tests/test_galera_cluster.py -v
        ;;
esac

echo ""
echo "✅ Test execution completed!"
echo "Deactivating virtual environment..."
deactivate
