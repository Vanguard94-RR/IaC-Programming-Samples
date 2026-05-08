#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vpc.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hardening.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/twistlock.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssl.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workload_identity.sh"

# Globals set by parameter collection
project_id=""
cluster_name=""
region=""
zone=""
machine_type=""
num_nodes=""
channel=""
private_nodes=""
control_plane_ip=""
fleet_id=""
cluster_version=""
cluster_access_scope=""
authorized_cidr=""

get_cluster_versions() {
    local target_region="${1:-us-central1}"
    local target_channel="${2:-regular}"

    vprint "Fetching GKE versions for region $target_region, channel $target_channel" >&2

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        echo "1.31.0-gke.1000000"
        return 0
    fi

    local server_config
    server_config=$(gcloud container get-server-config \
        --region="$target_region" --format="json" 2>/dev/null || true)

    if [ -z "$server_config" ]; then
        warn "Could not fetch GKE server config — using default version" >&2
        echo "1.31.0-gke.1000000"
        return 0
    fi

    local version
    case "$target_channel" in
        rapid)   version=$(printf '%s' "$server_config" | jq -r '.channels[] | select(.channel=="RAPID") | .validVersions[0]') ;;
        regular) version=$(printf '%s' "$server_config" | jq -r '.channels[] | select(.channel=="REGULAR") | .validVersions[0]') ;;
        stable)  version=$(printf '%s' "$server_config" | jq -r '.channels[] | select(.channel=="STABLE") | .validVersions[0]') ;;
        *) error "Invalid channel: $target_channel" >&2; return 1 ;;
    esac

    if [ -z "$version" ]; then
        warn "Could not parse version for channel $target_channel — using default" >&2
        echo "1.31.0-gke.1000000"
        return 0
    fi

    success "GKE version for $target_channel: $version" >&2
    echo "$version"
}

register_fleet() {
    step "Fleet Registration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Fleet registration"
        return 0
    fi

    local fleet_project_number
    fleet_project_number=$(gcloud projects describe "$fleet_id" \
        --format="value(projectNumber)" 2>/dev/null || true)

    if [ -z "$fleet_project_number" ]; then
        error "Could not get project number for fleet: $fleet_id"
        return 1
    fi

    run_or_dry gcloud projects add-iam-policy-binding "$project_id" \
        --member="serviceAccount:service-${fleet_project_number}@gcp-sa-gkehub.iam.gserviceaccount.com" \
        --role="roles/container.serviceAgent" \
        --quiet 2>/dev/null || warn "IAM binding already exists"

    local gke_uri="https://container.googleapis.com/v1/projects/${project_id}/locations/${region}/clusters/${cluster_name}"
    run_or_dry gcloud container fleet memberships register "$cluster_name" \
        --project="$fleet_id" \
        --gke-uri="$gke_uri" \
        --location=global \
        --enable-workload-identity \
        --quiet 2>/dev/null || warn "Already registered in fleet"

    success "Cluster registered in fleet: $fleet_id"
}

_collect_params() {
    step "Cluster Parameters"

    prompt_or_arg project_id "${ARG_PROJECT:-}" "GCP Project ID" ""
    [ -z "$project_id" ] && { error "project_id required"; return 1; }

    prompt_or_arg cluster_name "${ARG_CLUSTER:-}" "Cluster name" "gke-${project_id}"
    prompt_or_arg region "${ARG_REGION:-}" "GCP region" "us-central1"

    local env="${ARG_ENV:-}"
    if [ -z "$env" ]; then
        case "$project_id" in
            *-pro) env="pro" ;;
            *-uat) env="uat" ;;
            *)     env="qa"  ;;
        esac
    fi
    info "Environment: $env"
    case "$env" in
        pro)
            machine_type="${machine_type:-n2-standard-2}"
            channel="${channel:-regular}"
            num_nodes="${num_nodes:-2}"
            fleet_id="${fleet_id:-gnp-fleets-pro}"
            ;;
        uat)
            machine_type="${machine_type:-n1-standard-2}"
            channel="${channel:-rapid}"
            num_nodes="${num_nodes:-2}"
            fleet_id="${fleet_id:-gnp-fleets-uat}"
            ;;
        qa|*)
            machine_type="${machine_type:-n1-standard-2}"
            channel="${channel:-rapid}"
            num_nodes="${num_nodes:-1}"
            fleet_id="${fleet_id:-gnp-fleets-qa}"
            ;;
    esac

    prompt_or_arg machine_type "$machine_type" "Machine type" "$machine_type"
    prompt_or_arg num_nodes "$num_nodes" "Number of nodes" "$num_nodes"
    prompt_or_arg channel "$channel" "Release channel (rapid|regular|stable)" "$channel"
    prompt_or_arg fleet_id "$fleet_id" "Fleet project ID" "$fleet_id"

    zone="${region}-f"
    info "Zone: $zone"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        private_nodes="true"
        control_plane_ip="172.19.0.0/28"
        cluster_access_scope="gke-default"
        return 0
    fi

    local cluster_type
    read_input cluster_type "${CYAN}Cluster type: [1] Private  [2] Public (default: 1): ${NC}"
    if [ "${cluster_type:-1}" = "2" ]; then
        private_nodes="false"
    else
        private_nodes="true"
        read_input control_plane_ip "${CYAN}Control plane CIDR (e.g. 172.19.0.0/28): ${NC}"
        control_plane_ip="${control_plane_ip:-172.19.0.0/28}"
        local current_ip
        current_ip=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null \
            || curl -4 -s --max-time 5 api.ipify.org 2>/dev/null \
            || true)
        if [ -n "$current_ip" ]; then
            local ip3 ip4_net
            ip3=$(echo "$current_ip" | cut -d. -f1-3)
            ip4_net=$(( $(echo "$current_ip" | cut -d. -f4) & 240 ))
            authorized_cidr="${ip3}.${ip4_net}/28"
            info "Authorizing control plane access: ${authorized_cidr}"
        else
            warn "Could not detect public IP — control plane may be unreachable after create"
        fi
    fi

    local scope_choice
    read_input scope_choice "${CYAN}API access scope: [1] Default  [2] Full (default: 1): ${NC}"
    if [ "${scope_choice:-1}" = "2" ]; then
        cluster_access_scope="https://www.googleapis.com/auth/cloud-platform"
    else
        cluster_access_scope="gke-default"
    fi
}

_build_cluster_flags() {
    local location_flag node_locations_flag private_flags
    location_flag="--region=${region}"
    node_locations_flag="--node-locations=${zone}"

    if [ "$private_nodes" = "true" ]; then
        local authorized_net=""
        [ -n "${authorized_cidr:-}" ] && authorized_net="--master-authorized-networks=${authorized_cidr}"
        private_flags="--enable-private-nodes --master-ipv4-cidr=${control_plane_ip} --enable-master-authorized-networks ${authorized_net}"
    else
        private_flags="--no-enable-private-nodes"
    fi

    local network_flags
    if [ "${IS_SHARED_VPC:-false}" = "true" ]; then
        network_flags="--network=projects/${SHARED_HOST}/global/networks/${VPC_NAME} --subnetwork=projects/${SHARED_HOST}/regions/${region}/subnetworks/${SUBNET_NAME}"
    else
        network_flags="--network=projects/${project_id}/global/networks/${VPC_NAME} --subnetwork=projects/${project_id}/regions/${region}/subnetworks/${SUBNET_NAME}"
    fi

    printf '%s' "$location_flag $node_locations_flag $private_flags $network_flags"
}

cmd_create() {
    print_banner_box "GKE Cluster Creation — v4.0"

    _collect_params

    step "Enabling GCP APIs"
    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping API enablement"
    else
        for api in container.googleapis.com gkehub.googleapis.com compute.googleapis.com; do
            run_or_dry gcloud services enable "$api" --project="$project_id" 2>/dev/null \
                || warn "$api already enabled"
        done
        success "APIs enabled"
    fi

    cmd_vpc_select

    if [ "${IS_SHARED_VPC:-false}" = "true" ]; then
        configure_shared_vpc_permissions "$project_id" "$SHARED_HOST"
    fi

    step "GKE Version"
    cluster_version=$(get_cluster_versions "$region" "$channel")
    info "Cluster version: $cluster_version"

    step "Creating GKE Cluster: $cluster_name"
    local cluster_flags
    cluster_flags=$(_build_cluster_flags)

    # shellcheck disable=SC2086
    run_or_dry gcloud container clusters create "$cluster_name" \
        --project="$project_id" \
        $cluster_flags \
        --release-channel="$channel" \
        --cluster-version="$cluster_version" \
        --machine-type="$machine_type" \
        --image-type="COS_CONTAINERD" \
        --disk-type="pd-balanced" \
        --disk-size="100" \
        --metadata=disable-legacy-endpoints=true \
        --num-nodes="$num_nodes" \
        --logging=SYSTEM,WORKLOAD \
        --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,CADVISOR,KUBELET \
        --scopes="$cluster_access_scope" \
        --no-enable-intra-node-visibility \
        --enable-ip-alias \
        --max-pods-per-node=64 \
        --cluster-secondary-range-name="${PODS_RANGE_NAME}" \
        --services-secondary-range-name="${SERVICES_RANGE_NAME}" \
        --security-posture=standard \
        --workload-vulnerability-scanning=disabled \
        --no-enable-google-cloud-access \
        --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,GcpFilestoreCsiDriver \
        --enable-autoupgrade \
        --enable-autorepair \
        --max-surge-upgrade=1 \
        --max-unavailable-upgrade=0 \
        --binauthz-evaluation-mode=DISABLED \
        --enable-managed-prometheus \
        --enable-shielded-nodes \
        --shielded-secure-boot \
        --shielded-integrity-monitoring \
        --enable-secret-manager \
        --workload-pool="${project_id}.svc.id.goog"

    if [ "${NO_CLUSTER:-0}" != "1" ]; then
        if ! gcloud container clusters describe "$cluster_name" \
            --project="$project_id" --region="$region" &>/dev/null; then
            error "Cluster creation failed"
            return 1
        fi
    fi
    success "Cluster created: $cluster_name"

    register_fleet

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        _print_cluster_summary
        return 0
    fi

    apply_cluster_hardening
    create_ssl_certificate

    if [[ "$project_id" =~ -pro$ ]]; then
        local confirm_twistlock
        read_input confirm_twistlock "${CYAN}Deploy Twistlock? (Y/N): ${NC}"
        [[ "${confirm_twistlock:-N}" =~ ^[Yy]$ ]] && deploy_twistlock
    fi

    local confirm_wi
    read_input confirm_wi "${CYAN}Create Workload Identity assets? (Y/N): ${NC}"
    [[ "${confirm_wi:-N}" =~ ^[Yy]$ ]] && create_workload_identity_assets

    _print_cluster_summary
}

_print_cluster_summary() {
    printf '\n'
    printf '%b\n' "${CYAN}╔══════════════════════════════════════╗${NC}"
    printf '%b\n' "${CYAN}║         CLUSTER CREATED              ║${NC}"
    printf '%b\n' "${CYAN}╠══════════════════════════════════════╣${NC}"
    printf "%b\n" "${CYAN}║${NC} Project:  ${WHITE}${project_id}${NC}"
    printf "%b\n" "${CYAN}║${NC} Cluster:  ${WHITE}${cluster_name}${NC}"
    printf "%b\n" "${CYAN}║${NC} Fleet:    ${WHITE}${fleet_id}${NC}"
    printf "%b\n" "${CYAN}║${NC} Region:   ${WHITE}${region}${NC}"
    printf "%b\n" "${CYAN}║${NC} VPC:      ${WHITE}${VPC_NAME}${NC}"
    printf "%b\n" "${CYAN}║${NC} Version:  ${WHITE}${cluster_version}${NC}"
    printf '%b\n' "${CYAN}╚══════════════════════════════════════╝${NC}"
    printf '\n'
}
