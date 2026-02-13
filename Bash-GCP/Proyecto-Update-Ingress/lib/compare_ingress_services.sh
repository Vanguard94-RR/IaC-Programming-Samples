#!/usr/bin/env bash
# compare_ingress_services - extracted from kube_compare_apply

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

compare_ingress_services() {
    step "Comparando servicios entre el Ingress actual y el nuevo YAML"
    local old_yaml="$BACKUP_FILE"
    local new_yaml="ingress.yaml"
    local old_services="${TMP_PREFIX}_services_old.txt"
    local new_services="${TMP_PREFIX}_services_new.txt"

    if [ ! -f "$old_yaml" ]; then
        error "Backup file not found: $old_yaml"
        return 1
    fi
    if [ ! -f "$new_yaml" ]; then
        error "New ingress file not found: $new_yaml"
        return 1
    fi

    if ! yq eval '.spec.rules[].http.paths[].backend.service.name' "$old_yaml" | sort -u > "$old_services"; then
        error "Failed to extract services from current ingress"
        return 1
    fi
    if ! yq eval '.spec.rules[].http.paths[].backend.service.name' "$new_yaml" | sort -u > "$new_services"; then
        error "Failed to extract services from new ingress"
        return 1
    fi

    echo -e "\n${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}${BOLD}COMPARACIÓN DE SERVICIOS BACKEND${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    
    local old_list="${TMP_PREFIX}_services_old_list.txt"
    local new_list="${TMP_PREFIX}_services_new_list.txt"
    sort "$old_services" > "$old_list"
    sort "$new_services" > "$new_list"
    
    # Contar cambios
    local added=$(comm -13 "$old_list" "$new_list" | wc -l)
    local removed=$(comm -23 "$old_list" "$new_list" | wc -l)
    local unchanged=$(comm -12 "$old_list" "$new_list" | wc -l)
    
    echo -e "${WHITE}Resumen de cambios:${NC}"
    echo -e "  ${GREEN}✚ Servicios NUEVOS:      $added${NC}"
    echo -e "  ${RED}✖ Servicios ELIMINADOS:  $removed${NC}"
    echo -e "  ${CYAN}● Servicios SIN CAMBIO:  $unchanged${NC}"
    echo ""
    
    if [ "$added" -gt 0 ]; then
        echo -e "${GREEN}${BOLD}Servicios NUEVOS que se agregarán:${NC}"
        comm -13 "$old_list" "$new_list" | sed 's/^/  + /'
        echo ""
    fi
    
    if [ "$removed" -gt 0 ]; then
        echo -e "${RED}${BOLD}Servicios que se ELIMINARÁN:${NC}"
        comm -23 "$old_list" "$new_list" | sed 's/^/  - /'
        echo ""
    fi
    
    if [ "$unchanged" -gt 0 ]; then
        echo -e "${CYAN}${BOLD}Servicios que permanecen (sin cambio):${NC}"
        comm -12 "$old_list" "$new_list" | sed 's/^/  ● /'
        echo ""
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    rm -f "$old_list" "$new_list"

    echo -e "\n${YELLOW}${BOLD}CAMBIOS EN RUTAS (Path):${NC}"
    local old_paths="${TMP_PREFIX}_paths_old.txt"
    local new_paths="${TMP_PREFIX}_paths_new.txt"
    yq eval '.spec.rules[].http.paths[] | [.backend.service.name, .path] | @tsv' "$old_yaml" | sort > "$old_paths"
    yq eval '.spec.rules[].http.paths[] | [.backend.service.name, .path] | @tsv' "$new_yaml" | sort > "$new_paths"

    local added_paths=$(comm -13 "$old_paths" "$new_paths" | wc -l)
    local removed_paths=$(comm -23 "$old_paths" "$new_paths" | wc -l)
    
    if [ "$added_paths" -gt 0 ]; then
        echo -e "${GREEN}Rutas NUEVAS agregadas:${NC}"
        comm -13 "$old_paths" "$new_paths" | awk -F'\t' '{printf "  + %-30s → %s\n", $1, $2}'
        echo ""
    fi

    if [ "$removed_paths" -gt 0 ]; then
        echo -e "${RED}Rutas ELIMINADAS:${NC}"
        comm -23 "$old_paths" "$new_paths" | awk -F'\t' '{printf "  - %-30s → %s\n", $1, $2}'
        echo ""
    fi
    
    if [ "$added_paths" -eq 0 ] && [ "$removed_paths" -eq 0 ]; then
        echo -e "${CYAN}  ● Sin cambios en las rutas${NC}"
        echo ""
    fi

    echo -e "${YELLOW}Modified Paths (service/path changed):${NC}"
    local services_all="${TMP_PREFIX}_services_all.txt"
    if ! awk -F'\t' '{print $1}' "$old_paths" | sort | uniq > "$services_all"; then
        warn "Failed to create services list for comparison"
    else
        while read -r svc; do
            if [ -n "$svc" ]; then
                old_svc_paths=$(awk -F'\t' -v s="$svc" '$1==s {print $2}' "$old_paths" | sort)
                new_svc_paths=$(awk -F'\t' -v s="$svc" '$1==s {print $2}' "$new_paths" | sort)
                if [ -n "$old_svc_paths" ] && [ -n "$new_svc_paths" ]; then
                    local old_temp="${TMP_PREFIX}_old_paths_${svc//[^a-zA-Z0-9]/_}.txt"
                    local new_temp="${TMP_PREFIX}_new_paths_${svc//[^a-zA-Z0-9]/_}.txt"
                    echo "$old_svc_paths" > "$old_temp"
                    echo "$new_svc_paths" > "$new_temp"
                    if ! diff "$old_temp" "$new_temp" >/dev/null 2>&1; then
                        echo -e "  ${BOLD}${svc}${NC}"
                        diff "$old_temp" "$new_temp" 2>/dev/null | grep -E '^[<>]' | sed 's/^</  Old: /;s/^>/  New: /' || true
                    fi
                    rm -f "$old_temp" "$new_temp" 2>/dev/null || true
                fi
            fi
        done < "$services_all"
    fi

    rm -f "$old_services" "$new_services" "$old_paths" "$new_paths" "$services_all" 2>/dev/null || true
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    success "Comparación completada exitosamente"
    return 0
}
