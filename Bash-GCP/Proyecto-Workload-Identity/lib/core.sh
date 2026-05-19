#!/bin/bash
# =============================================================================
# Workload Identity Manager — Core Library
# GCP/k8s operations, validation, dry-run wrapper, operation orchestrators
# Globals required: G_IAM_ROLE, G_ANNOTATION_KEY, G_DEFAULT_NS
# Calls: log, print_error, print_success, print_warning, print_info (from lib/ui.sh)
#        registry_upsert, update_registry_status, sync_registry (from lib/registry.sh)
# =============================================================================

# ---------------------------------------------------------------------------
# exec_or_dry description command [args...]
# If WI_DRY_RUN=1: print without executing. Else: execute.
# ---------------------------------------------------------------------------
exec_or_dry() {
    local description="$1"; shift
    if [[ "${WI_DRY_RUN:-0}" == "1" ]]; then
        echo "[DRY-RUN] $description: $*"
        return 0
    fi
    "$@"
}

# ---------------------------------------------------------------------------
# _resolve_cluster_location project cluster
# Queries GCP for cluster location. Fails if ambiguous or not found.
# ---------------------------------------------------------------------------
_resolve_cluster_location() {
    local project="$1"
    local cluster="$2"

    local result
    result=$(gcloud container clusters list \
        --project "$project" \
        --filter="name=${cluster}" \
        --format="value(name,location)" 2>/dev/null)

    local line_count
    line_count=$(printf '%s\n' "$result" | awk 'NF{c++} END{print c+0}')

    if [[ "$line_count" -eq 1 ]]; then
        echo "$result" | awk -F'\t' '{print $2}'
        return 0
    elif [[ "$line_count" -gt 1 ]]; then
        echo "Multiple clusters named '$cluster' in project '$project'. Use --location." >&2
        return 1
    else
        echo "Cluster '$cluster' not found in project '$project'." >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# check_binding_exists iam_sa_email project_id ksa_name namespace
# Returns 0 if IAM binding AND KSA annotation are both correctly set.
# ---------------------------------------------------------------------------
check_binding_exists() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"

    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"

    local iam_ok=1
    gcloud iam service-accounts get-iam-policy "$iam_sa_email" \
        --project "$project_id" \
        --format="json" 2>/dev/null \
    | jq -e --arg m "$member" \
        '.bindings[] | select(.role=="roles/iam.workloadIdentityUser") | .members[] | select(.==$m)' \
        &>/dev/null \
    && iam_ok=0

    local annotation
    annotation=$(get_ksa_annotation "$ksa_name" "$namespace" 2>/dev/null || echo "")
    local ann_ok=1
    [[ "$annotation" == "$iam_sa_email" ]] && ann_ok=0

    [[ "$iam_ok" -eq 0 && "$ann_ok" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# do_bind project cluster location namespace ksa iam_sa [ticket] [dry_run]
# Bind two existing accounts. Most common production operation.
# ---------------------------------------------------------------------------
do_bind() {
    local project="$1"
    local cluster="$2"
    local location="$3"
    local namespace="$4"
    local ksa="$5"
    local iam_sa="$6"
    local ticket="${7:-}"
    local dry_run="${8:-0}"

    # Validate
    validate_project_id "$project"     || return 1
    validate_iam_sa_email "$iam_sa"    || return 1
    validate_k8s_name "$ksa" "KSA"     || return 1

    # Auth
    check_gcloud_auth || return 1

    # Resolve location if omitted
    if [[ -z "$location" ]]; then
        location=$(_resolve_cluster_location "$project" "$cluster") || return 1
    fi

    # Connect
    connect_to_cluster "$cluster" "$location" "$project" || return 1

    # Idempotency
    if check_binding_exists "$iam_sa" "$project" "$ksa" "$namespace"; then
        echo "Binding already configured: $ksa → $iam_sa"
        return 0
    fi

    # Set dry-run env for exec_or_dry
    local saved_dry="${WI_DRY_RUN:-0}"
    [[ "$dry_run" == "1" ]] && export WI_DRY_RUN=1

    # Create IAM SA if missing
    if ! verify_iam_sa "$iam_sa" "$project"; then
        local sa_name="${iam_sa%%@*}"
        exec_or_dry "create IAM SA" \
            gcloud iam service-accounts create "$sa_name" \
                --project "$project" \
                --display-name "$sa_name"
    fi

    # Create KSA if missing
    if [[ "${WI_DRY_RUN:-0}" == "1" ]]; then
        exec_or_dry "create KSA" kubectl create serviceaccount "$ksa" -n "$namespace"
    elif ! kubectl get serviceaccount "$ksa" -n "$namespace" --request-timeout=5s &>/dev/null; then
        exec_or_dry "create KSA" kubectl create serviceaccount "$ksa" -n "$namespace"
    fi

    # IAM binding — auto-enables WI if pool missing, then retries
    local member="serviceAccount:${project}.svc.id.goog[${namespace}/${ksa}]"
    if [[ "${WI_DRY_RUN:-0}" == "1" ]]; then
        exec_or_dry "add IAM binding" \
            gcloud iam service-accounts add-iam-policy-binding "$iam_sa" \
                --project "$project" --role "$G_IAM_ROLE" --member "$member"
    else
        _add_iam_binding_wi_aware "$iam_sa" "$project" "$G_IAM_ROLE" "$member" "$cluster" "$location" || { export WI_DRY_RUN="$saved_dry"; return 1; }
    fi

    # KSA annotation
    exec_or_dry "annotate KSA" \
        kubectl annotate serviceaccount "$ksa" \
            --namespace "$namespace" \
            "${G_ANNOTATION_KEY}=${iam_sa}" \
            --overwrite

    export WI_DRY_RUN="$saved_dry"

    # Registry (skip on dry-run)
    if [[ "${dry_run:-0}" != "1" ]]; then
        registry_upsert "$ticket" "$project" "$cluster" "$location" \
            "$namespace" "$ksa" "$iam_sa"
        sync_registry push
    fi
}

# ---------------------------------------------------------------------------
# do_setup project cluster location namespace ksa iam_sa [ticket] [dry_run]
# Full flow: create IAM SA if missing, create KSA if missing, then bind.
# ---------------------------------------------------------------------------
do_setup() {
    local project="$1"
    local cluster="$2"
    local location="$3"
    local namespace="$4"
    local ksa="$5"
    local iam_sa="$6"
    local ticket="${7:-}"
    local dry_run="${8:-0}"

    validate_project_id "$project"     || return 1
    validate_iam_sa_email "$iam_sa"    || return 1
    validate_k8s_name "$ksa" "KSA"     || return 1

    check_gcloud_auth || return 1

    if [[ -z "$location" ]]; then
        location=$(_resolve_cluster_location "$project" "$cluster") || return 1
    fi

    connect_to_cluster "$cluster" "$location" "$project" || return 1

    # Idempotency: skip if already fully configured
    if check_binding_exists "$iam_sa" "$project" "$ksa" "$namespace"; then
        echo "Binding already configured: $ksa → $iam_sa"
        return 0
    fi

    local saved_dry="${WI_DRY_RUN:-0}"
    [[ "$dry_run" == "1" ]] && export WI_DRY_RUN=1

    # Create IAM SA if missing
    if ! verify_iam_sa "$iam_sa" "$project"; then
        local sa_name="${iam_sa%%@*}"
        exec_or_dry "create IAM SA" \
            gcloud iam service-accounts create "$sa_name" \
                --project "$project" \
                --display-name "$sa_name"
    fi

    # Create KSA if missing
    if [[ "${WI_DRY_RUN:-0}" == "1" ]]; then
        exec_or_dry "create KSA" kubectl create serviceaccount "$ksa" -n "$namespace"
    elif ! kubectl get serviceaccount "$ksa" -n "$namespace" --request-timeout=5s &>/dev/null; then
        exec_or_dry "create KSA" kubectl create serviceaccount "$ksa" -n "$namespace"
    fi

    # IAM binding — auto-enables WI if pool missing, then retries
    local member="serviceAccount:${project}.svc.id.goog[${namespace}/${ksa}]"
    if [[ "${WI_DRY_RUN:-0}" == "1" ]]; then
        exec_or_dry "add IAM binding" \
            gcloud iam service-accounts add-iam-policy-binding "$iam_sa" \
                --project "$project" --role "$G_IAM_ROLE" --member "$member"
    else
        _add_iam_binding_wi_aware "$iam_sa" "$project" "$G_IAM_ROLE" "$member" "$cluster" "$location" || { export WI_DRY_RUN="$saved_dry"; return 1; }
    fi

    # KSA annotation
    exec_or_dry "annotate KSA" \
        kubectl annotate serviceaccount "$ksa" \
            --namespace "$namespace" \
            "${G_ANNOTATION_KEY}=${iam_sa}" \
            --overwrite

    export WI_DRY_RUN="$saved_dry"

    if [[ "${dry_run:-0}" != "1" ]]; then
        registry_upsert "$ticket" "$project" "$cluster" "$location" \
            "$namespace" "$ksa" "$iam_sa"
        sync_registry push
    fi
}

# ---------------------------------------------------------------------------
# do_verify project cluster location namespace ksa iam_sa
# Check all four components; print status; returns 0 only if all OK.
# ---------------------------------------------------------------------------
do_verify() {
    local project="$1"
    local cluster="$2"
    local location="$3"
    local namespace="$4"
    local ksa="$5"
    local iam_sa="$6"

    check_gcloud_auth || return 1

    if [[ -z "$location" ]]; then
        location=$(_resolve_cluster_location "$project" "$cluster") || return 1
    fi

    connect_to_cluster "$cluster" "$location" "$project" || return 1

    local all_ok=0

    # IAM SA exists
    if verify_iam_sa "$iam_sa" "$project"; then
        echo "✓ IAM SA exists: $iam_sa"
    else
        echo "✗ IAM SA not found: $iam_sa"
        all_ok=1
    fi

    # KSA exists
    if kubectl get serviceaccount "$ksa" -n "$namespace" --request-timeout=5s &>/dev/null; then
        echo "✓ KSA exists: $ksa (ns=$namespace)"
    else
        echo "✗ KSA not found: $ksa (ns=$namespace)"
        all_ok=1
    fi

    # KSA annotation
    local annotation
    annotation=$(get_ksa_annotation "$ksa" "$namespace" 2>/dev/null || echo "")
    if [[ "$annotation" == "$iam_sa" ]]; then
        echo "✓ KSA annotation matches"
    else
        echo "✗ KSA annotation mismatch: got='$annotation' want='$iam_sa'"
        all_ok=1
    fi

    # IAM binding
    if check_binding_exists "$iam_sa" "$project" "$ksa" "$namespace"; then
        echo "✓ IAM binding configured"
    else
        echo "✗ IAM binding missing or incomplete"
        all_ok=1
    fi

    return $all_ok
}

# ---------------------------------------------------------------------------
# do_cleanup project cluster location namespace ksa iam_sa level [dry_run]
# level 1=binding only, 2=+ksa, 3=+iam_sa
# ---------------------------------------------------------------------------
do_cleanup() {
    local project="$1"
    local cluster="$2"
    local location="$3"
    local namespace="$4"
    local ksa="$5"
    local iam_sa="$6"
    local level="${7:-1}"
    local dry_run="${8:-0}"

    check_gcloud_auth || return 1

    if [[ -z "$location" ]]; then
        location=$(_resolve_cluster_location "$project" "$cluster") || return 1
    fi

    connect_to_cluster "$cluster" "$location" "$project" || return 1

    local saved_dry="${WI_DRY_RUN:-0}"
    [[ "$dry_run" == "1" ]] && export WI_DRY_RUN=1

    local member="serviceAccount:${project}.svc.id.goog[${namespace}/${ksa}]"
    exec_or_dry "remove IAM binding" \
        gcloud iam service-accounts remove-iam-policy-binding "$iam_sa" \
            --project "$project" \
            --role "$G_IAM_ROLE" \
            --member "$member"

    if [[ "$level" -ge 2 ]]; then
        exec_or_dry "delete KSA" \
            kubectl delete serviceaccount "$ksa" -n "$namespace"
    fi

    if [[ "$level" -ge 3 ]]; then
        exec_or_dry "delete IAM SA" \
            gcloud iam service-accounts delete "$iam_sa" \
                --project "$project" --quiet
    fi

    export WI_DRY_RUN="$saved_dry"

    if [[ "${dry_run:-0}" != "1" ]]; then
        update_registry_status "$project" "$cluster" "$namespace" "$ksa" "eliminado"
        sync_registry push
    fi
}

# ---------------------------------------------------------------------------
# GCP/k8s primitive functions (moved unchanged from monolith)
# ---------------------------------------------------------------------------

check_gcloud_auth() {
    local max_attempts=3 attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if gcloud auth list --filter=status:ACTIVE \
            --format="value(account)" &>/dev/null; then
            return 0
        fi
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "\033[1;33m⚠ gcloud auth expired, refreshing...\033[0m"
            gcloud auth application-default print-access-token &>/dev/null
            ((attempt++))
            sleep 1
        else
            ((attempt++))
        fi
    done
    echo -e "\033[0;31m✗ gcloud auth failed. Run: gcloud auth login\033[0m" >&2
    return 1
}

retry_gcloud_command() {
    local max_retries=3 timeout=1 attempt=1 exit_code=0
    while [[ $attempt -le $max_retries ]]; do
        "$@"
        exit_code=$?
        [[ $exit_code -eq 0 ]] && return 0
        if [[ $exit_code -eq 1 || $exit_code -eq 403 || $exit_code -eq 401 ]]; then
            return $exit_code
        fi
        if [[ $attempt -lt $max_retries ]]; then
            echo -e "\033[0;37m  Retry $attempt/$max_retries in ${timeout}s...\033[0m" >&2
            sleep "$timeout"
            timeout=$(( timeout * 2 ))
        fi
        (( attempt++ ))
    done
    return $exit_code
}

connect_to_cluster() {
    local cluster_name="$1" location="$2" project_id="$3"
    local flag
    log "Connecting to cluster: $cluster_name in $location"
    if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
        flag="--region"
    else
        flag="--zone"
    fi
    if ! gcloud container clusters get-credentials "$cluster_name" \
            "$flag" "$location" --project "$project_id" 2>/dev/null; then
        echo "Failed to connect to cluster $cluster_name ($location)" >&2
        return 1
    fi
    log "Connected to cluster: $cluster_name"
}

verify_iam_sa() {
    local sa_email="$1" project_id="$2"
    gcloud iam service-accounts describe "$sa_email" \
        --project "$project_id" &>/dev/null
}

create_iam_sa() {
    local sa_name="$1" project_id="$2" display_name="${3:-$1}"
    gcloud iam service-accounts create "$sa_name" \
        --project "$project_id" --display-name "$display_name"
}

create_namespace() {
    local namespace="$1"
    timeout 7 kubectl get namespace "$namespace" --request-timeout=5s &>/dev/null && return 0
    timeout 12 kubectl create namespace "$namespace" --request-timeout=10s
}

create_ksa() {
    local ksa_name="$1" namespace="$2"
    timeout 7 kubectl get serviceaccount "$ksa_name" -n "$namespace" --request-timeout=5s &>/dev/null && return 0
    timeout 12 kubectl create serviceaccount "$ksa_name" -n "$namespace" --request-timeout=10s
}

add_iam_binding() {
    local iam_sa_email="$1" project_id="$2" ksa_name="$3" namespace="$4"
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    gcloud iam service-accounts add-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" --role "$G_IAM_ROLE" --member "$member"
}

annotate_ksa() {
    local ksa_name="$1" namespace="$2" iam_sa_email="$3"
    timeout 12 kubectl annotate serviceaccount "$ksa_name" \
        --namespace "$namespace" \
        --request-timeout=10s \
        "${G_ANNOTATION_KEY}=${iam_sa_email}" --overwrite
}

remove_iam_binding() {
    local iam_sa_email="$1" project_id="$2" ksa_name="$3" namespace="$4"
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    gcloud iam service-accounts remove-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" --role "$G_IAM_ROLE" --member "$member"
}

delete_ksa() {
    local ksa_name="$1" namespace="$2"
    kubectl delete serviceaccount "$ksa_name" -n "$namespace"
}

get_ksa_annotation() {
    local ksa_name="$1" namespace="$2"
    kubectl get serviceaccount "$ksa_name" -n "$namespace" \
        --request-timeout=5s \
        -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null
}

list_gke_clusters() {
    local project_id="$1"
    gcloud container clusters list --project "$project_id" \
        --format="value(name,location)" 2>/dev/null
}

list_workload_identities() {
    local namespace="$1"
    local ksa_output
    ksa_output=$(kubectl get serviceaccounts -n "$namespace" --request-timeout=5s -o json 2>/dev/null)
    [[ -z "$ksa_output" ]] && { echo "  No service accounts found in $namespace"; return 0; }

    local found=0
    while IFS='|' read -r ksa annotation; do
        [[ -z "$ksa" || -z "$annotation" ]] && continue
        echo "  • KSA: $ksa"
        echo "    IAM SA: $annotation"
        found=1
    done < <(echo "$ksa_output" | jq -r \
        '.items[] | "\(.metadata.name)|\(.metadata.annotations["iam.gke.io/gcp-service-account"] // "")"' \
        2>/dev/null)

    [[ "$found" -eq 0 ]] && echo "  No KSAs with Workload Identity annotation in $namespace"
}

get_current_project() {
    gcloud config get-value project 2>/dev/null
}

# ---------------------------------------------------------------------------
# Validation functions (moved unchanged from monolith)
# ---------------------------------------------------------------------------

validate_project_id() {
    local project="$1"
    if [[ ${#project} -lt 6 || ${#project} -gt 30 ]]; then
        echo -e "\033[0;31m✗ Project ID must be 6-30 chars: $project\033[0m" >&2
        return 1
    fi
    if [[ ! "$project" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        echo -e "\033[0;31m✗ Invalid project ID format: $project\033[0m" >&2
        return 1
    fi
    if ! gcloud projects describe "$project" &>/dev/null; then
        echo -e "\033[0;31m✗ Project not found or no permissions: $project\033[0m" >&2
        return 1
    fi
    return 0
}

validate_iam_sa_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com$ ]]; then
        echo -e "\033[0;31m✗ Invalid IAM SA email: $email\033[0m" >&2
        return 1
    fi
    return 0
}

validate_k8s_name() {
    local name="$1" context="$2"
    if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || (( ${#name} > 63 )); then
        echo -e "\033[0;31m✗ Invalid $context name: $name\033[0m" >&2
        return 1
    fi
    return 0
}

validate_namespace() {
    local namespace="$1"
    if ! kubectl get namespace "$namespace" --request-timeout=5s &>/dev/null; then
        echo -e "\033[0;31m✗ Namespace not found: $namespace\033[0m" >&2
        return 1
    fi
    return 0
}

validate_workload_identity_enabled() {
    local project="$1" cluster="$2" location="$3"
    local pool
    pool=$(gcloud container clusters describe "$cluster" \
        --project "$project" \
        --location "$location" \
        --format="value(workloadIdentityConfig.workloadPool)" 2>/dev/null)
    if [[ -z "$pool" ]]; then
        echo -e "\033[0;31m✗ Workload Identity not enabled on cluster '$cluster'\033[0m" >&2
        echo -e "\033[0;33m  Fix: gcloud container clusters update $cluster --location=$location --project=$project --workload-pool=${project}.svc.id.goog\033[0m" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _add_iam_binding_wi_aware iam_sa project role member cluster location
# Attempts IAM binding; if WI pool missing, offers to enable and retries once.
# ---------------------------------------------------------------------------
_add_iam_binding_wi_aware() {
    local iam_sa="$1" project="$2" role="$3" member="$4" cluster="$5" location="$6"
    local out rc=0
    out=$(gcloud iam service-accounts add-iam-policy-binding "$iam_sa" \
        --project "$project" --role "$role" --member "$member" 2>&1) || rc=$?
    [[ $rc -eq 0 ]] && return 0
    if echo "$out" | grep -q "Identity Pool does not exist"; then
        ensure_workload_identity_enabled "$project" "$cluster" "$location" || return 1
        gcloud iam service-accounts add-iam-policy-binding "$iam_sa" \
            --project "$project" --role "$role" --member "$member"
        return $?
    fi
    echo "$out" >&2
    return $rc
}

enable_workload_identity() {
    local project="$1" cluster="$2" location="$3"
    echo -e "\033[1;33m⚠ Enabling Workload Identity on '$cluster' — node pools will restart (~5 min)\033[0m"
    gcloud container clusters update "$cluster" \
        --location "$location" \
        --project "$project" \
        --workload-pool="${project}.svc.id.goog" \
        --quiet
}

ensure_workload_identity_enabled() {
    local project="$1" cluster="$2" location="$3"
    # Fast path: already enabled
    validate_workload_identity_enabled "$project" "$cluster" "$location" 2>/dev/null && return 0

    echo -e "\033[1;33m⚠ Workload Identity not enabled on cluster '$cluster'\033[0m"
    if ! ask_confirmation "Enable Workload Identity on cluster '$cluster'" "enable"; then
        return 1
    fi
    enable_workload_identity "$project" "$cluster" "$location" || return 1
    echo -e "\033[1;32m✓ Workload Identity enabled\033[0m"
    return 0
}

validate_kubectl_connectivity() {
    if ! kubectl cluster-info --request-timeout=5s &>/dev/null; then
        echo -e "\033[0;31m✗ kubectl cannot reach cluster API server (timeout)\033[0m" >&2
        echo -e "\033[0;33m  Check VPN or masterAuthorizedNetworksConfig\033[0m" >&2
        return 1
    fi
    return 0
}

select_cluster_from_project() {
    local project_id="$1"
    local prompt_msg="${2:-Select GKE cluster:}"
    local clusters_raw
    clusters_raw=$(list_gke_clusters "$project_id")

    [[ -z "$clusters_raw" ]] && {
        print_error "No GKE clusters found in project $project_id"
        return 1
    }

    declare -a cluster_names cluster_locations cluster_options
    while IFS=$'\t' read -r name location; do
        cluster_names+=("$name")
        cluster_locations+=("$location")
        cluster_options+=("$name ($location)")
    done <<< "$clusters_raw"

    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        SELECTED_CLUSTER="${cluster_names[0]}"
        SELECTED_LOCATION="${cluster_locations[0]}"
        print_info "Single cluster found" "$SELECTED_CLUSTER ($SELECTED_LOCATION)"
    else
        prompt_selection "$prompt_msg" cluster_options selected_option
        for i in "${!cluster_options[@]}"; do
            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                SELECTED_CLUSTER="${cluster_names[$i]}"
                SELECTED_LOCATION="${cluster_locations[$i]}"
                break
            fi
        done
    fi
    return 0
}
