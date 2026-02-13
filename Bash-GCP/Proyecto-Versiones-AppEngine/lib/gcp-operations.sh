#!/bin/bash

################################################################################
# lib/gcp-operations.sh - Operaciones GCP Simples
################################################################################

# Obtener lista de servicios
get_services() {
    local project=$1
    gcloud app services list --project="$project" --format=json 2>/dev/null || echo "[]"
}

# Obtener versiones de un servicio
get_service_versions() {
    local project=$1
    local service=$2
    
    printf "  (esto puede tardar...)\\n" >&2
    gcloud app versions list \
        --project="$project" \
        --service="$service" \
        --format=json \
        --sort-by="~deployTime" \
        --limit=1000 \
        2>/dev/null || echo "[]"
}

# Obtener versión en servicio (la que tiene traffic allocation)
get_serving_version() {
    local project=$1
    local service=$2
    
    gcloud app versions list \
        --project="$project" \
        --service="$service" \
        --filter="traffic_split>0" \
        --format="value(id)" \
        2>/dev/null | head -1
}

# Calcular versiones a eliminar - RECENT
get_versions_to_delete_recent() {
    local versions_json=$1
    local keep=$2
    local serving_version=$3
    
    echo "$versions_json" | jq --arg serving "$serving_version" --arg keep "$keep" '
        [.[] | select(.id != $serving)] | .[$keep | tonumber:] | 
        map({id: .id, createTime: .version.createTime})
    '
}

# Calcular versiones a eliminar - MONTHLY
get_versions_to_delete_monthly() {
    local versions_json=$1
    local months=$2
    local serving_version=$3
    
    echo "$versions_json" | jq --arg serving "$serving_version" --arg months "$months" '
        [.[] | select(.id != $serving)] |
        group_by(.version.createTime[0:7]) |
        map(sort_by(-.version.createTime)[0]) |
        sort_by(-.version.createTime) |
        .[$months | tonumber:] as $old_months |
        (
            [.[] | select(.id != $serving)] |
            map(select((.version.createTime[0:7] | IN($old_months[].version.createTime[0:7])) | not)) |
            map({id: .id, createTime: .version.createTime})
        )
    ' 2>/dev/null || echo "[]"
}

# Eliminar versión individual
delete_version() {
    local project=$1
    local service=$2
    local version=$3
    
    if gcloud app versions delete "$version" \
        --service="$service" \
        --project="$project" \
        --quiet 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Eliminar múltiples versiones
delete_versions() {
    local project=$1
    local service=$2
    local versions_json=$3
    
    local deleted=0
    local failed=0
    local version_ids
    mapfile -t version_ids < <(echo "$versions_json" | jq -r '.[].id')
    local total=${#version_ids[@]}
    local current=0
    
    echo ""
    
    for version_id in "${version_ids[@]}"; do
        [[ -z "$version_id" ]] && continue
        
        ((current++))
        
        if delete_version "$project" "$service" "$version_id"; then
            ((deleted++))
            show_progress "$current" "$total" >&2
        else
            ((failed++))
            show_progress "$current" "$total" >&2
        fi
    done
    
    echo "" >&2
    echo "$deleted"
}
