#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MySQL Master-Slave Replication Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Step 1: Start containers
echo -e "${YELLOW}Step 1: Starting Docker containers...${NC}"
docker-compose up -d
echo -e "${GREEN}✓ Containers started${NC}\n"

# Wait for MySQL to be ready
echo -e "${YELLOW}Step 2: Waiting for MySQL services to be ready...${NC}"
sleep 15
echo -e "${GREEN}✓ MySQL services ready${NC}\n"

# Step 2.5: Verify and fix server-ids
echo -e "${YELLOW}Step 2.5: Verifying server-ids...${NC}"
MASTER_SERVER_ID=$(docker exec mysql-master mysql -uroot -pmysql -sN -e "SELECT @@server_id;" 2>/dev/null || echo "101")
SLAVE_SERVER_ID=$(docker exec mysql-slave mysql -uroot -pmysql -sN -e "SELECT @@server_id;" 2>/dev/null || echo "102")

if [ "$MASTER_SERVER_ID" = "$SLAVE_SERVER_ID" ]; then
    echo -e "${YELLOW}⚠ Server IDs are the same ($MASTER_SERVER_ID). Fixing...${NC}"
    docker exec mysql-master mysql -uroot -pmysql -e "SET GLOBAL server_id = 101;" 2>/dev/null || true
    docker exec mysql-slave mysql -uroot -pmysql -e "SET GLOBAL server_id = 102;" 2>/dev/null || true
    # Also update in my.cnf equivalent by restarting with correct config
    echo -e "${YELLOW}⚠ Please restart containers to apply server-id changes permanently${NC}"
    echo -e "${YELLOW}  Run: docker-compose restart mysql-master mysql-slave${NC}"
fi
echo -e "${GREEN}✓ Master server_id: $MASTER_SERVER_ID, Slave server_id: $SLAVE_SERVER_ID${NC}\n"

# Step 3: Create replication user on master
echo -e "${YELLOW}Step 3: Creating replication user on master...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
CREATE USER IF NOT EXISTS 'slave_user'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'slave_user'@'%';
FLUSH PRIVILEGES;
SELECT user, host FROM mysql.user WHERE user='slave_user';
EOF
echo -e "${GREEN}✓ Replication user created${NC}\n"

# Step 4: Create demo database and table on master
echo -e "${YELLOW}Step 4: Creating demo database and table on master...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
CREATE TABLE IF NOT EXISTS demo (
    id INT AUTO_INCREMENT PRIMARY KEY,
    value VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO demo (value) VALUES ('Initial data from master');
SELECT * FROM demo;
EOF
echo -e "${GREEN}✓ Demo table created with initial data${NC}\n"

# Step 5: Dump existing data from master with binary log position
echo -e "${YELLOW}Step 5: Dumping existing data from master...${NC}"
docker exec -i mysql-master mysqldump -uroot -pmysql --source-data=2 --single-transaction --set-gtid-purged=OFF acquia > /tmp/acquia-dump.sql
echo -e "${GREEN}✓ Data dumped from master${NC}\n"

# Step 6: Restore dump on slave
echo -e "${YELLOW}Step 6: Restoring data on slave...${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql acquia < /tmp/acquia-dump.sql
echo -e "${GREEN}✓ Data restored on slave${NC}\n"

# Step 7: Extract master log position from dump
echo -e "${YELLOW}Step 7: Extracting master binary log position from dump...${NC}"
# Try new MySQL 8.0+ syntax first, fallback to old syntax
MASTER_LOG_FILE=$(grep -E "CHANGE (REPLICATION )?SOURCE TO|CHANGE MASTER TO" /tmp/acquia-dump.sql | grep -oE "SOURCE_LOG_FILE='[^']*'|MASTER_LOG_FILE='[^']*'" | cut -d"'" -f2 | head -1)
MASTER_LOG_POS=$(grep -E "CHANGE (REPLICATION )?SOURCE TO|CHANGE MASTER TO" /tmp/acquia-dump.sql | grep -oE "SOURCE_LOG_POS=[0-9]*|MASTER_LOG_POS=[0-9]*" | cut -d"=" -f2 | head -1)
echo -e "${GREEN}✓ Master Log File: $MASTER_LOG_FILE${NC}"
echo -e "${GREEN}✓ Master Log Position: $MASTER_LOG_POS${NC}\n"

# Step 8: Configure slave
echo -e "${YELLOW}Step 8: Configuring slave to replicate from master...${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql <<EOF
STOP REPLICA;
CHANGE REPLICATION SOURCE TO 
    SOURCE_HOST='mysql-master',
    SOURCE_USER='slave_user',
    SOURCE_PASSWORD='password',
    SOURCE_LOG_FILE='$MASTER_LOG_FILE',
    SOURCE_LOG_POS=$MASTER_LOG_POS;
START REPLICA;
EOF
echo -e "${GREEN}✓ Slave configured${NC}\n"

# Step 9: Wait for slave to catch up
echo -e "${YELLOW}Step 9: Waiting for slave to synchronize...${NC}"
sleep 5

# Step 10: Check slave status
echo -e "${YELLOW}Step 10: Checking slave status...${NC}"
# Use -N (no column names) and -s (silent) for cleaner output
IO_RUNNING=$(docker exec mysql-slave mysql -uroot -pmysql -sN -e "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status WHERE CHANNEL_NAME='';" 2>/dev/null)
SQL_RUNNING=$(docker exec mysql-slave mysql -uroot -pmysql -sN -e "SELECT SERVICE_STATE FROM performance_schema.replication_applier_status WHERE CHANNEL_NAME='';" 2>/dev/null)

# Fallback to SHOW REPLICA STATUS if performance_schema queries fail
if [ -z "$IO_RUNNING" ] || [ -z "$SQL_RUNNING" ]; then
    SLAVE_STATUS=$(docker exec mysql-slave mysql -uroot -pmysql -e "SHOW REPLICA STATUS\G" 2>/dev/null || docker exec mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G" 2>/dev/null)
    IO_RUNNING=$(echo "$SLAVE_STATUS" | grep -E "Replica_IO_Running:|Slave_IO_Running:" | awk '{print $2}')
    SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep -E "Replica_SQL_Running:|Slave_SQL_Running:" | awk '{print $2}')
fi

# Convert ON to Yes for consistency
[ "$IO_RUNNING" = "ON" ] && IO_RUNNING="Yes"
[ "$SQL_RUNNING" = "ON" ] && SQL_RUNNING="Yes"

echo -e "Replica_IO_Running: ${GREEN}$IO_RUNNING${NC}"
echo -e "Replica_SQL_Running: ${GREEN}$SQL_RUNNING${NC}\n"

if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Replication setup successful!${NC}"
    echo -e "${GREEN}========================================${NC}\n"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Replication setup failed!${NC}"
    echo -e "${RED}========================================${NC}\n"
    echo "Full slave status:"
    docker exec mysql-slave mysql -uroot -pmysql -e "SHOW REPLICA STATUS\G" 2>/dev/null || docker exec mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G" 2>/dev/null
    rm -f /tmp/acquia-dump.sql
    exit 1
fi

# Step 11: Verify data on slave
echo -e "${YELLOW}Step 11: Verifying data on slave...${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql -e "USE acquia; SELECT * FROM demo;"
echo -e "${GREEN}✓ Data verified on slave${NC}\n"

# Cleanup
rm -f /tmp/acquia-dump.sql

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setup complete! Run ./test-replication.sh to test${NC}"
echo -e "${BLUE}========================================${NC}"
