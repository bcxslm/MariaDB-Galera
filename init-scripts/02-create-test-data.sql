-- Create a test database and table to verify cluster replication
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

-- Create a test table
CREATE TABLE IF NOT EXISTS cluster_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_name VARCHAR(50) NOT NULL,
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert initial test data
INSERT INTO cluster_test (node_name, message) VALUES 
('initialization', 'Cluster initialized successfully'),
('setup', 'Test table created for replication testing');

-- Create an index for better performance
CREATE INDEX idx_node_name ON cluster_test(node_name);
CREATE INDEX idx_created_at ON cluster_test(created_at);

-- Show the created table structure
DESCRIBE cluster_test;

-- Show initial data
SELECT * FROM cluster_test;
