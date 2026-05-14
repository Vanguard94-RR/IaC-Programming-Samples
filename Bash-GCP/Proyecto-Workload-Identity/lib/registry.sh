#!/bin/bash
# =============================================================================
# Workload Identity Manager — Registry Library
# CSV registry operations: init, upsert, update status, GCS sync
# Globals required: G_CONTROL_FILE, G_TEMP_DIR, G_GCS_BUCKET
# =============================================================================

# Initialize and secure the registry CSV.
# Creates header if missing. Migrates corrupt rows (tab in cluster field).
init_control_file() {
    if [[ ! -f "$G_CONTROL_FILE" ]]; then
        echo "Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA,Status" \
            > "$G_CONTROL_FILE"
        if ! chmod 600 "$G_CONTROL_FILE" 2>/dev/null; then
            echo -e "\033[0;31m✗ Cannot set secure permissions on $G_CONTROL_FILE\033[0m" >&2
            return 1
        fi
    fi

    chmod 600 "$G_CONTROL_FILE" 2>/dev/null || true

    local actual_perms
    actual_perms=$(stat -c '%a' "$G_CONTROL_FILE" 2>/dev/null \
        || stat -f '%OA' "$G_CONTROL_FILE" 2>/dev/null)
    if [[ "$actual_perms" != "600" ]]; then
        echo -e "\033[1;33m⚠ Warning: registry permissions may not be 600 (found: $actual_perms)\033[0m" >&2
    fi

    # Migrate v4 header format (missing Status column)
    local header
    header=$(head -1 "$G_CONTROL_FILE" 2>/dev/null || echo "")
    if [[ -n "$header" && ! "$header" =~ "Status" ]]; then
        sed -i '1s/$/,Status/'  "$G_CONTROL_FILE"
        sed -i '2,$s/$/,activo/' "$G_CONTROL_FILE"
        chmod 600 "$G_CONTROL_FILE"
    fi

    # Migrate corrupt rows: cluster field contains embedded tab + location value
    if grep -qP '\t' "$G_CONTROL_FILE" 2>/dev/null; then
        local mig_tmp
        mig_tmp=$(mktemp --tmpdir="$G_TEMP_DIR")
        awk 'BEGIN{FS=","; OFS=","}
            NR==1 { print; next }
            $4 ~ /\t/ {
                n=split($4, parts, /\t/)
                if (n==2) { $4=parts[1]; $5=parts[2] }
            }
            { print }
        ' "$G_CONTROL_FILE" > "$mig_tmp"
        mv "$mig_tmp" "$G_CONTROL_FILE"
        chmod 600 "$G_CONTROL_FILE"
    fi
}

# Upsert a registry row.
# Key: (project, cluster, namespace, ksa)
# If row exists: update timestamp, ticket, location, iam_sa, status=activo
# If not exists: append new row
registry_upsert() {
    local ticket="${1:-}"
    local project="$2"
    local cluster="$3"
    local location="$4"
    local namespace="$5"
    local ksa="$6"
    local iam_sa="$7"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    [[ -z "$ticket" ]] && ticket="-"
    [[ ! -f "$G_CONTROL_FILE" ]] && init_control_file

    local temp_file
    temp_file=$(mktemp --tmpdir="$G_TEMP_DIR")

    awk -F',' -v p="$project" -v c="$cluster" -v ns="$namespace" -v k="$ksa" \
        -v ts="$timestamp" -v tkt="$ticket" -v loc="$location" -v isa="$iam_sa" \
        -v st="activo" \
        'BEGIN { OFS=","; found=0 }
        NR==1 { print; next }
        $3==p && $4==c && $6==ns && $7==k {
            $1=ts; $2=tkt; $5=loc; $8=isa; $9=st
            found=1
        }
        { print }
        END {
            if (!found) print ts","tkt","p","c","loc","ns","k","isa","st
        }
    ' "$G_CONTROL_FILE" > "$temp_file"

    mv "$temp_file" "$G_CONTROL_FILE"
    chmod 600 "$G_CONTROL_FILE"
}

# Update the status field for an existing registry row.
update_registry_status() {
    local project="$1"
    local cluster="$2"
    local namespace="$3"
    local ksa="$4"
    local new_status="$5"

    [[ ! -f "$G_CONTROL_FILE" ]] && return 1

    local temp_file
    temp_file=$(mktemp --tmpdir="$G_TEMP_DIR")

    awk -F',' -v p="$project" -v c="$cluster" -v ns="$namespace" \
        -v k="$ksa" -v s="$new_status" \
        'BEGIN { OFS="," }
        NR==1 { print; next }
        $3==p && $4==c && $6==ns && $7==k { $9=s }
        { print }
    ' "$G_CONTROL_FILE" > "$temp_file"

    mv "$temp_file" "$G_CONTROL_FILE"
    chmod 600 "$G_CONTROL_FILE"
}

# Sync registry to/from GCS. Non-fatal if bucket not configured.
# $1: action = push | pull
sync_registry() {
    local action="${1:-push}"

    [[ -z "$G_GCS_BUCKET" ]] && return 0

    if [[ ! "$G_GCS_BUCKET" =~ ^gs:// ]]; then
        log "WARNING: Invalid GCS bucket: $G_GCS_BUCKET"
        return 0
    fi

    [[ ! -f "$G_CONTROL_FILE" ]] && {
        log "WARNING: Registry file not found, skipping sync"
        return 0
    }

    case "$action" in
        push)
            if gcloud storage cp "$G_CONTROL_FILE" \
                "$G_GCS_BUCKET/registry.csv" --quiet 2>&1; then
                log "Registry synced to GCS"
            else
                log "WARNING: Failed to sync registry to GCS"
            fi
            ;;
        pull)
            if gcloud storage cp "$G_GCS_BUCKET/registry.csv" \
                "$G_CONTROL_FILE" --quiet 2>&1; then
                chmod 600 "$G_CONTROL_FILE"
                log "Registry synced from GCS"
            else
                log "WARNING: Failed to sync registry from GCS"
            fi
            ;;
        *)
            log "WARNING: sync_registry: unknown action '$action'"
            return 1
            ;;
    esac
    return 0
}
