#!/usr/bin/env bash
# apply_new_ingress - extracted from kube_compare_apply

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compare_ingress_services.sh"

apply_new_ingress() {
    step "Iniciando proceso de aplicación del nuevo Ingress"
    
    # Detectar si el ingress ya existe (UPDATE) o es nuevo (CREATE)
    local operation="CREATE"
    if kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        operation="UPDATE"
        info "Operación detectada: ${BOLD}ACTUALIZACIÓN${NC} del Ingress existente"
    else
        info "Operación detectada: ${BOLD}CREACIÓN${NC} de nuevo Ingress"
    fi
    
    echo -e "\n${YELLOW}Validando nuevo ingress.yaml (server-side dry-run)...${NC}"
    if ! kubectl apply -f ingress.yaml -n "$NAMESPACE" --dry-run=server >/dev/null 2>&1; then
        echo -e "${RED}ingress.yaml falló la validación server-side. Abortando aplicación.${NC}"
        kubectl apply -f ingress.yaml -n "$NAMESPACE" --dry-run=server -o yaml || true
        return 1
    fi
    success "Server-side dry-run validation passed"

    # Mostrar diff de cambios si es una actualización
    if [ "$operation" = "UPDATE" ] && [ -f "$BACKUP_FILE" ]; then
        echo -e "\n${CYAN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Vista previa de cambios (kubectl diff):${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        if kubectl diff -f ingress.yaml -n "$NAMESPACE" 2>/dev/null | head -50; then
            echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        else
            info "No se pudo generar diff (puede que no haya cambios o kubectl diff no esté disponible)"
        fi
    fi

    if ! compare_ingress_services; then
        warn "Service comparison failed, but continuing with apply process"
    fi

    if [ "${DRY_RUN:-false}" = "true" ]; then
        echo -e "${YELLOW}Modo dry-run: validación pasada, no se aplicará.${NC}"
        return 0
    fi

    echo -e "\n${YELLOW}¿Desea aplicar el nuevo ingress.yaml? (${operation})${NC}"
    printf "%b" "${CYAN}Escriba '${WHITE}${BOLD}yes${NC}${CYAN}' o '${WHITE}${BOLD}Y${NC}${CYAN}' para continuar: ${NC}"
    read_input CONFIRM ""
    CONFIRM_LOWER=$(printf "%s" "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [ "$CONFIRM_LOWER" = "yes" ] || [ "$CONFIRM_LOWER" = "y" ]; then
        info "Aplicando cambios al Ingress..."
        local apply_output
        apply_output=$(kubectl apply -f ingress.yaml -n "$NAMESPACE" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            # Mostrar el resultado real de kubectl (created/configured/unchanged)
            if echo "$apply_output" | grep -q "configured"; then
                success "Ingress ACTUALIZADO exitosamente: $apply_output"
            elif echo "$apply_output" | grep -q "created"; then
                success "Ingress CREADO exitosamente: $apply_output"
            elif echo "$apply_output" | grep -q "unchanged"; then
                info "Ingress sin cambios: $apply_output"
            else
                success "Ingress aplicado: $apply_output"
            fi
            post_apply_validation
        else
            echo -e "${RED}Error al aplicar el nuevo Ingress: $apply_output${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Operación cancelada. No se realizaron cambios.${NC}"
    fi
}
