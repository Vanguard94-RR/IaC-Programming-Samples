#!/bin/bash
###############################################################################
# Firebase Node Manager - Interactive Wrapper
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

###############################################################################
# HELPER FUNCTIONS
###############################################################################

header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   ${CYAN}Firebase Node Manager${NC}                                 ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

prompt() {
    local label="$1"
    local var_name="$2"
    local default="${3:-}"
    
    if [ -n "$default" ]; then
        echo -ne "${YELLOW}${label}${NC} [${default}]: "
    else
        echo -ne "${YELLOW}${label}${NC}: "
    fi
    
    read -r input
    eval "$var_name='${input:-$default}'"
}

confirm() {
    local message="$1"
    echo -ne "${YELLOW}${message}${NC} (y/n): "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
}

show_summary() {
    echo ""
    echo -e "${CYAN}📋 SUMMARY:${NC}"
    echo "  $1"
    echo ""
}

###############################################################################
# OPTION 1: EXTRACT
###############################################################################

extract_menu() {
    header
    echo -e "${CYAN}📥 EXTRACT NODE${NC}\n"
    
    prompt "Backup file path or URL" backup_file
    # Validate: check if URL or file exists
    if ! [[ "$backup_file" =~ ^https?:// ]] && [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ File not found or invalid URL${NC}" && sleep 2 && return
    fi
    
    prompt "Node path to extract (e.g. SectionsView/home, Home)" node_path
    [ -z "$node_path" ] && echo -e "${RED}❌ Node required${NC}" && sleep 2 && return
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    default_output="JsonOutput/${node_path//\//_}_${timestamp}.json"
    prompt "Output file" output_file "$default_output"
    
    show_summary "
  📁 Backup: $backup_file
  📍 Node: $node_path
  💾 Output: $output_file"
    
    confirm "Continue?" || return
    
    echo ""
    echo -e "${YELLOW}⏳ Extracting...${NC}\n"
    
    if "$SCRIPT_DIR/extract.sh" "$backup_file" "$node_path" "$output_file"; then
        echo -e "\n${GREEN}✅ Extraction completed${NC}"
    else
        echo -e "\n${RED}❌ Extraction error${NC}"
    fi
    
    read -p "Press ENTER to continue..."
}

###############################################################################
# OPTION 2: RESTORE
###############################################################################

restore_menu() {
    header
    echo -e "${CYAN}📤 RESTORE NODE${NC}\n"
    
    prompt "Firebase project ID" project_id
    [ -z "$project_id" ] && echo -e "${RED}❌ Project required${NC}" && sleep 2 && return
    
    prompt "Node path to restore (e.g. SectionsView, Home)" node_path
    [ -z "$node_path" ] && echo -e "${RED}❌ Node required${NC}" && sleep 2 && return
    
    prompt "Path to data file" data_file
    [ ! -f "$data_file" ] && echo -e "${RED}❌ File not found${NC}" && sleep 2 && return
    
    show_summary "
  🔧 Project: $project_id
  📍 Node: $node_path
  📄 Data: $data_file"
    
    echo -e "${RED}⚠️  WARNING: This operation will modify data in Firebase${NC}"
    
    confirm "Confirm restore?" || return
    
    echo ""
    echo -e "${YELLOW}⏳ Restoring...${NC}\n"
    
    if "$SCRIPT_DIR/restore.sh" "$project_id" "$node_path" "$data_file"; then
        echo -e "\n${GREEN}✅ Restore completed${NC}"
    else
        echo -e "\n${RED}❌ Restore error${NC}"
    fi
    
    read -p "Press ENTER to continue..."
}

###############################################################################
# MAIN MENU
###############################################################################

main_menu() {
    while true; do
        header
        echo -e "Select an option:\n"
        echo -e "  ${GREEN}1)${NC} 📥 Extract node from backup"
        echo -e "  ${GREEN}2)${NC} 📤 Restore node to Firebase"
        echo -e "  ${GREEN}3)${NC} 🚪 Exit"
        echo ""
        
        echo -ne "${CYAN}Option [1-3]:${NC} "
        read -r choice
        
        case "$choice" in
            1) extract_menu ;;
            2) restore_menu ;;
            3) 
                echo -e "\n${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Invalid option${NC}"
                sleep 2
                ;;
        esac
    done
}

###############################################################################
# ENTRY POINT
###############################################################################

main_menu
