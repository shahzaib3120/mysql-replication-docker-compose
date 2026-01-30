#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MySQL Replication Test Suite${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Function to check replication status
check_replication_status() {
    # Use -N (no column names) and -s (silent) for cleaner output
    IO_RUNNING=$(docker exec mysql-slave mysql -uroot -pmysql -sN -e "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status WHERE CHANNEL_NAME='';" 2>/dev/null)
    SQL_RUNNING=$(docker exec mysql-slave mysql -uroot -pmysql -sN -e "SELECT SERVICE_STATE FROM performance_schema.replication_applier_status WHERE CHANNEL_NAME='';" 2>/dev/null)
    
    # Fallback to SHOW REPLICA STATUS if performance_schema queries fail
    if [ -z "$IO_RUNNING" ] || [ -z "$SQL_RUNNING" ]; then
        SLAVE_STATUS=$(docker exec mysql-slave mysql -uroot -pmysql -e "SHOW REPLICA STATUS\G" 2>/dev/null || docker exec mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G" 2>/dev/null)
        IO_RUNNING=$(echo "$SLAVE_STATUS" | grep -E "Replica_IO_Running:|Slave_IO_Running:" | awk '{print $2}')
        SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep -E "Replica_SQL_Running:|Slave_SQL_Running:" | awk '{print $2}')
        SECONDS_BEHIND=$(echo "$SLAVE_STATUS" | grep -E "Seconds_Behind_Source:|Seconds_Behind_Master:" | awk '{print $2}')
    else
        # Get seconds behind from performance_schema
        SECONDS_BEHIND=$(docker exec mysql-slave mysql -uroot -pmysql -sN -e "SELECT COUNT_TRANSACTIONS_IN_QUEUE FROM performance_schema.replication_connection_status WHERE CHANNEL_NAME='';" 2>/dev/null)
    fi
    
    # Convert ON to Yes for consistency
    [ "$IO_RUNNING" = "ON" ] && IO_RUNNING="Yes"
    [ "$SQL_RUNNING" = "ON" ] && SQL_RUNNING="Yes"
    
    if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
        echo -e "${GREEN}✓ Replication is running${NC}"
        echo -e "  Replica_IO_Running: ${GREEN}$IO_RUNNING${NC}"
        echo -e "  Replica_SQL_Running: ${GREEN}$SQL_RUNNING${NC}"
        echo -e "  Seconds_Behind_Source: ${GREEN}$SECONDS_BEHIND${NC}\n"
        return 0
    else
        echo -e "${RED}✗ Replication is NOT running${NC}"
        echo -e "  Replica_IO_Running: ${RED}$IO_RUNNING${NC}"
        echo -e "  Replica_SQL_Running: ${RED}$SQL_RUNNING${NC}\n"
        return 1
    fi
}

# Function to compare data between master and slave
compare_data() {
    local table=$1
    echo -e "${YELLOW}Comparing data in table '$table'...${NC}"
    
    echo -e "${BLUE}Master data:${NC}"
    docker exec -i mysql-master mysql -uroot -pmysql -e "USE acquia; SELECT * FROM $table;"
    
    echo -e "${BLUE}Slave data:${NC}"
    docker exec -i mysql-slave mysql -uroot -pmysql -e "USE acquia; SELECT * FROM $table;"
    
    MASTER_COUNT=$(docker exec -i mysql-master mysql -uroot -pmysql -sN -e "USE acquia; SELECT COUNT(*) FROM $table;")
    SLAVE_COUNT=$(docker exec -i mysql-slave mysql -uroot -pmysql -sN -e "USE acquia; SELECT COUNT(*) FROM $table;")
    
    if [ "$MASTER_COUNT" = "$SLAVE_COUNT" ]; then
        echo -e "${GREEN}✓ Row counts match: $MASTER_COUNT rows${NC}\n"
        return 0
    else
        echo -e "${RED}✗ Row counts differ: Master=$MASTER_COUNT, Slave=$SLAVE_COUNT${NC}\n"
        return 1
    fi
}

# Test 1: Check initial replication status
echo -e "${YELLOW}Test 1: Checking replication status...${NC}"
check_replication_status
if [ $? -ne 0 ]; then
    echo -e "${RED}Replication is not running. Please run ./setup-replication.sh first${NC}"
    exit 1
fi

# Test 2: Insert data on master and verify on slave
echo -e "${YELLOW}Test 2: Testing INSERT replication...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
INSERT INTO demo (value) VALUES ('Test insert $(date +%s)');
EOF
echo -e "${GREEN}✓ Inserted data on master${NC}"
sleep 2
compare_data "demo"

# Test 3: Update data on master and verify on slave
echo -e "${YELLOW}Test 3: Testing UPDATE replication...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
UPDATE demo SET value = 'Updated value $(date +%s)' WHERE id = 1;
EOF
echo -e "${GREEN}✓ Updated data on master${NC}"
sleep 2
compare_data "demo"

# Test 4: Create new table on master and verify on slave
echo -e "${YELLOW}Test 4: Testing CREATE TABLE replication...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
CREATE TABLE IF NOT EXISTS test_table_$(date +%s) (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100)
);
EOF
echo -e "${GREEN}✓ Created new table on master${NC}"
sleep 2

echo -e "${BLUE}Tables on master:${NC}"
docker exec -i mysql-master mysql -uroot -pmysql -e "USE acquia; SHOW TABLES;"

echo -e "${BLUE}Tables on slave:${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql -e "USE acquia; SHOW TABLES;"

# Test 5: Bulk insert test
echo -e "${YELLOW}Test 5: Testing bulk INSERT replication...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
INSERT INTO demo (value) VALUES 
    ('Bulk insert 1'),
    ('Bulk insert 2'),
    ('Bulk insert 3'),
    ('Bulk insert 4'),
    ('Bulk insert 5');
EOF
echo -e "${GREEN}✓ Inserted 5 rows on master${NC}"
sleep 2
compare_data "demo"

# Test 6: Check binary log position
echo -e "${YELLOW}Test 6: Checking binary log positions...${NC}"
echo -e "${BLUE}Master status:${NC}"
docker exec mysql-master mysql -uroot -pmysql -e "SHOW MASTER STATUS\G" 2>/dev/null

echo -e "${BLUE}Replica status (relevant fields):${NC}"
docker exec mysql-slave mysql -uroot -pmysql -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Source_Log_File|Master_Log_File|Read_Source_Log_Pos|Read_Master_Log_Pos|Exec_Source_Log_Pos|Exec_Master_Log_Pos|Seconds_Behind_Source|Seconds_Behind_Master)" || \
docker exec mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep -E "(Source_Log_File|Master_Log_File|Read_Source_Log_Pos|Read_Master_Log_Pos|Exec_Source_Log_Pos|Exec_Master_Log_Pos|Seconds_Behind_Source|Seconds_Behind_Master)"

# Test 7: Check server IDs
echo -e "${YELLOW}Test 7: Verifying server IDs are different...${NC}"
MASTER_ID=$(docker exec -i mysql-master mysql -uroot -pmysql -sN -e "SELECT @@server_id;")
SLAVE_ID=$(docker exec -i mysql-slave mysql -uroot -pmysql -sN -e "SELECT @@server_id;")

echo -e "Master server_id: ${BLUE}$MASTER_ID${NC}"
echo -e "Slave server_id: ${BLUE}$SLAVE_ID${NC}"

if [ "$MASTER_ID" != "$SLAVE_ID" ]; then
    echo -e "${GREEN}✓ Server IDs are different (required for replication)${NC}\n"
else
    echo -e "${RED}✗ Server IDs are the same (this will cause replication to fail!)${NC}\n"
fi

# Final status check
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Final Replication Status${NC}"
echo -e "${BLUE}========================================${NC}"
check_replication_status

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All tests completed!${NC}"
echo -e "${GREEN}========================================${NC}"
