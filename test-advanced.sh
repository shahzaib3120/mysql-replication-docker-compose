#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Advanced Replication Tests${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Test 1: Replication lag test
echo -e "${YELLOW}Test 1: Replication lag test (inserting 100 rows)...${NC}"
START_TIME=$(date +%s)
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
CREATE TABLE IF NOT EXISTS lag_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

for i in {1..100}; do
    docker exec -i mysql-master mysql -uroot -pmysql -e "USE acquia; INSERT INTO lag_test (data) VALUES ('Row $i');" > /dev/null 2>&1
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -e "${GREEN}✓ Inserted 100 rows in ${DURATION}s${NC}"

echo -e "${YELLOW}Waiting for slave to catch up...${NC}"
sleep 3

MASTER_COUNT=$(docker exec -i mysql-master mysql -uroot -pmysql -sN -e "USE acquia; SELECT COUNT(*) FROM lag_test;")
SLAVE_COUNT=$(docker exec -i mysql-slave mysql -uroot -pmysql -sN -e "USE acquia; SELECT COUNT(*) FROM lag_test;")

echo -e "Master count: ${BLUE}$MASTER_COUNT${NC}"
echo -e "Slave count: ${BLUE}$SLAVE_COUNT${NC}"

if [ "$MASTER_COUNT" = "$SLAVE_COUNT" ]; then
    echo -e "${GREEN}✓ Slave is in sync${NC}\n"
else
    echo -e "${RED}✗ Slave is behind: $((MASTER_COUNT - SLAVE_COUNT)) rows${NC}\n"
fi

# Test 2: Binary log analysis
echo -e "${YELLOW}Test 2: Binary log analysis...${NC}"
echo -e "${BLUE}Master binary logs:${NC}"
docker exec -i mysql-master mysql -uroot -pmysql -e "SHOW BINARY LOGS;"

echo -e "${BLUE}Slave relay logs:${NC}"
docker exec -i mysql-slave bash -c "ls -lh /var/log/mysql/mysql-relay-bin.*" 2>/dev/null || echo "No relay logs found"

# Test 3: Replication filters test
echo -e "${YELLOW}Test 3: Testing replication filters...${NC}"
echo -e "${BLUE}Master replication filters:${NC}"
docker exec -i mysql-master mysql -uroot -pmysql -e "SHOW MASTER STATUS\G" | grep -E "(Binlog_Do_DB|Binlog_Ignore_DB)"

echo -e "${BLUE}Slave replication filters:${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G" | grep -E "(Replicate_Do_DB|Replicate_Ignore_DB|Replicate_Do_Table|Replicate_Ignore_Table)"

# Test 4: Test non-replicated database
echo -e "${YELLOW}Test 4: Testing non-replicated database (should NOT replicate)...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
CREATE DATABASE IF NOT EXISTS test_no_replication;
USE test_no_replication;
CREATE TABLE test_table (id INT);
INSERT INTO test_table VALUES (1), (2), (3);
EOF
echo -e "${GREEN}✓ Created database 'test_no_replication' on master${NC}"

sleep 2

SLAVE_DB_EXISTS=$(docker exec -i mysql-slave mysql -uroot -pmysql -sN -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test_no_replication';")

if [ "$SLAVE_DB_EXISTS" = "0" ]; then
    echo -e "${GREEN}✓ Database NOT replicated (as expected, only 'acquia' is replicated)${NC}\n"
else
    echo -e "${YELLOW}⚠ Database was replicated (binlog_do_db filter may not be working)${NC}\n"
fi

# Test 5: Transaction consistency test
echo -e "${YELLOW}Test 5: Transaction consistency test...${NC}"
docker exec -i mysql-master mysql -uroot -pmysql <<EOF
USE acquia;
START TRANSACTION;
INSERT INTO demo (value) VALUES ('Transaction 1');
INSERT INTO demo (value) VALUES ('Transaction 2');
INSERT INTO demo (value) VALUES ('Transaction 3');
COMMIT;
EOF
echo -e "${GREEN}✓ Committed transaction with 3 inserts on master${NC}"

sleep 2

MASTER_LAST_3=$(docker exec -i mysql-master mysql -uroot -pmysql -sN -e "USE acquia; SELECT value FROM demo ORDER BY id DESC LIMIT 3;")
SLAVE_LAST_3=$(docker exec -i mysql-slave mysql -uroot -pmysql -sN -e "USE acquia; SELECT value FROM demo ORDER BY id DESC LIMIT 3;")

if [ "$MASTER_LAST_3" = "$SLAVE_LAST_3" ]; then
    echo -e "${GREEN}✓ Transaction replicated consistently${NC}\n"
else
    echo -e "${RED}✗ Transaction data mismatch${NC}\n"
fi

# Test 6: Replication error recovery simulation
echo -e "${YELLOW}Test 6: Testing replication status monitoring...${NC}"
SLAVE_STATUS=$(docker exec -i mysql-slave mysql -uroot -pmysql -e "SHOW SLAVE STATUS\G")

echo -e "${BLUE}Key replication metrics:${NC}"
echo "$SLAVE_STATUS" | grep -E "(Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_IO_Error|Last_SQL_Error)" | while read line; do
    if echo "$line" | grep -q "Running: Yes"; then
        echo -e "${GREEN}$line${NC}"
    elif echo "$line" | grep -q "Running: No"; then
        echo -e "${RED}$line${NC}"
    elif echo "$line" | grep -q "Seconds_Behind_Master: 0"; then
        echo -e "${GREEN}$line${NC}"
    else
        echo -e "${BLUE}$line${NC}"
    fi
done

# Test 7: Performance metrics
echo -e "\n${YELLOW}Test 7: Performance metrics...${NC}"
echo -e "${BLUE}Master status:${NC}"
docker exec -i mysql-master mysql -uroot -pmysql -e "SHOW STATUS LIKE 'Binlog_cache%';"

echo -e "${BLUE}Slave status:${NC}"
docker exec -i mysql-slave mysql -uroot -pmysql -e "SHOW STATUS LIKE 'Slave_running';"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Advanced tests completed!${NC}"
echo -e "${GREEN}========================================${NC}"
