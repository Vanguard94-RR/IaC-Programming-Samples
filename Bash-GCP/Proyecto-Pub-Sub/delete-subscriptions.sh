#!/bin/bash

################################################################################
# delete-stela-subscriptions.sh - Eliminar suscripciones STELA de ODS-UAT
# 
# Uso: ./delete-stela-subscriptions.sh
#
# Elimina las 11 suscripciones creadas para STELA en gnp-ods-uat
################################################################################

set -uo pipefail

# Directorio del script
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importar librerías
source "${SCRIPT_ROOT}/lib/common.sh"

# Proyecto
PROJECT="gnp-stela-uat"

# Lista de suscripciones a eliminar
SUBSCRIPTIONS=(
    "gnp-ods.stela.cuentas.registar.ods.recibos"
    "gnp-ods.stela.cuentas.bloqueada.ods.recibos"
    "gnp-ods.stela.cuentas.desbloqueada.ods.recibos"
    "gnp-ods.stela.cuentas.rehabilitada.ods.recibos"
    "gnp-ods.stela.cuentas.cancelada.ods.recibos"
    "gnp-ods.stela.cuentas.liquidada.ods.recibos"
    "gnp-ods.stela.cuentas.devuelta.ods.recibos"
    "gnp-ods.stela.cuentas.prorrogada.ods.recibos"
    "gnp-ods.stela.cuentas.bloqueada-transito.trazabilidad"
    "gnp-ods.stela.cuentas.desbloqueada-transito.trazabilidad"
    "gnp-ods.stela.cuentas.liquidada-flujo.ods.recibos"
)

################################################################################
# FUNCIONES
################################################################################

# Verificar si una suscripción existe
subscription_exists() {
    local project=$1
    local subscription=$2
    
    gcloud pubsub subscriptions describe "$subscription" --project="$project" &>/dev/null
}

# Eliminar suscripción
delete_subscription() {
    local project=$1
    local subscription=$2
    
    if ! subscription_exists "$project" "$subscription"; then
        print_warn "No existe: $subscription"
        return 0
    fi
    
    if gcloud pubsub subscriptions delete "$subscription" --project="$project" --quiet &>/dev/null; then
        print_success "Eliminada: $subscription"
        return 0
    else
        print_error "Error al eliminar: $subscription"
        return 1
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    print_info "Eliminando suscripciones STELA de $PROJECT"
    echo ""
    
    # Validar dependencias
    if ! command -v gcloud &>/dev/null; then
        die "gcloud no instalado"
    fi
    
    # Validar autenticación
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        die "Ejecuta: gcloud auth login"
    fi
    
    # Confirmar eliminación
    echo "Se eliminarán ${#SUBSCRIPTIONS[@]} suscripciones de $PROJECT"
    echo ""
    read -rp "¿Continuar? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_warn "Cancelado"
        exit 0
    fi
    
    echo ""
    
    local deleted=0
    local failed=0
    
    # Eliminar cada suscripción
    for subscription in "${SUBSCRIPTIONS[@]}"; do
        if delete_subscription "$PROJECT" "$subscription"; then
            ((deleted++)) || true
        else
            ((failed++)) || true
        fi
    done
    
    echo ""
    print_success "Completado: $deleted eliminadas, $failed errores"
    
    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

# Ejecutar
main "$@"
