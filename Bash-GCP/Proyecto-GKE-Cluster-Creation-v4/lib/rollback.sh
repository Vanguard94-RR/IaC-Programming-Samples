#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

_rollback_fleet() {
    local project_id="$1" cluster_name="$2" fleet_id="$3"
    step "Fleet: Unregister"

    if gcloud container fleet memberships describe "$cluster_name" \
        --project="$fleet_id" --location=global &>/dev/null; then
        if run_or_dry gcloud container fleet memberships delete "$cluster_name" \
            --project="$fleet_id" \
            --location=global \
            --quiet; then
            success "Fleet membership removed: $cluster_name"
        else
            warn "Fleet membership delete failed — may need manual cleanup"
        fi
    else
        info "Fleet membership not found: $cluster_name — skipping"
    fi
}

_rollback_cluster() {
    local project_id="$1" cluster_name="$2" region="$3"
    step "GKE Cluster: Delete"

    if gcloud container clusters describe "$cluster_name" \
        --project="$project_id" --region="$region" &>/dev/null; then
        if run_or_dry gcloud container clusters delete "$cluster_name" \
            --project="$project_id" \
            --region="$region" \
            --quiet; then
            success "Cluster deleted: $cluster_name"
        else
            warn "Cluster delete failed"
        fi
    else
        info "Cluster not found: $cluster_name — skipping"
    fi
}

_rollback_workload_identity() {
    local project_id="$1"
    step "Workload Identity: Delete IAM SA"
    local iam_sa="apps-sa@${project_id}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$iam_sa" \
        --project="$project_id" &>/dev/null; then
        if run_or_dry gcloud iam service-accounts delete "$iam_sa" \
            --project="$project_id" \
            --quiet; then
            success "IAM SA deleted: $iam_sa"
        else
            warn "IAM SA delete failed"
        fi
    else
        info "IAM SA not found: $iam_sa — skipping"
    fi
}

_rollback_nat() {
    local project_id="$1" region="$2"
    step "Cloud NAT: Delete"
    local router_name="${project_id}-router"
    local nat_name="${project_id}-nat"
    local nat_ip="${project_id}-nat-ip"

    if gcloud compute routers describe "$router_name" \
        --region="$region" --project="$project_id" &>/dev/null; then
        if gcloud compute routers nats describe "$nat_name" \
            --router="$router_name" --region="$region" --project="$project_id" &>/dev/null; then
            if run_or_dry gcloud compute routers nats delete "$nat_name" \
                --router="$router_name" \
                --region="$region" \
                --project="$project_id" \
                --quiet; then
                success "NAT deleted: $nat_name"
            else
                warn "NAT delete failed"
            fi
        else
            info "NAT not found: $nat_name — skipping"
        fi
        if run_or_dry gcloud compute routers delete "$router_name" \
            --region="$region" \
            --project="$project_id" \
            --quiet; then
            success "Router deleted: $router_name"
        else
            warn "Router delete failed"
        fi
    else
        info "Router not found: $router_name — skipping"
    fi

    if gcloud compute addresses describe "$nat_ip" \
        --region="$region" --project="$project_id" &>/dev/null; then
        if run_or_dry gcloud compute addresses delete "$nat_ip" \
            --region="$region" \
            --project="$project_id" \
            --quiet; then
            success "Static IP released: $nat_ip"
        else
            warn "Static IP delete failed"
        fi
    else
        info "Static IP not found: $nat_ip — skipping"
    fi
}

_rollback_vpc() {
    local project_id="$1" region="$2"
    step "VPC: Delete subnet and network"
    local subnet_name="${project_id}-subnet"
    local vpc_name="${project_id}-vpc"

    if gcloud compute networks subnets describe "$subnet_name" \
        --region="$region" --project="$project_id" &>/dev/null; then
        if run_or_dry gcloud compute networks subnets delete "$subnet_name" \
            --region="$region" \
            --project="$project_id" \
            --quiet; then
            success "Subnet deleted: $subnet_name"
        else
            warn "Subnet delete failed"
        fi
    else
        info "Subnet not found: $subnet_name — skipping"
    fi

    if gcloud compute networks describe "$vpc_name" \
        --project="$project_id" &>/dev/null; then
        if run_or_dry gcloud compute networks delete "$vpc_name" \
            --project="$project_id" \
            --quiet; then
            success "VPC deleted: $vpc_name"
        else
            warn "VPC delete failed — may have dangling firewall rules"
        fi
    else
        info "VPC not found: $vpc_name — skipping"
    fi
}

_rollback_hardening() {
    local project_id="$1"
    step "Cloud Armor + SSL Policy: Delete"

    if gcloud compute security-policies describe "cve-canary" \
        --project="$project_id" &>/dev/null; then
        if run_or_dry gcloud compute security-policies delete "cve-canary" \
            --project="$project_id" \
            --quiet; then
            success "Cloud Armor policy deleted: cve-canary"
        else
            warn "Cloud Armor delete failed"
        fi
    else
        info "Cloud Armor policy not found: cve-canary — skipping"
    fi

    if gcloud compute ssl-policies describe "sslsecure" \
        --project="$project_id" &>/dev/null; then
        if run_or_dry gcloud compute ssl-policies delete "sslsecure" \
            --project="$project_id" \
            --quiet; then
            success "SSL policy deleted: sslsecure"
        else
            warn "SSL policy delete failed"
        fi
    else
        info "SSL policy not found: sslsecure — skipping"
    fi
}

_rollback_ssl_cert() {
    local project_id="$1"
    step "SSL Certificate: Delete"
    local ssl_cert="${project_id}-ssl-cert"

    if gcloud compute ssl-certificates describe "$ssl_cert" \
        --project="$project_id" --global &>/dev/null; then
        if run_or_dry gcloud compute ssl-certificates delete "$ssl_cert" \
            --project="$project_id" \
            --global \
            --quiet; then
            success "SSL certificate deleted: $ssl_cert"
        else
            warn "SSL certificate delete failed"
        fi
    else
        info "SSL certificate not found: $ssl_cert — skipping"
    fi
}

cmd_rollback() {
    print_banner_box "GKE Cluster Rollback"
    _preflight_checks

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Dry rollback — no GCP calls executed"
        return 0
    fi

    local project_id cluster_name region fleet_id

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
    case "$env" in
        pro) fleet_id="gnp-fleets-pro" ;;
        uat) fleet_id="gnp-fleets-uat" ;;
        qa)  fleet_id="gnp-fleets-qa"  ;;
    esac
    prompt_or_arg fleet_id "$fleet_id" "Fleet project ID" "$fleet_id"

    info "Project:  $project_id"
    info "Cluster:  $cluster_name"
    info "Region:   $region"
    info "Fleet:    $fleet_id"

    warn "This will permanently delete all resources for project: $project_id"
    local confirm
    read_input confirm "${CYAN}Type project ID to confirm deletion: ${NC}"
    if [ "$confirm" != "$project_id" ]; then
        info "Confirmation mismatch — aborted"
        return 0
    fi

    _rollback_fleet           "$project_id" "$cluster_name" "$fleet_id"
    _rollback_cluster         "$project_id" "$cluster_name" "$region"
    _rollback_workload_identity "$project_id"
    _rollback_nat             "$project_id" "$region"
    _rollback_vpc             "$project_id" "$region"
    _rollback_hardening       "$project_id"
    _rollback_ssl_cert        "$project_id"

    success "Rollback complete for project: $project_id"
}
