#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MySQL Replication Cleanup${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${YELLOW}This will:${NC}"
echo -e "  - Stop all containers"
echo -e "  - Remove all volumes (data will be lost)"
echo -e "  - Clean up log files"
echo -e ""
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "${YELLOW}Step 1: Stopping containers...${NC}"
docker-compose down -v
echo -e "${GREEN}✓ Containers stopped and volumes removed${NC}\n"

echo -e "${YELLOW}Step 2: Cleaning up data directories...${NC}"
rm -rf master/data/* master/log/* master/backup/*
rm -rf slave/data/* slave/log/* slave/backup/*
echo -e "${GREEN}✓ Data directories cleaned${NC}\n"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo -e "${BLUE}To set up replication again, run:${NC}"
echo -e "  ./setup-replication.sh"
