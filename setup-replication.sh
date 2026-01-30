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

# Step 3: Create replication user on master
echo -e "${YELLOW}Step 3: Creating replication user on master...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
GRANT REPLICATION SLAVE ON *.* TO 'slave_user'@'%' IDENTIFIED BY 'password';
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
docker exec -i mysql-master mysqldump -uroot -pmysql --master-data=2 --single-transaction acquia > /tmp/acquia-dump.sql
echo -e "${GREEN}✓ Data dumped from master${NC}\n"

# Step 6: Restore dump on slave
echo -e "${YELLOW}Step 6: Restoring data on slave...${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql acquia < /tmp/acquia-dump.sql
echo -e "${GREEN}✓ Data restored on slave${NC}\n"

# Step 7: Extract master log position from dump
echo -e "${YELLOW}Step 7: Extracting master binary log position from dump...${NC}"
MASTER_LOG_FILE=$(grep "CHANGE MASTER TO" /tmp/acquia-dump.sql | grep -o "MASTER_LOG_FILE='[^']*'" | cut -d"'" -f2)
MASTER_LOG_POS=$(grep "CHANGE MASTER TO" /tmp/acquia-dump.sql | grep -o "MASTER_LOG_POS=[0-9]*" | cut -d"=" -f2)
echo -e "${GREEN}✓ Master Log File: $MASTER_LOG_FILE${NC}"
echo -e "${GREEN}✓ Master Log Position: $MASTER_LOG_POS${NC}\n"

# Step 8: Configure slave
echo -e "${YELLOW}Step 8: Configuring slave to replicate from master...${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql <<EOF
STOP SLAVE;
CHANGE MASTER TO 
    MASTER_HOST='mysql-master',
    MASTER_USER='slave_user',
    MASTER_PASSWORD='password',
    MASTER_LOG_FILE='$MASTER_LOG_FILE',
    MASTER_LOG_POS=$MASTER_LOG_POS;
START SLAVE;
EOF
echo -e "${GREEN}✓ Slave configured${NC}\n"

# Step 9: Wait for slave to catch up
echo -e "${YELLOW}Step 9: Waiting for slave to synchronize...${NC}"
sleep 5

# Step 10: Check slave status
echo -e "${YELLOW}Step 10: Checking slave status...${NC}"
SLAVE_STATUS=$(docker exec -i mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G")
IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')

echo -e "Slave_IO_Running: ${GREEN}$IO_RUNNING${NC}"
echo -e "Slave_SQL_Running: ${GREEN}$SQL_RUNNING${NC}\n"

if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Replication setup successful!${NC}"
    echo -e "${GREEN}========================================${NC}\n"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ Replication setup failed!${NC}"
    echo -e "${RED}========================================${NC}\n"
    echo "Full slave status:"
    echo "$SLAVE_STATUS"
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
