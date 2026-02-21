#!/bin/bash
###############################################################################
# Firebase Node Extractor - Extract JSON nodes from Firebase backups
# Supports local files and URLs (http, https, gs://)
# Usage: ./extract.sh <backup-file|URL> <node-path> [output.json]
###############################################################################

set -euo pipefail

BACKUP_INPUT="${1:?Usage: $0 <backup-file|URL> <node-path> [output.json]}"
NODE_PATH="${2:?Usage: $0 <backup-file|URL> <node-path> [output.json]}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="JsonOutput"
OUTPUT_FILE="${3:-${OUTPUT_DIR}/${NODE_PATH//\//_}_${TIMESTAMP}.json}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$OUTPUT_DIR"

# Determine if input is file or URL
BACKUP_FILE="$BACKUP_INPUT"
TEMP_FILES=()
GITLAB_TOKEN=""

if [[ "$BACKUP_INPUT" =~ ^(https?|gs):// ]]; then
    echo -e "${YELLOW}📥 Downloading backup...${NC}"
    BACKUP_DIR="backup"
    mkdir -p "$BACKUP_DIR"
    
    # Convert GitLab blob URLs to API URLs
    DOWNLOAD_URL="$BACKUP_INPUT"
    if [[ "$BACKUP_INPUT" =~ gitlab\.com/(.+)/-/blob/([^/]+)/(.+)$ ]]; then
        PROJECT_PATH="${BASH_REMATCH[1]}"
        BRANCH="${BASH_REMATCH[2]}"
        FILE_PATH="${BASH_REMATCH[3]}"
        # URL encode for API
        PROJECT_ENCODED=$(echo "$PROJECT_PATH" | sed 's/\//%2F/g')
        FILE_ENCODED=$(echo "$FILE_PATH" | sed 's/\//%2F/g')
        DOWNLOAD_URL="https://gitlab.com/api/v4/projects/${PROJECT_ENCODED}/repository/files/${FILE_ENCODED}/raw?ref=${BRANCH}"
        echo -e "${YELLOW}📝 Using GitLab API...${NC}"
        # Load GitLab token if it exists
        if [ -f "/home/admin/Documents/GNP/PersonalGitLabToken" ]; then
            GITLAB_TOKEN=$(cat /home/admin/Documents/GNP/PersonalGitLabToken | tr -d '\n')
            echo -e "${YELLOW}🔐 Using GitLab token for authentication...${NC}"
        fi
    fi
    
    # Convert GitHub blob URLs to raw URLs
    if [[ "$BACKUP_INPUT" =~ github\.com/.+/blob/ ]]; then
        DOWNLOAD_URL=$(echo "$BACKUP_INPUT" | sed 's|github\.com/\([^/]*\)/\([^/]*\)/blob/|raw.githubusercontent.com/\1/\2/|')
        echo -e "${YELLOW}📝 Using raw content URL...${NC}"
    fi
    
    # Convert Google Cloud Storage HTTPS URLs to gs:// format
    GCS_URL="$DOWNLOAD_URL"
    if [[ "$DOWNLOAD_URL" =~ storage\.(googleapis|cloud\.google)\.com/([^/]+)/(.+)\? ]] || [[ "$DOWNLOAD_URL" =~ storage\.(googleapis|cloud\.google)\.com/([^/]+)/(.+)$ ]]; then
        BUCKET="${BASH_REMATCH[2]}"
        OBJECT="${BASH_REMATCH[3]}"
        # URL decode the object path (handle %3A and similar)
        OBJECT=$(echo -e "$(echo "$OBJECT" | sed 's/+/ /g;s/%/\\x/g')")
        GCS_URL="gs://$BUCKET/$OBJECT"
    fi
    
    # Use gsutil for GCS paths
    if [[ "$GCS_URL" =~ ^gs:// ]]; then
        if command -v gsutil &> /dev/null; then
            BACKUP_FILE="${BACKUP_DIR}/backup_$TIMESTAMP.json.gz"
            gsutil -m cp "$GCS_URL" "$BACKUP_FILE" 2>/dev/null || {
                echo -e "${RED}❌ gsutil download failed. Check authentication: gcloud auth login${NC}"
                exit 1
            }
            TEMP_FILES+=("$BACKUP_FILE")
        else
            echo -e "${RED}❌ gsutil not found. Install Google Cloud SDK.${NC}"
            exit 1
        fi
    else
        # Handle regular http/https URLs
        # Determine file extension based on URL
        FILE_EXT=".json.gz"
        if [[ "$DOWNLOAD_URL" =~ /api/v4/ ]]; then
            FILE_EXT=".json"  # GitLab API returns uncompressed JSON
        fi
        BACKUP_FILE="${BACKUP_DIR}/backup_$TIMESTAMP${FILE_EXT}"
        if command -v curl &> /dev/null; then
            if [ -n "$GITLAB_TOKEN" ]; then
                curl -sS -L -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -o "$BACKUP_FILE" "$DOWNLOAD_URL" || {
                    echo -e "${RED}❌ Failed to download from GitLab${NC}"
                    exit 1
                }
            else
                curl -sS -L -o "$BACKUP_FILE" "$DOWNLOAD_URL" || {
                    echo -e "${RED}❌ Failed to download from URL${NC}"
                    exit 1
                }
            fi
        elif command -v wget &> /dev/null; then
            if [ -n "$GITLAB_TOKEN" ]; then
                wget -q -O "$BACKUP_FILE" --header="PRIVATE-TOKEN: $GITLAB_TOKEN" "$DOWNLOAD_URL" || {
                    echo -e "${RED}❌ Failed to download from GitLab${NC}"
                    exit 1
                }
            else
                wget -q -O "$BACKUP_FILE" "$DOWNLOAD_URL" || {
                    echo -e "${RED}❌ Failed to download from URL${NC}"
                    exit 1
                }
            fi
        else
            echo -e "${RED}❌ curl or wget required${NC}"
            exit 1
        fi
        TEMP_FILES+=("$BACKUP_FILE")
    fi
    
    # Check if file is valid
    if [ ! -s "$BACKUP_FILE" ]; then
        echo -e "${RED}❌ Downloaded file is empty${NC}"
        rm -f "${TEMP_FILES[@]}"
        exit 1
    fi
    
    # Check for HTML response (means authentication failed or URL is invalid)
    if head -c 100 "$BACKUP_FILE" 2>/dev/null | grep -qi "<!DOCTYPE\|<html"; then
        echo -e "${RED}❌ GitLab returned HTML (login page). Further options:${NC}"
        echo -e "  1. Clone the repo: git clone --sparse <repo-url>"
        echo -e "  2. Use GitLab API with project ID"
        echo -e "  3. Ensure token has 'read_repository' permission"
        rm -f "${TEMP_FILES[@]}"
        exit 1
    fi
fi

# Decompress if needed
if [[ "$BACKUP_FILE" =~ \.gz$ ]] && file "$BACKUP_FILE" | grep -q "gzip"; then
    echo -e "${YELLOW}📦 Decompressing...${NC}"
    DECOMPRESSED_FILE="${BACKUP_FILE%.gz}"
    if ! gunzip -c "$BACKUP_FILE" > "$DECOMPRESSED_FILE"; then
        echo -e "${RED}❌ Failed to decompress${NC}"
        rm -f "${TEMP_FILES[@]}" "$DECOMPRESSED_FILE"
        exit 1
    fi
    TEMP_FILES+=("$DECOMPRESSED_FILE")
    BACKUP_FILE="$DECOMPRESSED_FILE"
fi

# Validate backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}❌ Backup file not found: $BACKUP_INPUT${NC}"
    rm -f "${TEMP_FILES[@]}"
    exit 1
fi

echo -e "${YELLOW}⏳ Extracting $NODE_PATH...${NC}"

# Convert node path to jq format (e.g., SectionsView/home -> .SectionsView.home)
JQ_PATH=$(echo "$NODE_PATH" | sed 's/^/./; s/\//./g')

# Extract node
if jq -r "$JQ_PATH" "$BACKUP_FILE" > "$OUTPUT_FILE"; then
    SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    LINES=$(wc -l < "$OUTPUT_FILE")
    echo -e "${GREEN}✅ Done${NC}"
    echo "📁 $OUTPUT_FILE"
    echo "📊 Size: $SIZE | Lines: $LINES"
else
    echo -e "${RED}❌ Failed to extract node. Check node path.${NC}"
    rm -f "${TEMP_FILES[@]}"
    exit 1
fi

# Cleanup temp files
rm -f "${TEMP_FILES[@]}"
