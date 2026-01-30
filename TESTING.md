# MySQL Master-Slave Replication Test Scripts

This directory contains automated scripts to set up, test, and manage MySQL master-slave replication using Docker.

## 📋 Prerequisites

- Docker and Docker Compose installed
- Bash shell (macOS/Linux)

## 🚀 Quick Start

### 1. Setup Replication

```bash
./setup-replication.sh
```

This script will:

- Start MySQL master and slave containers
- Create replication user on master
- Configure slave to replicate from master
- Create demo database and table
- Verify replication is working

### 2. Test Replication

```bash
./test-replication.sh
```

This script runs comprehensive tests:

- ✅ Replication status check
- ✅ INSERT operation replication
- ✅ UPDATE operation replication
- ✅ CREATE TABLE replication
- ✅ Bulk insert test
- ✅ Binary log position verification
- ✅ Server ID validation

### 3. Advanced Tests

```bash
./test-advanced.sh
```

Advanced testing scenarios:

- ⚡ Replication lag test (100 row insert)
- 📊 Binary log analysis
- 🔍 Replication filter verification
- 🔄 Transaction consistency test
- 📈 Performance metrics
- 🚫 Non-replicated database test

### 4. Cleanup

```bash
./cleanup.sh
```

Stops containers and removes all data (requires confirmation).

## 📁 Directory Structure

```
.
├── docker-compose.yml          # Container orchestration
├── master/
│   ├── conf.d/
│   │   └── master.cnf         # Master MySQL config (server-id: 101)
│   ├── data/                  # Master data directory
│   ├── log/                   # Master binary logs
│   └── backup/                # Master backups
├── slave/
│   ├── conf.d/
│   │   └── slave.cnf          # Slave MySQL config (server-id: 102)
│   ├── data/                  # Slave data directory
│   ├── log/                   # Slave relay logs
│   └── backup/                # Slave backups
├── setup-replication.sh       # Initial setup script
├── test-replication.sh        # Basic replication tests
├── test-advanced.sh           # Advanced replication tests
└── cleanup.sh                 # Cleanup script
```

## 🔧 Configuration Details

### Master Configuration (`master/conf.d/master.cnf`)

```ini
[mysqld]
server-id = 101                # Unique server ID
log_bin = /var/log/mysql/mysql-bin.log
binlog_do_db = acquia         # Only replicate 'acquia' database
bind-address = 0.0.0.0
```

### Slave Configuration (`slave/conf.d/slave.cnf`)

```ini
[mysqld]
server-id = 102                # Different from master
log_bin = /var/log/mysql/mysql-bin.log
relay-log = /var/log/mysql/mysql-relay-bin.log
binlog_do_db = acquia
replicate_do_db = acquia      # Only replicate 'acquia' database
bind-address = 0.0.0.0
```

## 🔑 Key Concepts Demonstrated

### 1. Server IDs

- Master: `server-id = 101`
- Slave: `server-id = 102`
- **Critical**: Server IDs MUST be different for replication to work

### 2. Replication User

```sql
GRANT REPLICATION SLAVE ON *.* TO 'slave_user'@'%' IDENTIFIED BY 'password';
```

### 3. Slave Configuration

```sql
CHANGE MASTER TO
    MASTER_HOST='mysql-master',
    MASTER_USER='slave_user',
    MASTER_PASSWORD='password',
    MASTER_LOG_FILE='mysql-bin.000001',
    MASTER_LOG_POS=123;
START SLAVE;
```

### 4. Monitoring Replication

```sql
-- On Master
SHOW MASTER STATUS\G

-- On Slave
SHOW SLAVE STATUS\G
```

Key status indicators:

- `Slave_IO_Running: Yes` - IO thread is running
- `Slave_SQL_Running: Yes` - SQL thread is running
- `Seconds_Behind_Master: 0` - Slave is in sync

## 🐛 Troubleshooting

### Error: Server IDs are the same

```
Last_IO_Error: Fatal error: The slave I/O thread stops because master and slave have equal MySQL server ids
```

**Solution**: Verify `server-id` in `master.cnf` and `slave.cnf` are different.

### Replication not starting

1. Check slave status: `SHOW SLAVE STATUS\G`
2. Verify master is reachable: `ping mysql-master`
3. Check replication user exists on master
4. Verify binary log position is correct

### Slave is behind

```sql
-- Check lag
SHOW SLAVE STATUS\G  -- Look at Seconds_Behind_Master

-- If needed, skip problematic queries
STOP SLAVE SQL_THREAD;
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE SQL_THREAD;
```

## 📊 Manual Testing Commands

### Connect to Master

```bash
docker exec -it mysql-master mysql -uroot -pmysql
```

### Connect to Slave

```bash
docker exec -it mysql-slave mysql -uroot -pmysql
```

### Insert Test Data on Master

```sql
USE acquia;
INSERT INTO demo (value) VALUES ('Test data');
```

### Verify on Slave

```sql
USE acquia;
SELECT * FROM demo;
```

### View Binary Logs

```bash
# On Master
docker exec -it mysql-master bash
cd /var/log/mysql/
mysqlbinlog mysql-bin.000001

# On Slave
docker exec -it mysql-slave bash
cd /var/log/mysql/
mysqlbinlog mysql-relay-bin.000001
```

## 🎯 What Gets Replicated

✅ **Replicated** (database: `acquia`):

- CREATE/DROP TABLE
- INSERT/UPDATE/DELETE
- ALTER TABLE
- TRUNCATE

❌ **NOT Replicated**:

- Other databases (due to `binlog_do_db = acquia`)
- User/permission changes (unless explicitly configured)
- System database changes

## 🔄 Workflow

1. **Setup**: Run `./setup-replication.sh`
2. **Test**: Run `./test-replication.sh` to verify basic functionality
3. **Advanced**: Run `./test-advanced.sh` for comprehensive testing
4. **Develop**: Make changes and test replication
5. **Cleanup**: Run `./cleanup.sh` when done

## 📝 Notes

- Default credentials: `root` / `mysql`
- Replication user: `slave_user` / `password`
- Database: `acquia`
- Master port: 3306 (mapped dynamically)
- Slave port: 3306 (mapped dynamically)

## 🔗 Useful Resources

- [MySQL Replication Documentation](https://dev.mysql.com/doc/refman/5.6/en/replication.html)
- [Binary Log Formats](https://dev.mysql.com/doc/refman/5.6/en/binary-log-formats.html)
- [Replication Troubleshooting](https://dev.mysql.com/doc/refman/5.6/en/replication-problems.html)
