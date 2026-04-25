#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# Globals set by this module (used by cluster.sh)
SHARED_HOST=""
IS_SHARED_VPC="false"
PODS_RANGE_NAME=""
SERVICES_RANGE_NAME=""

# --- Subcommand: fix-shared-vpc ---
cmd_fix_shared_vpc() {
    step "Fix Shared VPC Association"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Shared VPC association"
        return 0
    fi

    local service_project host_project
    prompt_or_arg service_project "" "Service project ID" ""
    prompt_or_arg host_project "" "Host project ID" "gnp-red-data-central"

    if [ -z "$service_project" ] || [ -z "$host_project" ]; then
        error "Both service_project and host_project are required"
        return 1
    fi

    step "Verifying current association"
    local current
    current=$(run_or_dry gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep "^${service_project}$" || true)

    if [ -n "$current" ]; then
        local xpn_host
        xpn_host=$(run_or_dry gcloud compute shared-vpc get-host-project "$service_project" 2>/dev/null || true)
        if [ "$xpn_host" = "$host_project" ]; then
            success "Project already associated correctly"
            return 0
        fi
        warn "Inconsistency detected — host expected: $host_project, got: $xpn_host"
    fi

    step "Verifying permissions on host project"
    local current_user
    current_user=$(gcloud config get-value account 2>/dev/null)
    info "Current user: $current_user"

    local user_roles
    user_roles=$(gcloud projects get-iam-policy "$host_project" \
        --flatten="bindings[].members" \
        --filter="bindings.members:user:$current_user" \
        --format="value(bindings.role)" 2>/dev/null \
        | grep -E "(roles/compute.xpnAdmin|roles/owner)" || true)

    if [ -z "$user_roles" ]; then
        error "Insufficient permissions on host project $host_project"
        info "Required: roles/compute.xpnAdmin or roles/owner"
        info "Request: gcloud projects add-iam-policy-binding $host_project \\"
        info "    --member=\"user:$current_user\" --role=\"roles/compute.xpnAdmin\""
        return 1
    fi
    success "Permissions verified: $user_roles"

    step "Associating project to Shared VPC"
    if run_or_dry gcloud compute shared-vpc associated-projects add "$service_project" \
        --host-project="$host_project"; then
        success "Project associated"
    else
        error "Association failed"
        return 1
    fi

    step "Verifying association"
    sleep 3
    local verified
    verified=$(run_or_dry gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep "^${service_project}$" || true)

    if [ -n "$verified" ]; then
        success "Association verified"
        info "Now re-run: ./bin/create_gke_cluster.sh create --project $service_project"
    else
        error "Association could not be verified"
        return 1
    fi
}

# --- configure_shared_vpc_permissions ---
configure_shared_vpc_permissions() {
    local service_project="$1"
    local host_project="$2"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping IAM bindings"
        return 0
    fi

    step "Configuring Shared VPC IAM permissions"

    local service_project_number
    service_project_number=$(gcloud projects describe "$service_project" \
        --format="value(projectNumber)" 2>/dev/null)

    if [ -z "$service_project_number" ]; then
        error "Could not get project number for: $service_project"
        return 1
    fi

    local gke_sa="service-${service_project_number}@container-engine-robot.iam.gserviceaccount.com"
    local api_sa="${service_project_number}@cloudservices.gserviceaccount.com"

    local xpn_status
    xpn_status=$(gcloud compute project-info describe --project="$host_project" \
        --format="value(xpnProjectStatus)" 2>/dev/null || true)

    if [ "$xpn_status" != "HOST" ]; then
        info "Enabling $host_project as Shared VPC host..."
        if ! run_or_dry gcloud compute shared-vpc enable "$host_project"; then
            error "Could not enable Shared VPC host. Run fix-shared-vpc subcommand."
            return 1
        fi
        sleep 3
    fi
    success "Host project $host_project is Shared VPC host"

    local associated
    associated=$(gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep "^${service_project}$" || true)

    if [ -z "$associated" ]; then
        info "Associating $service_project to $host_project..."
        if ! run_or_dry gcloud compute shared-vpc associated-projects add "$service_project" \
            --host-project="$host_project"; then
            error "Association failed. Run fix-shared-vpc subcommand."
            return 1
        fi
        sleep 5
    fi
    success "Project associated to Shared VPC"

    for sa in "$gke_sa" "$api_sa"; do
        info "Granting roles/compute.networkUser to $sa..."
        run_or_dry gcloud projects add-iam-policy-binding "$host_project" \
            --member="serviceAccount:${sa}" \
            --role="roles/compute.networkUser" \
            --condition=None \
            --quiet 2>/dev/null || warn "Role already assigned"
    done

    info "Granting roles/container.hostServiceAgentUser to $gke_sa..."
    run_or_dry gcloud projects add-iam-policy-binding "$host_project" \
        --member="serviceAccount:${gke_sa}" \
        --role="roles/container.hostServiceAgentUser" \
        --condition=None \
        --quiet 2>/dev/null || warn "Role already assigned"

    info "Waiting for IAM propagation (10s)..."
    sleep 10
    success "Shared VPC IAM permissions configured"
}

# --- detect_secondary_ranges ---
detect_secondary_ranges() {
    local subnet="${1:-}"
    local host_project="${2:-}"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping secondary range detection"
        PODS_RANGE_NAME="pods"
        SERVICES_RANGE_NAME="servicios"
        return 0
    fi

    step "Detecting secondary ranges in subnet '$subnet'"

    if ! command -v jq &>/dev/null; then
        error "jq is required for secondary range detection"
        return 1
    fi

    local subnet_details
    subnet_details=$(gcloud compute networks subnets describe "$subnet" \
        --project="$host_project" \
        --region="${region:-us-central1}" \
        --format="json" 2>/dev/null || true)

    if [ -z "$subnet_details" ]; then
        warn "Subnet '$subnet' not found in project '$host_project'"
        local create_confirm
        read_input create_confirm "${CYAN}Create subnet now? (Y/N): ${NC}"
        if [[ ! "$create_confirm" =~ ^[Yy]$ ]]; then
            error "Cannot continue without subnet. Aborting."
            return 1
        fi
        _create_shared_subnet "$subnet" "$host_project"
        return $?
    fi

    local all_ranges
    all_ranges=$(printf '%s' "$subnet_details" | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)

    if [ -z "$all_ranges" ]; then
        error "Subnet '$subnet' has no secondary IP ranges configured"
        return 1
    fi

    info "Secondary ranges found:"
    while IFS= read -r rng; do
        local cidr
        cidr=$(printf '%s' "$subnet_details" \
            | jq -r --arg n "$rng" '.secondaryIpRanges[] | select(.rangeName==$n) | .ipCidrRange')
        info "  • $rng → $cidr"
    done <<< "$all_ranges"

    local pods_range=""
    while IFS= read -r rng; do
        if [[ "$rng" =~ ^pods?$ ]]; then
            pods_range="$rng"
            break
        fi
    done <<< "$all_ranges"

    local svcs_range=""
    while IFS= read -r rng; do
        if [[ "$rng" =~ ^servicios?$|^services?$ ]]; then
            svcs_range="$rng"
            break
        fi
    done <<< "$all_ranges"

    if [ -z "$pods_range" ] || [ -z "$svcs_range" ]; then
        warn "Could not auto-detect range names"
        info "Available ranges: $(echo "$all_ranges" | tr '\n' ' ')"
        read_input pods_range "${CYAN}Enter pods range name: ${NC}"
        read_input svcs_range "${CYAN}Enter services range name: ${NC}"
    fi

    PODS_RANGE_NAME="$pods_range"
    SERVICES_RANGE_NAME="$svcs_range"
    success "Pods range: $PODS_RANGE_NAME"
    success "Services range: $SERVICES_RANGE_NAME"
}

_create_shared_subnet() {
    local subnet="$1"
    local host_project="$2"
    local primary_cidr pods_cidr svcs_cidr

    read_input primary_cidr "${CYAN}Primary CIDR for nodes (e.g. 10.97.231.0/24): ${NC}"
    read_input pods_cidr    "${CYAN}CIDR for Pods (e.g. 10.83.24.0/21): ${NC}"
    read_input svcs_cidr    "${CYAN}CIDR for Services (e.g. 10.82.232.0/21): ${NC}"

    if [ -z "$primary_cidr" ] || [ -z "$pods_cidr" ] || [ -z "$svcs_cidr" ]; then
        error "All three CIDRs are required"
        return 1
    fi

    if run_or_dry gcloud compute networks subnets create "$subnet" \
        --project="$host_project" \
        --network="${VPC_NAME:-}" \
        --region="${region:-us-central1}" \
        --range="$primary_cidr" \
        --secondary-range="pods=${pods_cidr},servicios=${svcs_cidr}" \
        --enable-private-ip-google-access; then
        PODS_RANGE_NAME="pods"
        SERVICES_RANGE_NAME="servicios"
        success "Subnet created"
    else
        error "Failed to create subnet '$subnet'"
        return 1
    fi
}
