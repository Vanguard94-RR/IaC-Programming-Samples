#!/bin/bash

################################################################################
# validate-stela-subscriptions.sh - Validador de suscripciones STELA
# 
# Valida que todas las suscripciones y permisos estén correctamente configurados
################################################################################

set -uo pipefail

# Colores
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m'

print_info() { echo -e "${COLOR_BLUE}ℹ${COLOR_NC} $*"; }
print_success() { echo -e "${COLOR_GREEN}✓${COLOR_NC} $*"; }
print_warn() { echo -e "${COLOR_YELLOW}⚠${COLOR_NC} $*"; }
print_error() { echo -e "${COLOR_RED}✗${COLOR_NC} $*" >&2; }

# Configuración
CONSUMER_PROJECT="gnp-ods-uat"
SOURCE_PROJECT="gnp-stela-uat"
SERVICE_ACCOUNT="stela-cuentas-cobrar@gnp-ods-uat.iam.gserviceaccount.com"

# Lista de recursos a validar
declare -A SUBSCRIPTIONS_MAP=(
    ["gnp-ods.stela.cuentas.registar.ods.recibos"]="gnp-tesoreria.stela.cuentas.registrada"
    ["gnp-ods.stela.cuentas.bloqueada.ods.recibos"]="gnp-tesoreria.stela.cuentas.bloqueada"
    ["gnp-ods.stela.cuentas.desbloqueada.ods.recibos"]="gnp-tesoreria.stela.cuentas.desbloqueada"
    ["gnp-ods.stela.cuentas.rehabilitada.ods.recibos"]="gnp-tesoreria.stela.cuentas.rehabilitada"
    ["gnp-ods.stela.cuentas.cancelada.ods.recibos"]="gnp-tesoreria.stela.cuentas.cancelada"
    ["gnp-ods.stela.cuentas.liquidada.ods.recibos"]="gnp-tesoreria.stela.cuentas.liquidada"
    ["gnp-ods.stela.cuentas.devuelta.ods.recibos"]="gnp-tesoreria.stela.cuentas.devuelta"
    ["gnp-ods.stela.cuentas.prorrogada.ods.recibos"]="gnp-tesoreria.stela.cuentas.prorrogada"
    ["gnp-ods.stela.cuentas.bloqueada-transito.trazabilidad"]="gnp-tesoreria.stela.cuentas.bloqueada-transito"
    ["gnp-ods.stela.cuentas.desbloqueada-transito.trazabilidad"]="gnp-tesoreria.stela.cuentas.desbloqueada-transito"
    ["gnp-ods.stela.cuentas.liquidada-flujo.ods.recibos"]="gnp-tesoreria.stela.cuentas.liquidada-flujo"
)

################################################################################
# FUNCIONES DE VALIDACIÓN
################################################################################

validate_subscription_exists() {
    local subscription=$1
    
    if gcloud pubsub subscriptions describe "$subscription" \
        --project="$CONSUMER_PROJECT" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

validate_subscription_topic() {
    local subscription=$1
    local expected_topic=$2
    
    local actual_topic
    actual_topic=$(gcloud pubsub subscriptions describe "$subscription" \
        --project="$CONSUMER_PROJECT" \
        --format="value(topic)" 2>/dev/null)
    
    local expected_full="projects/${SOURCE_PROJECT}/topics/${expected_topic}"
    
    if [[ "$actual_topic" == "$expected_full" ]]; then
        return 0
    else
        print_error "    Topic esperado: $expected_full"
        print_error "    Topic actual:   $actual_topic"
        return 1
    fi
}

validate_subscription_expiration() {
    local subscription=$1
    
    local expiration
    expiration=$(gcloud pubsub subscriptions describe "$subscription" \
        --project="$CONSUMER_PROJECT" \
        --format="value(expirationPolicy.ttl)" 2>/dev/null)
    
    # Si está vacío o es muy largo, significa "never expire"
    if [[ -z "$expiration" || "$expiration" == "null" ]]; then
        return 0
    fi
    
    # Verificar si tiene días muy altos (prácticamente nunca)
    if [[ "$expiration" =~ [0-9]+d ]] && [[ "${expiration%d}" -gt 10000 ]]; then
        return 0
    fi
    
    print_warn "    Expiración configurada: $expiration"
    return 1
}

validate_topic_iam_permission() {
    local topic=$1
    
    local has_permission
    has_permission=$(gcloud pubsub topics get-iam-policy "$topic" \
        --project="$SOURCE_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.role:roles/pubsub.viewer" \
        --format="value(bindings.members)" 2>/dev/null | \
        grep -c "serviceAccount:$SERVICE_ACCOUNT" || echo 0)
    
    if [[ "$has_permission" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# MAIN VALIDATION
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     Validación de Suscripciones STELA → ODS                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    print_info "Proyecto Consumer: $CONSUMER_PROJECT"
    print_info "Proyecto Source:   $SOURCE_PROJECT"
    print_info "Service Account:   $SERVICE_ACCOUNT"
    echo ""
    
    local total=0
    local passed=0
    local failed=0
    
    for subscription in "${!SUBSCRIPTIONS_MAP[@]}"; do
        local topic="${SUBSCRIPTIONS_MAP[$subscription]}"
        ((total++)) || true
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_info "[$total/11] Validando: $subscription"
        
        local sub_ok=true
        
        # 1. Verificar que existe la suscripción
        if validate_subscription_exists "$subscription"; then
            print_success "  Suscripción existe"
        else
            print_error "  Suscripción NO existe"
            sub_ok=false
        fi
        
        # 2. Verificar topic correcto
        if [[ "$sub_ok" == "true" ]]; then
            if validate_subscription_topic "$subscription" "$topic"; then
                print_success "  Topic correcto"
            else
                print_error "  Topic incorrecto"
                sub_ok=false
            fi
        fi
        
        # 3. Verificar que no expira
        if [[ "$sub_ok" == "true" ]]; then
            if validate_subscription_expiration "$subscription"; then
                print_success "  No expira (correcto)"
            else
                print_error "  Tiene expiración configurada"
                sub_ok=false
            fi
        fi
        
        # 4. Verificar permisos IAM en el topic
        if validate_topic_iam_permission "$topic"; then
            print_success "  Permisos IAM correctos en topic"
        else
            print_error "  Falta permiso roles/pubsub.viewer en topic"
            sub_ok=false
        fi
        
        if [[ "$sub_ok" == "true" ]]; then
            print_success "✓ VALIDACIÓN COMPLETA"
            ((passed++)) || true
        else
            print_error "✗ VALIDACIÓN FALLIDA"
            ((failed++)) || true
        fi
        
        echo ""
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    RESUMEN DE VALIDACIÓN                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    print_info "Total suscripciones: $total"
    print_success "Validaciones exitosas: $passed"
    
    if [[ $failed -gt 0 ]]; then
        print_error "Validaciones fallidas: $failed"
        echo ""
        print_error "¡Hay errores que deben corregirse!"
        return 1
    else
        echo ""
        print_success "✓ Todas las validaciones pasaron correctamente"
        return 0
    fi
}

# Ejecutar
main "$@"
