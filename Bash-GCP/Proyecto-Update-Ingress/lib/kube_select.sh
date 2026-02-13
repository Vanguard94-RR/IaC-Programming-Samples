#!/usr/bin/env bash
# Cluster and resource selection helpers (extracted from kube.sh)

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

# If a cleanup_temp_files function exists in other modules, ensure it's called on exit
if declare -f cleanup_temp_files >/dev/null 2>&1; then
    trap cleanup_temp_files EXIT INT TERM
fi

select_gcp_project() {
    step "Step 1: Select your GCP project"
    while true; do
        read_input PROJECT_ID "${CYAN}Enter your project ID:${NC} ${WHITE}${BOLD}"
        printf '%b' "${NC}"
        if [ -z "$PROJECT_ID" ]; then
            echo -e "${RED}Project ID cannot be empty. Please try again.${NC}"
            continue
        fi
        info "Setting project to: $PROJECT_ID"
        if gcloud config set project "$PROJECT_ID" 2>/dev/null; then
            success "Project set successfully."
            break
        else
            echo -e "${RED}Failed to set project. Please check the project ID and try again.${NC}"
        fi
    done
}

select_cluster() {
    step "Step 2: Select your Kubernetes cluster"
    if ! CLUSTERS_INFO=$(gcloud container clusters list --format="value(name,zone)" 2>/dev/null); then
        echo -e "${RED}Failed to list clusters. Exiting.${NC}"
        exit 1
    fi
    if [ -z "$CLUSTERS_INFO" ]; then
        echo -e "${RED}No clusters found in project. Exiting.${NC}"
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
        echo -e "${RED}No clusters found in project. Exiting.${NC}"
        exit 1
    fi

    while true; do
        read_input CLUSTER_NUM "${CYAN}Enter the cluster number:${NC} ${WHITE}${BOLD}"
        printf '%b' "${NC}"
        if validate_number "$CLUSTER_NUM" "$max_clusters"; then
            break
        fi
    done

    CLUSTER_IDX=$((CLUSTER_NUM-1))
    CLUSTER_NAME=${CLUSTER_NAMES[$CLUSTER_IDX]}
    CLUSTER_ZONE=${CLUSTER_ZONES[$CLUSTER_IDX]}
}

connect_to_cluster() {
    echo -e "\n${YELLOW}Step 3: Connect to cluster${NC}"
    if ! gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_ZONE" --project "$PROJECT_ID"; then
        echo -e "${RED}Failed to connect to cluster. Exiting.${NC}"
        exit 1
    fi
}

namespace_and_ingress_name() {
    step "Step 4: Select the Ingress to update"
    if ! INGRESS_LIST=$(kubectl get ingress --all-namespaces -o custom-columns=NS:metadata.namespace,NAME:metadata.name --no-headers 2>/dev/null); then
        echo -e "${RED}Failed to list Ingress resources. Exiting.${NC}"
        exit 1
    fi
    if [ -z "$INGRESS_LIST" ]; then
        echo -e "${RED}No Ingress resources found in any namespace. Exiting.${NC}"
        exit 1
    fi

    INGRESS_NAMES=()
    INGRESS_NAMESPACES=()
    INGRESS_TABLE=""
    INDEX=1

    INGRESS_TABLE+="\n+----+-------------------------+---------------------+\n"
    INGRESS_TABLE+="| #  | Ingress Name            | Namespace           |\n"
    INGRESS_TABLE+="+----+-------------------------+---------------------+\n"
    while read -r line; do
        if [ -n "$line" ]; then
            ns=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            INGRESS_NAMESPACES+=("$ns")
            INGRESS_NAMES+=("$name")
            INGRESS_TABLE+="| $(printf '%-2s' "$INDEX") | $(printf '%-23s' "$name") | $(printf '%-19s' "$ns") |\n"
            INDEX=$((INDEX+1))
        fi
    done <<< "$INGRESS_LIST"
    INGRESS_TABLE+="+----+-------------------------+---------------------+\n"
    printf "%b" "$INGRESS_TABLE"

    local max_ingress=$((INDEX-1))
    if [ $max_ingress -eq 0 ]; then
        echo -e "${RED}No Ingress resources found. Exiting.${NC}"
        exit 1
    fi

    while true; do
        read_input INGRESS_NUM "${CYAN}Enter the ingress number:${NC} ${WHITE}${BOLD}"
        printf '%b' "${NC}"
        if validate_number "$INGRESS_NUM" "$max_ingress"; then
            break
        fi
    done

    INGRESS_IDX=$((INGRESS_NUM-1))
    INGRESS_NAME=${INGRESS_NAMES[$INGRESS_IDX]}
    NAMESPACE=${INGRESS_NAMESPACES[$INGRESS_IDX]}
    echo -e "${YELLOW}Selected ingress: ${CYAN}$INGRESS_NAME${NC} in namespace: ${CYAN}$NAMESPACE${NC}"
}
