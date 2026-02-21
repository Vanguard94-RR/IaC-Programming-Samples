#!/bin/bash
###############################################################################
# Simple Firebase Node Restorer
# Usage: ./restore.sh project-id node-path data.json
###############################################################################

set -euo pipefail

PROJECT="${1:?Usage: $0 <project-id> <node-path> <data.json>}"
NODE_PATH="${2:?Usage: $0 <project-id> <node-path> <data.json>}"
DATA_FILE="${3:?Usage: $0 <project-id> <node-path> <data.json>}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

[ ! -f "$DATA_FILE" ] && echo -e "${RED}❌ File not found: $DATA_FILE${NC}" && exit 1

echo -e "${YELLOW}⚠️  Restoring $NODE_PATH to $PROJECT${NC}"
echo "File: $DATA_FILE"
read -p "Confirm? (y/n): " -r confirm

[[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Cancelled" && exit 0

echo -e "${YELLOW}⏳ Uploading...${NC}"

firebase database:set \
    --project "$PROJECT" \
    "/$NODE_PATH" \
    "$DATA_FILE" \
    --confirm

echo -e "${GREEN}✅ Done${NC}"
