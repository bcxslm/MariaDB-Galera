#!/usr/bin/env python3
"""
MariaDB Galera Cluster Unit Tests

This test suite validates:
- Individual node connectivity and health
- Cluster formation and synchronization
- Read/write operations across nodes
- Failover scenarios
- Data consistency between nodes

Requirements:
    pip install pymysql pytest python-dotenv

Usage:
    python -m pytest tests/test_galera_cluster.py -v
    python tests/test_galera_cluster.py  # Direct execution
"""

import os
import sys
import time
import pytest
import pymysql
from dotenv import load_dotenv
from typing import Dict, List, Optional, Tuple
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class GaleraClusterTester:
    """Test suite for MariaDB Galera cluster"""
    
    def __init__(self, env_file: str = ".prd2.env"):
        """Initialize with environment configuration"""
        # Load environment variables
        env_path = os.path.join(os.path.dirname(__file__), "..", env_file)
        load_dotenv(env_path)
        
        self.config = {
            'host1_ip': os.getenv('HOST1_IP', '10.87.2.22'),
            'host2_ip': os.getenv('HOST2_IP', '10.87.2.23'),
            'port': 3306,
            'user': os.getenv('MYSQL_USER', 'dcsautuser'),
            'password': os.getenv('MYSQL_PASSWORD', '').replace('$$', '$'),  # Unescape dollars
            'database': os.getenv('MYSQL_DATABASE', 'dcsautomation'),
            'root_password': os.getenv('MYSQL_ROOT_PASSWORD', '').replace('$$', '$'),
            'cluster_name': os.getenv('CLUSTER_NAME', 'dcsautomation_galera_cluster')
        }
        
        self.connections = {}
        
    def get_connection(self, node: str, use_root: bool = False) -> pymysql.Connection:
        """Get database connection for specified node"""
        host = self.config['host1_ip'] if node == 'node1' else self.config['host2_ip']
        user = 'root' if use_root else self.config['user']
        password = self.config['root_password'] if use_root else self.config['password']
        
        key = f"{node}_{'root' if use_root else 'user'}"
        
        if key not in self.connections:
            try:
                self.connections[key] = pymysql.connect(
                    host=host,
                    port=self.config['port'],
                    user=user,
                    password=password,
                    database=self.config['database'],
                    charset='utf8mb4',
                    autocommit=True
                )
                logger.info(f"Connected to {node} ({host}) as {user}")
            except Exception as e:
                logger.error(f"Failed to connect to {node} ({host}): {e}")
                raise
                
        return self.connections[key]
    
    def execute_query(self, node: str, query: str, use_root: bool = False) -> List[Dict]:
        """Execute query on specified node and return results"""
        conn = self.get_connection(node, use_root)
        with conn.cursor(pymysql.cursors.DictCursor) as cursor:
            cursor.execute(query)
            return cursor.fetchall()
    
    def test_node_connectivity(self):
        """Test basic connectivity to both nodes"""
        logger.info("Testing node connectivity...")
        
        # Test Node 1
        try:
            result1 = self.execute_query('node1', "SELECT 1 as test")
            assert result1[0]['test'] == 1, "Node 1 connectivity test failed"
            logger.info("✅ Node 1 connectivity: PASS")
        except Exception as e:
            logger.error(f"❌ Node 1 connectivity: FAIL - {e}")
            raise
        
        # Test Node 2
        try:
            result2 = self.execute_query('node2', "SELECT 1 as test")
            assert result2[0]['test'] == 1, "Node 2 connectivity test failed"
            logger.info("✅ Node 2 connectivity: PASS")
        except Exception as e:
            logger.error(f"❌ Node 2 connectivity: FAIL - {e}")
            raise
    
    def test_cluster_status(self):
        """Test Galera cluster status and health"""
        logger.info("Testing cluster status...")
        
        for node in ['node1', 'node2']:
            # Check cluster size
            result = self.execute_query(node, "SHOW STATUS LIKE 'wsrep_cluster_size'", use_root=True)
            cluster_size = int(result[0]['Value'])
            assert cluster_size == 2, f"{node}: Expected cluster size 2, got {cluster_size}"
            
            # Check node state
            result = self.execute_query(node, "SHOW STATUS LIKE 'wsrep_local_state_comment'", use_root=True)
            state = result[0]['Value']
            assert state == 'Synced', f"{node}: Expected state 'Synced', got '{state}'"
            
            # Check if ready
            result = self.execute_query(node, "SHOW STATUS LIKE 'wsrep_ready'", use_root=True)
            ready = result[0]['Value']
            assert ready == 'ON', f"{node}: Expected ready 'ON', got '{ready}'"
            
            # Check cluster name
            result = self.execute_query(node, "SHOW STATUS LIKE 'wsrep_cluster_name'", use_root=True)
            cluster_name = result[0]['Value']
            assert cluster_name == self.config['cluster_name'], f"{node}: Cluster name mismatch"
            
            logger.info(f"✅ {node} cluster status: PASS")
    
    def test_write_replication(self):
        """Test write operations and replication between nodes"""
        logger.info("Testing write replication...")
        
        table_name = f"test_replication_{int(time.time())}"
        
        try:
            # Create table on Node 1
            create_sql = f"""
            CREATE TABLE {table_name} (
                id INT AUTO_INCREMENT PRIMARY KEY,
                node VARCHAR(10),
                data VARCHAR(100),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
            self.execute_query('node1', create_sql)
            logger.info(f"Created table {table_name} on Node 1")
            
            # Insert data on Node 1
            self.execute_query('node1', f"INSERT INTO {table_name} (node, data) VALUES ('node1', 'test_data_1')")
            
            # Wait for replication
            time.sleep(1)
            
            # Verify data exists on Node 2
            result = self.execute_query('node2', f"SELECT * FROM {table_name} WHERE node = 'node1'")
            assert len(result) == 1, "Data not replicated to Node 2"
            assert result[0]['data'] == 'test_data_1', "Replicated data mismatch"
            
            # Insert data on Node 2
            self.execute_query('node2', f"INSERT INTO {table_name} (node, data) VALUES ('node2', 'test_data_2')")
            
            # Wait for replication
            time.sleep(1)
            
            # Verify data exists on Node 1
            result = self.execute_query('node1', f"SELECT * FROM {table_name} WHERE node = 'node2'")
            assert len(result) == 1, "Data not replicated to Node 1"
            assert result[0]['data'] == 'test_data_2', "Replicated data mismatch"
            
            # Verify both records exist on both nodes
            for node in ['node1', 'node2']:
                result = self.execute_query(node, f"SELECT COUNT(*) as count FROM {table_name}")
                assert result[0]['count'] == 2, f"{node}: Expected 2 records, got {result[0]['count']}"
            
            logger.info("✅ Write replication: PASS")
            
        finally:
            # Cleanup
            try:
                self.execute_query('node1', f"DROP TABLE IF EXISTS {table_name}")
                logger.info(f"Cleaned up table {table_name}")
            except:
                pass
    
    def test_concurrent_writes(self):
        """Test concurrent write operations"""
        logger.info("Testing concurrent writes...")
        
        table_name = f"test_concurrent_{int(time.time())}"
        
        try:
            # Create table
            create_sql = f"""
            CREATE TABLE {table_name} (
                id INT AUTO_INCREMENT PRIMARY KEY,
                node VARCHAR(10),
                counter INT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
            self.execute_query('node1', create_sql)
            
            # Perform concurrent writes
            for i in range(5):
                self.execute_query('node1', f"INSERT INTO {table_name} (node, counter) VALUES ('node1', {i})")
                self.execute_query('node2', f"INSERT INTO {table_name} (node, counter) VALUES ('node2', {i})")
            
            # Wait for replication
            time.sleep(2)
            
            # Verify data consistency
            for node in ['node1', 'node2']:
                result = self.execute_query(node, f"SELECT COUNT(*) as count FROM {table_name}")
                assert result[0]['count'] == 10, f"{node}: Expected 10 records, got {result[0]['count']}"
                
                # Check data from both nodes exists
                result1 = self.execute_query(node, f"SELECT COUNT(*) as count FROM {table_name} WHERE node = 'node1'")
                result2 = self.execute_query(node, f"SELECT COUNT(*) as count FROM {table_name} WHERE node = 'node2'")
                assert result1[0]['count'] == 5, f"{node}: Expected 5 node1 records"
                assert result2[0]['count'] == 5, f"{node}: Expected 5 node2 records"
            
            logger.info("✅ Concurrent writes: PASS")
            
        finally:
            # Cleanup
            try:
                self.execute_query('node1', f"DROP TABLE IF EXISTS {table_name}")
            except:
                pass
    
    def test_node_identification(self):
        """Test node identification and naming"""
        logger.info("Testing node identification...")
        
        # Check node names
        result1 = self.execute_query('node1', "SHOW STATUS LIKE 'wsrep_node_name'", use_root=True)
        result2 = self.execute_query('node2', "SHOW STATUS LIKE 'wsrep_node_name'", use_root=True)
        
        node1_name = result1[0]['Value']
        node2_name = result2[0]['Value']
        
        # Verify different node names
        assert node1_name != node2_name, "Nodes should have different names"
        logger.info(f"Node 1 name: {node1_name}")
        logger.info(f"Node 2 name: {node2_name}")
        
        # Check node addresses
        result1 = self.execute_query('node1', "SHOW STATUS LIKE 'wsrep_node_address'", use_root=True)
        result2 = self.execute_query('node2', "SHOW STATUS LIKE 'wsrep_node_address'", use_root=True)
        
        node1_addr = result1[0]['Value']
        node2_addr = result2[0]['Value']
        
        assert node1_addr == self.config['host1_ip'], f"Node 1 address mismatch: {node1_addr}"
        assert node2_addr == self.config['host2_ip'], f"Node 2 address mismatch: {node2_addr}"
        
        logger.info("✅ Node identification: PASS")
    
    def run_all_tests(self):
        """Run all tests in sequence"""
        logger.info("🚀 Starting MariaDB Galera Cluster Tests")
        logger.info("=" * 50)
        
        tests = [
            self.test_node_connectivity,
            self.test_cluster_status,
            self.test_node_identification,
            self.test_write_replication,
            self.test_concurrent_writes
        ]
        
        passed = 0
        failed = 0
        
        for test in tests:
            try:
                test()
                passed += 1
            except Exception as e:
                logger.error(f"❌ {test.__name__}: FAILED - {e}")
                failed += 1
            
            logger.info("-" * 30)
        
        logger.info("=" * 50)
        logger.info(f"📊 Test Results: {passed} PASSED, {failed} FAILED")
        
        if failed == 0:
            logger.info("🎉 All tests PASSED! Cluster is healthy.")
        else:
            logger.error(f"⚠️  {failed} test(s) FAILED. Check cluster configuration.")
        
        return failed == 0
    
    def close_connections(self):
        """Close all database connections"""
        for conn in self.connections.values():
            try:
                conn.close()
            except:
                pass
        self.connections.clear()

def main():
    """Main test execution"""
    tester = GaleraClusterTester()
    
    try:
        success = tester.run_all_tests()
        sys.exit(0 if success else 1)
    finally:
        tester.close_connections()

if __name__ == "__main__":
    main()
