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


# cmd_vpc_select: interactive VPC selection
# Sets globals: VPC_NAME, SUBNET_NAME, IS_SHARED_VPC, SHARED_HOST
# PODS_RANGE_NAME, SERVICES_RANGE_NAME set only for existing/shared VPC paths
# (new VPC path leaves them empty — GKE auto-allocates secondary ranges)
cmd_vpc_select() {
    step "VPC Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping VPC selection — using defaults"
        VPC_NAME="${project_id:-test-vpc}"
        SUBNET_NAME="${project_id:-test-subnet}"
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
        case "$menu_opt" in
            1) menu_opt="2" ;;
            2) menu_opt="3" ;;
        esac
    fi

    case "$menu_opt" in
        1)
            info "Available VPCs:"
            gcloud compute networks list --project="${project_id}" --format="table(name,subnetworkMode)"
            prompt_or_arg VPC_NAME "$vpc_exists" "VPC name" "$vpc_exists"
            local detected_subnet
            # shellcheck disable=SC2154
            detected_subnet=$(gcloud compute networks subnets list \
                --network="$VPC_NAME" \
                --project="${project_id}" \
                --filter="region:${region} AND NOT name~^gke-" \
                --format="value(name)" 2>/dev/null | head -1 || true)
            prompt_or_arg SUBNET_NAME "$detected_subnet" "Subnet name" "${detected_subnet:-$VPC_NAME}"
            if ! gcloud compute networks subnets describe "$SUBNET_NAME" \
                --project="${project_id}" --region="${region}" &>/dev/null; then
                error "Subnet '$SUBNET_NAME' not found in region '${region}'. Use option 2 to create it."
                return 1
            fi
            local ranges
            ranges=$(gcloud compute networks subnets describe "$SUBNET_NAME" \
                --project="${project_id}" --region="${region}" \
                --format="json" 2>/dev/null \
                | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)
            if [ -z "$ranges" ]; then
                warn "No secondary ranges found in subnet '$SUBNET_NAME'"
                read_input PODS_RANGE_NAME "${CYAN}Pods range name: ${NC}"
                read_input SERVICES_RANGE_NAME "${CYAN}Services range name: ${NC}"
                if [ -z "$PODS_RANGE_NAME" ] || [ -z "$SERVICES_RANGE_NAME" ]; then
                    error "Both pods and services range names required — subnet has no secondary ranges"
                    return 1
                fi
                local pods_cidr services_cidr
                read_input pods_cidr "${CYAN}Pods CIDR     (default: 10.96.0.0/14): ${NC}"
                [ -z "$pods_cidr" ] && pods_cidr="10.96.0.0/14"
                read_input services_cidr "${CYAN}Services CIDR (default: 10.100.0.0/20): ${NC}"
                [ -z "$services_cidr" ] && services_cidr="10.100.0.0/20"
                info "Creating secondary ranges in subnet '$SUBNET_NAME'"
                if ! run_or_dry gcloud compute networks subnets update "$SUBNET_NAME" \
                    --project="${project_id}" --region="${region}" \
                    --add-secondary-ranges="${PODS_RANGE_NAME}=${pods_cidr},${SERVICES_RANGE_NAME}=${services_cidr}"; then
                    error "Failed to create secondary ranges in $SUBNET_NAME"
                    return 1
                fi
                success "Secondary ranges created: ${PODS_RANGE_NAME}=${pods_cidr}, ${SERVICES_RANGE_NAME}=${services_cidr}"
            else
                local pods_match services_match
                pods_match=$(echo "$ranges" | grep -E '^pods?$' | head -1 || true)
                services_match=$(echo "$ranges" | grep -E '^servicios?$|^services?$' | head -1 || true)
                if [ -z "$pods_match" ] || [ -z "$services_match" ]; then
                    info "Secondary ranges in '$SUBNET_NAME': $(echo "$ranges" | tr '\n' ' ')"
                    [ -z "$pods_match" ] && read_input pods_match "${CYAN}Which range is pods? ${NC}"
                    [ -z "$services_match" ] && read_input services_match "${CYAN}Which range is services? ${NC}"
                    if [ -z "$pods_match" ] || [ -z "$services_match" ]; then
                        error "Both pods and services range names required"
                        return 1
                    fi
                fi
                PODS_RANGE_NAME="$pods_match"
                SERVICES_RANGE_NAME="$services_match"
            fi
            ;;
        2)
            local vpc_ip
            read_input vpc_ip "${CYAN}Enter IP range for new VPC (e.g. 10.100.20.0/22): ${NC}"
            [ -z "$vpc_ip" ] && vpc_ip="10.0.0.0/22"

            if ! echo "$vpc_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
                error "Invalid CIDR format: $vpc_ip (expected x.x.x.x/prefix)"
                return 1
            fi

            local new_vpc_name="${project_id}-vpc"
            local new_subnet_name="${project_id}-subnet"

            run_or_dry gcloud compute networks create "$new_vpc_name" \
                --project="${project_id}" \
                --subnet-mode=custom \
                --mtu=1460 \
                --bgp-routing-mode=regional 2>/dev/null || warn "VPC already exists"

            if ! run_or_dry gcloud compute networks subnets create "$new_subnet_name" \
                --project="${project_id}" \
                --range="$vpc_ip" \
                --stack-type=IPV4_ONLY \
                --network="$new_vpc_name" \
                --region="${region}" \
                --enable-private-ip-google-access; then
                error "Failed to create subnet $new_subnet_name"
                return 1
            fi

            VPC_NAME="$new_vpc_name"
            SUBNET_NAME="$new_subnet_name"

            local pods_cidr services_cidr
            read_input pods_cidr "${CYAN}Pods CIDR     (default: 10.96.0.0/14): ${NC}"
            [ -z "$pods_cidr" ] && pods_cidr="10.96.0.0/14"
            read_input services_cidr "${CYAN}Services CIDR (default: 10.100.0.0/20): ${NC}"
            [ -z "$services_cidr" ] && services_cidr="10.100.0.0/20"

            PODS_RANGE_NAME="${project_id}-pods"
            SERVICES_RANGE_NAME="${project_id}-services"

            if ! run_or_dry gcloud compute networks subnets update "$new_subnet_name" \
                --project="${project_id}" \
                --region="${region}" \
                --add-secondary-ranges="${PODS_RANGE_NAME}=${pods_cidr},${SERVICES_RANGE_NAME}=${services_cidr}"; then
                error "Failed to add secondary ranges to $new_subnet_name"
                return 1
            fi
            ;;
        3)
            # shellcheck disable=SC2034
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

# _setup_cloud_nat: creates Cloud Router + NAT — mandatory for all envs (qa/uat/pro), always fixed static IP
_setup_cloud_nat() {
    step "Cloud NAT Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud NAT setup"
        return 0
    fi

    local router_name="${project_id}-router"
    local nat_name="${project_id}-nat"

    if gcloud compute routers describe "$router_name" \
        --region="${region}" --project="${project_id}" &>/dev/null; then
        if gcloud compute routers nats describe "$nat_name" \
            --router="$router_name" --region="${region}" --project="${project_id}" &>/dev/null; then
            success "Cloud NAT exists: $nat_name"
            return 0
        fi
        info "Router exists, creating NAT: $nat_name"
    else
        info "Creating Cloud Router: $router_name"
        if ! run_or_dry gcloud compute routers create "$router_name" \
            --network="${VPC_NAME}" \
            --region="${region}" \
            --project="${project_id}"; then
            error "Failed to create Cloud Router"
            return 1
        fi
    fi

    _reserve_nat_ip
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
        --nat-external-ip-pool="${NAT_IP_NAME}" \
        --nat-all-subnet-ip-ranges \
        --icmp-idle-timeout=30s \
        --tcp-established-idle-timeout=1200s \
        --tcp-transitory-idle-timeout=30s \
        --udp-idle-timeout=30s
    success "Cloud NAT created: $nat_name"
}
