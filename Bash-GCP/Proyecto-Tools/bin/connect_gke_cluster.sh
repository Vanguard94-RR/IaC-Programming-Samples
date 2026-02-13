#!/bin/bash
# Script: connect_gke_cluster.sh
# Description: Interactive script to select GCP project and GKE cluster, then connect using gcloud and kubectl.

set -o errexit
set -o nounset
set -o pipefail

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
BOLD="\033[1m"
NC="\033[0m"

step() { printf "\n${YELLOW}➜ ${WHITE}${BOLD}%s${NC}\n" "$1"; }
info() { printf "${CYAN}• ${WHITE}%s${NC}\n" "$1"; }
success() { printf "${GREEN}✔ ${WHITE}%s${NC}\n" "$1"; }
error() { printf "${RED}✖ ${WHITE}${BOLD}%s${NC}\n" "$1"; }

validate_number() {
    local input=$1
    local max=$2
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        error "Invalid input. Please enter a number."
        return 1
    fi
    if [ "$input" -lt 1 ] || [ "$input" -gt "$max" ]; then
        error "Invalid selection. Please enter a number between 1 and $max."
        return 1
    fi
    return 0
}

PROJECT_ID=""
if [ $# -ge 1 ]; then
    PROJECT_ID="$1"
fi

select_gcp_project() {
    step "Step 1: Select your GCP project"
    if [ -n "$PROJECT_ID" ]; then
        info "Using project ID from argument: $PROJECT_ID"
        if gcloud config set project "$PROJECT_ID"; then
            success "Project set successfully."
            return
        else
            error "Failed to set project. Please check the project ID and try again."
            exit 1
        fi
    fi
    while true; do
        echo -ne "${CYAN}Enter your project ID:${NC} ${WHITE}${BOLD}"
        read -r PROJECT_ID
        printf "${NC}"
        if [ -z "$PROJECT_ID" ]; then
            error "Project ID cannot be empty. Please try again."
            continue
        fi
        info "Setting project to: $PROJECT_ID"
        if gcloud config set project "$PROJECT_ID"; then
            success "Project set successfully."
            break
        else
            error "Failed to set project. Please check the project ID and try again."
        fi
    done
}

select_cluster() {
    step "Step 2: Select your Kubernetes cluster"
    if ! CLUSTERS_INFO=$(gcloud container clusters list --format="value(name,zone)"); then
        error "Failed to list clusters. Exiting."
        exit 1
    fi
    if [ -z "$CLUSTERS_INFO" ]; then
        error "No clusters found in project. Exiting."
        exit 1
    fi
    CLUSTER_NAMES=()
    CLUSTER_ZONES=()
    CLUSTER_TABLE=""
    INDEX=1
    CLUSTER_TABLE+="\n+----+-------------------------+---------------------+\n"
    CLUSTER_TABLE+="| #  | Cluster Name            | Zone                |\n"
    CLUSTER_TABLE+="+----+-------------------------+---------------------+\n"
    while read -r line; do
        if [ -n "$line" ]; then
            name=$(echo "$line" | awk '{print $1}')
            zone=$(echo "$line" | awk '{print $2}')
            CLUSTER_NAMES+=("$name")
            CLUSTER_ZONES+=("$zone")
            CLUSTER_TABLE+="| $(printf '%-2s' "$INDEX") | $(printf '%-23s' "$name") | $(printf '%-19s' "$zone") |\n"
            INDEX=$((INDEX+1))
        fi
    done <<< "$CLUSTERS_INFO"
    CLUSTER_TABLE+="+----+-------------------------+---------------------+\n"
    printf "%b" "$CLUSTER_TABLE"
    local max_clusters=$((INDEX-1))
    if [ $max_clusters -eq 0 ]; then
        error "No clusters found in project. Exiting."
        exit 1
    fi
    while true; do
        echo -ne "${CYAN}Enter the cluster number:${NC} ${WHITE}${BOLD}"
        read -r CLUSTER_NUM
        printf "${NC}"
        if validate_number "$CLUSTER_NUM" "$max_clusters"; then
            break
        fi
    done
    CLUSTER_IDX=$((CLUSTER_NUM-1))
    CLUSTER_NAME=${CLUSTER_NAMES[$CLUSTER_IDX]}
    CLUSTER_ZONE=${CLUSTER_ZONES[$CLUSTER_IDX]}
}

connect_to_cluster() {
    step "Step 3: Connect to cluster"
    if ! gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_ZONE" --project "$PROJECT_ID"; then
        error "Failed to connect to cluster. Exiting."
        exit 1
    fi
    success "Connected to cluster $CLUSTER_NAME in zone $CLUSTER_ZONE."
}

# Main execution
select_gcp_project
select_cluster
connect_to_cluster
