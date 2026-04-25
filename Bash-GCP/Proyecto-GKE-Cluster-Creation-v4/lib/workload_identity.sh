#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

create_workload_identity_assets() {
    step "Workload Identity Assets"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Workload Identity setup"
        return 0
    fi

    local namespace ksa_name iam_sa_name
    prompt_or_arg namespace "" "Kubernetes namespace" "apps"
    prompt_or_arg ksa_name "" "Kubernetes Service Account name" "apps-gke"
    prompt_or_arg iam_sa_name "" "IAM Service Account name" "apps-sa"

    info "Namespace:  $namespace"
    info "KSA:        $ksa_name"
    info "IAM SA:     $iam_sa_name"

    if ! run_or_dry gcloud container clusters get-credentials "${cluster_name}" \
        --region "${region}" --project "${project_id}" --quiet; then
        error "Could not get cluster credentials"
        return 1
    fi

    if run_or_dry kubectl get namespace "$namespace" &>/dev/null; then
        info "Namespace '$namespace' already exists"
    else
        info "Creating namespace: $namespace"
        run_or_dry kubectl create namespace "$namespace"
        success "Namespace created: $namespace"
    fi

    if run_or_dry kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        info "KSA '$ksa_name' already exists in '$namespace'"
    else
        info "Creating KSA: $ksa_name"
        run_or_dry kubectl create serviceaccount "$ksa_name" -n "$namespace"
        success "KSA created: $ksa_name"
    fi

    local iam_sa_full="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$iam_sa_full" \
        --project="${project_id}" &>/dev/null; then
        info "IAM SA '$iam_sa_full' already exists"
    else
        info "Creating IAM SA: $iam_sa_full"
        run_or_dry gcloud iam service-accounts create "$iam_sa_name" \
            --project="${project_id}" \
            --display-name="$iam_sa_name"
        success "IAM SA created: $iam_sa_full"
    fi

    local wi_member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    info "Binding Workload Identity..."
    run_or_dry gcloud iam service-accounts add-iam-policy-binding "$iam_sa_full" \
        --project="${project_id}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="$wi_member" \
        --quiet 2>/dev/null || warn "WI binding may already exist"

    info "Annotating KSA with IAM SA..."
    run_or_dry kubectl annotate serviceaccount "$ksa_name" \
        -n "$namespace" \
        "iam.gke.io/gcp-service-account=${iam_sa_full}" \
        --overwrite

    success "Workload Identity configured"
    info "  Namespace: $namespace"
    info "  KSA:       $ksa_name"
    info "  IAM SA:    $iam_sa_full"
    info "  WI member: $wi_member"
}
