#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared_vpc.sh"

# Globals set by this module
VPC_NAME=""
SUBNET_NAME=""
IS_SHARED_VPC="false"
NAT_IP_NAME=""

# get_node_subnet_cidr: returns /26 block from a /24 CIDR
get_node_subnet_cidr() {
    local base_ip
    base_ip=$(echo "$1" | cut -d'/' -f1)
    echo "${base_ip}/26"
}

# calculate_secondary_ranges: subdivide /24 into node/svc/pod blocks
calculate_secondary_ranges() {
    local base_ip o1 o2 o3 o4
    base_ip=$(echo "$1" | cut -d'/' -f1)
    o1=$(echo "$base_ip" | cut -d'.' -f1)
    o2=$(echo "$base_ip" | cut -d'.' -f2)
    o3=$(echo "$base_ip" | cut -d'.' -f3)
    o4=$(echo "$base_ip" | cut -d'.' -f4)
    echo "servicios=${o1}.${o2}.${o3}.$(( o4 + 64 ))/26,pods=${o1}.${o2}.${o3}.$(( o4 + 128 ))/25"
}

# validate_secondary_ranges: verify subnet has secondary ranges
validate_secondary_ranges() {
    local subnet="$1"
    if [ -z "$subnet" ]; then
        error "Subnet name required for validation"
        return 1
    fi

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping secondary range validation"
        return 0
    fi

    local ranges
    ranges=$(gcloud compute networks subnets describe "$subnet" \
        --project="${project_id:-}" --region="${region:-us-central1}" \
        --format="json" 2>/dev/null \
        | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)

    if [ -z "$ranges" ]; then
        error "No secondary ranges found in subnet '$subnet'"
        return 1
    fi
    success "Secondary ranges validated in '$subnet': $(echo "$ranges" | tr '\n' ' ')"
}

# cmd_vpc_select: interactive VPC selection
# Sets globals: VPC_NAME, SUBNET_NAME, IS_SHARED_VPC, SHARED_HOST,
#               PODS_RANGE_NAME, SERVICES_RANGE_NAME
cmd_vpc_select() {
    step "VPC Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping VPC selection — using defaults"
        VPC_NAME="${project_id:-test-vpc}"
        SUBNET_NAME="${project_id:-test-subnet}"
        PODS_RANGE_NAME="pods"
        SERVICES_RANGE_NAME="servicios"
        IS_SHARED_VPC="false"
        _setup_cloud_nat
        return 0
    fi

    local vpc_exists
    vpc_exists=$(gcloud compute networks list --project="${project_id}" \
        --format="value(name)" 2>/dev/null | head -1 || true)

    local menu_opt
    if [ -n "$vpc_exists" ]; then
        info "Existing VPC detected: $vpc_exists"
        info "[1] Use existing VPC"
        info "[2] Create new VPC"
        info "[3] Use Shared VPC"
        read_input menu_opt "${CYAN}Select option [1-3]: ${NC}"
    else
        info "No VPC found in project."
        info "[1] Create new VPC"
        info "[2] Use Shared VPC"
        read_input menu_opt "${CYAN}Select option [1-2]: ${NC}"
        [ "$menu_opt" = "1" ] && menu_opt="2"
        [ "$menu_opt" = "2" ] && menu_opt="3"
    fi

    case "$menu_opt" in
        1)
            info "Available VPCs:"
            gcloud compute networks list --project="${project_id}" --format="table(name,subnetworkMode)"
            prompt_or_arg VPC_NAME "" "VPC name" "$vpc_exists"
            prompt_or_arg SUBNET_NAME "" "Subnet name" "$vpc_exists"
            local ranges
            ranges=$(gcloud compute networks subnets describe "$SUBNET_NAME" \
                --project="${project_id}" --region="${region}" \
                --format="json" 2>/dev/null \
                | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)
            if [ -z "$ranges" ]; then
                warn "No secondary ranges found in subnet '$SUBNET_NAME'"
                read_input PODS_RANGE_NAME "${CYAN}Enter pods range name (e.g. pods): ${NC}"
                read_input SERVICES_RANGE_NAME "${CYAN}Enter services range name (e.g. servicios): ${NC}"
                PODS_RANGE_NAME="${PODS_RANGE_NAME:-pods}"
                SERVICES_RANGE_NAME="${SERVICES_RANGE_NAME:-servicios}"
            else
                PODS_RANGE_NAME=$(echo "$ranges" | grep -E '^pods?$' | head -1 || echo "pods")
                SERVICES_RANGE_NAME=$(echo "$ranges" | grep -E '^servicios?$|^services?$' | head -1 || echo "servicios")
            fi
            ;;
        2)
            local vpc_ip
            read_input vpc_ip "${CYAN}Enter IP range for new VPC (e.g. 10.0.0.0/24): ${NC}"
            [ -z "$vpc_ip" ] && vpc_ip="10.0.0.0/24"

            run_or_dry gcloud compute networks create "${project_id}" \
                --project="${project_id}" \
                --subnet-mode=custom \
                --mtu=1460 \
                --bgp-routing-mode=regional 2>/dev/null || warn "VPC already exists"

            local secondary_ranges node_cidr
            secondary_ranges=$(calculate_secondary_ranges "$vpc_ip")
            node_cidr=$(get_node_subnet_cidr "$vpc_ip")

            run_or_dry gcloud compute networks subnets create "${project_id}" \
                --project="${project_id}" \
                --range="$node_cidr" \
                --stack-type=IPV4_ONLY \
                --network="${project_id}" \
                --region="${region}" \
                --secondary-range "$secondary_ranges" \
                --enable-private-ip-google-access 2>/dev/null || \
            run_or_dry gcloud compute networks subnets update "${project_id}" \
                --project="${project_id}" \
                --region="${region}" \
                --add-secondary-ranges "$secondary_ranges" 2>/dev/null || \
            warn "Secondary ranges already exist"

            VPC_NAME="${project_id}"
            SUBNET_NAME="${project_id}"
            PODS_RANGE_NAME="pods"
            SERVICES_RANGE_NAME="servicios"
            ;;
        3)
            IS_SHARED_VPC="true"
            prompt_or_arg SHARED_HOST "" "Host project ID" "gnp-red-data-central"
            prompt_or_arg VPC_NAME "" "Shared VPC name" "gnp-datalake-qa"
            prompt_or_arg SUBNET_NAME "" "Shared subnet name" "${project_id}"

            local ranges_mode
            read_input ranges_mode "${CYAN}Secondary ranges: [1] Auto-detect  [2] Manual: ${NC}"
            if [ "${ranges_mode:-1}" = "2" ]; then
                read_input PODS_RANGE_NAME "${CYAN}Pods range name: ${NC}"
                read_input SERVICES_RANGE_NAME "${CYAN}Services range name: ${NC}"
            else
                detect_secondary_ranges "$SUBNET_NAME" "$SHARED_HOST"
            fi
            ;;
        *)
            error "Invalid option: $menu_opt"
            return 1
            ;;
    esac

    success "VPC: $VPC_NAME"
    success "Subnet: $SUBNET_NAME"
    success "Pods range: ${PODS_RANGE_NAME:-auto}"
    success "Services range: ${SERVICES_RANGE_NAME:-auto}"

    _setup_cloud_nat
}

# _setup_cloud_nat: creates Cloud Router + NAT if needed
_setup_cloud_nat() {
    step "Cloud NAT Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud NAT setup"
        return 0
    fi

    local router_name="${project_id}-router"
    local nat_name="${project_id}-nat"

    local router_exists=false
    if gcloud compute routers describe "$router_name" \
        --region="${region}" --project="${project_id}" &>/dev/null; then
        router_exists=true
    fi

    if [ "$router_exists" = "true" ]; then
        if gcloud compute routers nats describe "$nat_name" \
            --router="$router_name" --region="${region}" --project="${project_id}" &>/dev/null; then
            success "Cloud NAT exists: $nat_name"
            return 0
        fi
        warn "Router exists but no NAT configured"
        local create_choice
        read_input create_choice "${CYAN}Create NAT on existing router? [1] Yes  [2] Skip: ${NC}"
        [ "${create_choice:-1}" = "2" ] && return 0
        _create_nat "$router_name" "$nat_name"
        return 0
    fi

    local env_lower
    env_lower=$(printf '%s' "${project_id}" | grep -oE '(pro|uat|qa)$' || echo "qa")
    local default_choice="2"
    if [ "$env_lower" = "pro" ]; then
        warn "PRO environment: Cloud NAT is recommended"
        default_choice="1"
    else
        info "QA/UAT environment: Cloud NAT is optional"
    fi

    local create_choice
    read_input create_choice "${CYAN}Create Cloud NAT and Router? [1] Yes  [2] Skip (default: $default_choice): ${NC}"
    [ "${create_choice:-$default_choice}" = "2" ] && return 0

    info "Creating Cloud Router: $router_name"
    if ! run_or_dry gcloud compute routers create "$router_name" \
        --network="${VPC_NAME}" \
        --region="${region}" \
        --project="${project_id}"; then
        error "Failed to create Cloud Router"
        return 1
    fi
    _create_nat "$router_name" "$nat_name"
}

_reserve_nat_ip() {
    local ip_name="${project_id}-nat-ip"
    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping static IP reservation"
        NAT_IP_NAME="$ip_name"
        return 0
    fi
    if gcloud compute addresses describe "$ip_name" \
        --region="${region}" --project="${project_id}" &>/dev/null; then
        success "Static IP exists: $ip_name"
    else
        info "Reserving static IP: $ip_name"
        run_or_dry gcloud compute addresses create "$ip_name" \
            --region="${region}" \
            --project="${project_id}"
    fi
    NAT_IP_NAME="$ip_name"
}

_create_nat() {
    local router_name="$1"
    local nat_name="$2"
    info "Creating Cloud NAT: $nat_name"
    run_or_dry gcloud compute routers nats create "$nat_name" \
        --router="$router_name" \
        --region="${region}" \
        --project="${project_id}" \
        --auto-allocate-nat-external-ips \
        --nat-all-subnet-ip-ranges \
        --icmp-idle-timeout=30s \
        --tcp-established-idle-timeout=1200s \
        --tcp-transitory-idle-timeout=30s \
        --udp-idle-timeout=30s
    success "Cloud NAT created: $nat_name"
}
