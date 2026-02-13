#!/bin/bash

################################################################################
# lib/gcp-operations.sh - Operaciones GCP Pub/Sub
################################################################################

set -uo pipefail

# Verificar si un topic existe
topic_exists() {
    local project=$1
    local topic=$2
    
    # Si el topic contiene "projects/", es una ruta completa
    if [[ "$topic" == projects/* ]]; then
        # Extraer el nombre del topic de la ruta completa
        local topic_name="${topic##*/topics/}"
        local topic_project
        topic_project=$(echo "$topic" | sed 's|projects/\([^/]*\)/.*|\1|')
        gcloud pubsub topics describe "$topic_name" --project="$topic_project" &>/dev/null
    else
        gcloud pubsub topics describe "$topic" --project="$project" &>/dev/null
    fi
}

# Crear topic (idempotente)
create_topic() {
    local project=$1
    local topic=$2
    local retention_days=${3:-7}
    
    if topic_exists "$project" "$topic"; then
        print_warn "Ya existe"
        return 0
    fi
    
    if gcloud pubsub topics create "$topic" \
        --project="$project" \
        --message-retention-duration="${retention_days}d" &>/dev/null; then
        print_success "Creado"
        return 0
    else
        print_error "Fallo"
        return 1
    fi
}

# Verificar si una suscripción existe
subscription_exists() {
    local project=$1
    local subscription=$2
    
    gcloud pubsub subscriptions describe "$subscription" --project="$project" &>/dev/null
}

# Crear suscripción (idempotente)
# Soporta topics en el mismo proyecto o en otros proyectos
create_subscription() {
    local project=$1
    local subscription=$2
    local topic=$3
    local ack_deadline=${4:-600}
    local retention_days=${5:-7}
    
    if subscription_exists "$project" "$subscription"; then
        print_warn "Ya existe"
        return 0
    fi
    
    # Construir la referencia del topic
    local topic_ref
    if [[ "$topic" == projects/* ]]; then
        # Ya es una ruta completa
        topic_ref="$topic"
    else
        # Es solo el nombre, asumir mismo proyecto
        topic_ref="projects/${project}/topics/${topic}"
    fi
    
    if gcloud pubsub subscriptions create "$subscription" \
        --project="$project" \
        --topic="$topic_ref" \
        --ack-deadline="$ack_deadline" \
        --message-retention-duration="${retention_days}d" \
        --expiration-period=never &>/dev/null; then
        print_success "Creada"
        return 0
    else
        print_error "Fallo"
        return 1
    fi
}

# Verificar que Pub/Sub esté habilitado
pubsub_enabled() {
    local project=$1
    
    gcloud services list --project="$project" \
        --enabled --format="value(name)" | grep -q "pubsub.googleapis.com"
}

