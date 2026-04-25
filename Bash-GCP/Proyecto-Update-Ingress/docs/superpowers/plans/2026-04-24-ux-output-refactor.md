# UX Output Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize all script output to English, eliminate visual noise, add rollback box, health check countdown, and final deployment summary.

**Architecture:** Pure output/string changes across 7 files. No logic or control flow is modified. Two new UI helpers (`print_command_box`, `print_summary_box`) are added to `lib/ui.sh`. A new `DEPLOY_RESULT` global is set by `apply_new_ingress` and consumed by the entrypoint summary.

**Tech Stack:** Bash 5+, kubectl, gcloud, yq

---

### Task 1: Add `print_command_box` and `print_summary_box` to `lib/ui.sh`

**Files:**
- Modify: `lib/ui.sh`

- [ ] **Step 1: Append `print_command_box` after `read_input` (end of file)**

```bash
# print_command_box <title> <cmd>
print_command_box() {
    local title="$1"
    local cmd="$2"
    local min_width=44
    local content_len=${#title}
    [ ${#cmd} -gt $content_len ] && content_len=${#cmd}
    local width=$(( content_len + 4 > min_width ? content_len + 4 : min_width ))
    local bar=""
    for ((i=1; i<=width; i++)); do bar+="═"; done
    printf '%b\n' "${CYAN}╔${bar}╗${NC}"
    printf '%b\n' "${CYAN}║${NC}  ${WHITE}${BOLD}${title}${NC}$(printf '%*s' $(( width - ${#title} - 2 )) "")${CYAN}║${NC}"
    printf '%b\n' "${CYAN}║${NC}  ${WHITE}${cmd}${NC}$(printf '%*s' $(( width - ${#cmd} - 2 )) "")${CYAN}║${NC}"
    printf '%b\n' "${CYAN}╚${bar}╝${NC}"
}
```

- [ ] **Step 2: Append `print_summary_box` after `print_command_box`**

```bash
# print_summary_box
# Uses globals: TICKET_ID, PROJECT_ID, CLUSTER_NAME, NAMESPACE,
#               INGRESS_NAME, CLEAN_FILE, DEPLOY_RESULT
print_summary_box() {
    local result="${DEPLOY_RESULT:-UNKNOWN}"
    local rollback_file
    rollback_file=$(basename "${CLEAN_FILE:-N/A}")
    local rollback_cmd="kubectl apply -f ${rollback_file} -n ${NAMESPACE:-N/A}"
    local rows=(
        "Ticket:   ${TICKET_ID:-N/A}"
        "Project:  ${PROJECT_ID:-N/A}"
        "Cluster:  ${CLUSTER_NAME:-N/A}"
        "Ingress:  ${INGRESS_NAME:-N/A}  [${NAMESPACE:-N/A}]"
        "Result:   ${result}"
        "Rollback: ${rollback_cmd}"
    )
    local width=52
    local row
    for row in "${rows[@]}"; do
        local row_len=$(( ${#row} + 4 ))
        [ $row_len -gt $width ] && width=$row_len
    done
    local bar="" title="DEPLOYMENT SUMMARY"
    for ((i=1; i<=width; i++)); do bar+="═"; done
    printf '%b\n' "${CYAN}╔${bar}╗${NC}"
    printf '%b\n' "${CYAN}║${NC}  ${WHITE}${BOLD}${title}${NC}$(printf '%*s' $(( width - ${#title} - 2 )) "")${CYAN}║${NC}"
    printf '%b\n' "${CYAN}╠${bar}╣${NC}"
    for row in "${rows[@]}"; do
        printf '%b\n' "${CYAN}║${NC}  ${WHITE}${row}${NC}$(printf '%*s' $(( width - ${#row} - 2 )) "")${CYAN}║${NC}"
    done
    printf '%b\n' "${CYAN}╚${bar}╝${NC}"
}
```

- [ ] **Step 3: Syntax check**

```bash
bash -n lib/ui.sh
```
Expected: no output (no errors).

- [ ] **Step 4: Smoke-test `print_command_box`**

```bash
source lib/ui.sh && print_command_box "ROLLBACK COMMAND (save this)" "kubectl apply -f rollback.yaml -n my-namespace"
```
Expected: a cyan box with two lines, at least 44 chars wide.

- [ ] **Step 5: Smoke-test `print_summary_box`**

```bash
source lib/ui.sh && \
  TICKET_ID=CTASK0001 PROJECT_ID=my-project CLUSTER_NAME=my-cluster \
  NAMESPACE=my-ns INGRESS_NAME=my-ingress CLEAN_FILE=/tmp/rollback.yaml \
  DEPLOY_RESULT="✔ UPDATED" \
  print_summary_box
```
Expected: a cyan box with DEPLOYMENT SUMMARY header and 6 data rows.

- [ ] **Step 6: Commit**

```bash
git add lib/ui.sh
git commit -m "feat: add print_command_box and print_summary_box to ui.sh"
```

---

### Task 2: Update `lib/kube_select.sh` — EN strings + `step()` consistency

**Files:**
- Modify: `lib/kube_select.sh`

- [ ] **Step 1: Replace error helpers in `select_gcp_project`**

Replace:
```bash
            echo -e "${RED}Project ID cannot be empty. Please try again.${NC}"
```
With:
```bash
            error "Project ID cannot be empty. Please try again."
```

Replace:
```bash
            echo -e "${RED}Failed to set project. Please check the project ID and try again.${NC}"
```
With:
```bash
            error "Failed to set project. Check the project ID and try again."
```

- [ ] **Step 2: Replace error helpers in `select_cluster`**

Replace (line ~37):
```bash
        echo -e "${RED}Failed to list clusters. Exiting.${NC}"
```
With:
```bash
        error "Failed to list clusters. Exiting."
```

Replace (line ~41):
```bash
        echo -e "${RED}No clusters found in project. Exiting.${NC}"
```
With:
```bash
        error "No clusters found in project. Exiting."
```

Replace (line ~68, inside post-loop check):
```bash
        echo -e "${RED}No clusters found in project. Exiting.${NC}"
```
With:
```bash
        error "No clusters found in project. Exiting."
```

- [ ] **Step 3: Fix `connect_to_cluster` — replace entire function**

Replace:
```bash
connect_to_cluster() {
    echo -e "\n${YELLOW}Step 3: Connect to cluster${NC}"
    if ! gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_ZONE" --project "$PROJECT_ID"; then
        echo -e "${RED}Failed to connect to cluster. Exiting.${NC}"
        exit 1
    fi
}
```
With:
```bash
connect_to_cluster() {
    step "Step 3: Connect to cluster"
    if ! gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_ZONE" --project "$PROJECT_ID"; then
        error "Failed to connect to cluster. Exiting."
        exit 1
    fi
}
```

- [ ] **Step 4: Replace error helpers in `namespace_and_ingress_name`**

Replace (line ~97):
```bash
        echo -e "${RED}Failed to list Ingress resources. Exiting.${NC}"
```
With:
```bash
        error "Failed to list Ingress resources. Exiting."
```

Replace (line ~101):
```bash
        echo -e "${RED}No Ingress resources found in any namespace. Exiting.${NC}"
```
With:
```bash
        error "No Ingress resources found in any namespace. Exiting."
```

Replace (line ~130):
```bash
        echo -e "${RED}No Ingress resources found. Exiting.${NC}"
```
With:
```bash
        error "No Ingress resources found. Exiting."
```

Replace (line ~143):
```bash
    echo -e "${YELLOW}Selected ingress: ${CYAN}$INGRESS_NAME${NC} in namespace: ${CYAN}$NAMESPACE${NC}"
```
With:
```bash
    info "Selected: $INGRESS_NAME  [namespace: $NAMESPACE]"
```

- [ ] **Step 5: Syntax check**

```bash
bash -n lib/kube_select.sh
```
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add lib/kube_select.sh
git commit -m "fix: standardize kube_select.sh output to EN and use step/error helpers"
```

---

### Task 3: Update `lib/kube_backup.sh` — rollback command box

**Files:**
- Modify: `lib/kube_backup.sh`

- [ ] **Step 1: Replace rollback info lines with `print_command_box`**

Find:
```bash
            success "Rollback-ready backup saved as $CLEAN_FILE"
            info "To rollback, run:"
            info "kubectl apply -f $CLEAN_FILE -n $NAMESPACE"
```
Replace with:
```bash
            success "Rollback-ready backup saved as $CLEAN_FILE"
            print_command_box "ROLLBACK COMMAND (save this)" "kubectl apply -f $CLEAN_FILE -n $NAMESPACE"
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/kube_backup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add lib/kube_backup.sh
git commit -m "feat: display rollback command in highlighted box"
```

---

### Task 4: Update `lib/apply_new_ingress.sh` — EN strings, remove `═══`, set `DEPLOY_RESULT`

**Files:**
- Modify: `lib/apply_new_ingress.sh`

- [ ] **Step 1: Translate step header and operation messages**

Replace:
```bash
    step "Iniciando proceso de aplicación del nuevo Ingress"
```
With:
```bash
    step "Applying new Ingress"
```

Replace:
```bash
        info "Operación detectada: ${BOLD}ACTUALIZACIÓN${NC} del Ingress existente"
```
With:
```bash
        info "Operation: UPDATE (Ingress already exists)"
```

Replace:
```bash
        info "Operación detectada: ${BOLD}CREACIÓN${NC} de nuevo Ingress"
```
With:
```bash
        info "Operation: CREATE (new Ingress)"
```

- [ ] **Step 2: Translate dry-run validation block**

Replace:
```bash
    echo -e "\n${YELLOW}Validando nuevo ingress.yaml (server-side dry-run)...${NC}"
    if ! kubectl apply -f ingress.yaml -n "$NAMESPACE" --dry-run=server >/dev/null 2>&1; then
        echo -e "${RED}ingress.yaml falló la validación server-side. Abortando aplicación.${NC}"
```
With:
```bash
    info "Validating ingress.yaml (server-side dry-run)..."
    if ! kubectl apply -f ingress.yaml -n "$NAMESPACE" --dry-run=server >/dev/null 2>&1; then
        error "ingress.yaml failed server-side validation. Aborting."
```

- [ ] **Step 3: Remove `═══` separators from kubectl diff block**

Replace:
```bash
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
```
With:
```bash
    if [ "$operation" = "UPDATE" ] && [ -f "$BACKUP_FILE" ]; then
        step "Preview of changes (kubectl diff)"
        local diff_output
        diff_output=$(kubectl diff -f ingress.yaml -n "$NAMESPACE" 2>/dev/null || true)
        if [ -n "$diff_output" ]; then
            printf "%s\n" "$diff_output"
        else
            info "No structural changes detected"
        fi
    fi
```

- [ ] **Step 4: Translate dry-run mode and confirmation messages**

Replace:
```bash
    if [ "${DRY_RUN:-false}" = "true" ]; then
        echo -e "${YELLOW}Modo dry-run: validación pasada, no se aplicará.${NC}"
        return 0
    fi
```
With:
```bash
    if [ "${DRY_RUN:-false}" = "true" ]; then
        info "Dry-run: validation passed, no changes applied."
        return 0
    fi
```

Replace:
```bash
    echo -e "\n${YELLOW}¿Desea aplicar el nuevo ingress.yaml? (${operation})${NC}"
    printf "%b" "${CYAN}Escriba '${WHITE}${BOLD}yes${NC}${CYAN}' o '${WHITE}${BOLD}Y${NC}${CYAN}' para continuar: ${NC}"
```
With:
```bash
    warn "Apply new ingress.yaml? (${operation})"
    printf "%b" "${CYAN}Type '${WHITE}${BOLD}yes${NC}${CYAN}' or '${WHITE}${BOLD}Y${NC}${CYAN}' to continue: ${NC}"
```

- [ ] **Step 5: Translate apply outcome messages and set `DEPLOY_RESULT`**

Replace the entire success/fail/cancel block:
```bash
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
```
With:
```bash
        if [ $exit_code -eq 0 ]; then
            if echo "$apply_output" | grep -q "configured"; then
                success "Ingress updated: $apply_output"
                DEPLOY_RESULT="✔ UPDATED"
            elif echo "$apply_output" | grep -q "created"; then
                success "Ingress created: $apply_output"
                DEPLOY_RESULT="✔ CREATED"
            elif echo "$apply_output" | grep -q "unchanged"; then
                info "Ingress unchanged: $apply_output"
                DEPLOY_RESULT="● UNCHANGED"
            else
                success "Ingress applied: $apply_output"
                DEPLOY_RESULT="✔ APPLIED"
            fi
            post_apply_validation
        else
            error "Failed to apply Ingress: $apply_output"
            DEPLOY_RESULT="✖ FAILED"
            return 1
        fi
    else
        info "Cancelled. No changes applied."
        DEPLOY_RESULT="⚠ CANCELLED"
    fi
```

- [ ] **Step 6: Syntax check**

```bash
bash -n lib/apply_new_ingress.sh
```
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add lib/apply_new_ingress.sh
git commit -m "fix: apply_new_ingress — EN strings, remove decorators, add DEPLOY_RESULT"
```

---

### Task 5: Refactor `lib/compare_ingress_services.sh`

**Files:**
- Modify: `lib/compare_ingress_services.sh`

This is a full replacement of the function body. All `═══` lines removed, strings translated, sub-sections rendered conditionally, unchanged services collapsed to one line.

- [ ] **Step 1: Replace the entire `compare_ingress_services` function body**

Replace everything from `compare_ingress_services() {` through the closing `}` with:

```bash
compare_ingress_services() {
    step "Backend service comparison"
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

    local old_list="${TMP_PREFIX}_services_old_list.txt"
    local new_list="${TMP_PREFIX}_services_new_list.txt"
    sort "$old_services" > "$old_list"
    sort "$new_services" > "$new_list"

    local added removed unchanged
    added=$(comm -13 "$old_list" "$new_list" | wc -l | tr -d ' ')
    removed=$(comm -23 "$old_list" "$new_list" | wc -l | tr -d ' ')
    unchanged=$(comm -12 "$old_list" "$new_list" | wc -l | tr -d ' ')

    # Unchanged: inline names when ≤3, count-only when >3
    local unchanged_inline=""
    if [ "$unchanged" -gt 0 ] && [ "$unchanged" -le 3 ]; then
        unchanged_inline="  ($(comm -12 "$old_list" "$new_list" | tr '\n' ',' | sed 's/,$//') )"
    fi

    printf "  ${GREEN}✚ New:      %s${NC}\n" "$added"
    printf "  ${RED}✖ Removed:  %s${NC}\n" "$removed"
    if [ "$unchanged" -gt 3 ]; then
        printf "  ${CYAN}● Unchanged: %s services${NC}\n" "$unchanged"
    else
        printf "  ${CYAN}● Unchanged: %s%s${NC}\n" "$unchanged" "$unchanged_inline"
    fi

    if [ "$added" -gt 0 ]; then
        echo ""
        info "New services:"
        comm -13 "$old_list" "$new_list" | sed 's/^/    + /'
    fi

    if [ "$removed" -gt 0 ]; then
        echo ""
        info "Removed services:"
        comm -23 "$old_list" "$new_list" | sed 's/^/    - /'
    fi

    rm -f "$old_list" "$new_list" "$old_services" "$new_services"

    # Path comparison
    local old_paths="${TMP_PREFIX}_paths_old.txt"
    local new_paths="${TMP_PREFIX}_paths_new.txt"
    yq eval '.spec.rules[].http.paths[] | [.backend.service.name, .path] | @tsv' "$old_yaml" | sort > "$old_paths"
    yq eval '.spec.rules[].http.paths[] | [.backend.service.name, .path] | @tsv' "$new_yaml" | sort > "$new_paths"

    local added_paths removed_paths
    added_paths=$(comm -13 "$old_paths" "$new_paths" | wc -l | tr -d ' ')
    removed_paths=$(comm -23 "$old_paths" "$new_paths" | wc -l | tr -d ' ')

    if [ "$added_paths" -gt 0 ]; then
        echo ""
        info "New paths:"
        comm -13 "$old_paths" "$new_paths" | awk -F'\t' '{printf "    + %-30s → %s\n", $1, $2}'
    fi

    if [ "$removed_paths" -gt 0 ]; then
        echo ""
        info "Removed paths:"
        comm -23 "$old_paths" "$new_paths" | awk -F'\t' '{printf "    - %-30s → %s\n", $1, $2}'
    fi

    # Modified paths per-service (conditional — only header if there is content)
    local services_all="${TMP_PREFIX}_services_all.txt"
    local has_modified=false
    if awk -F'\t' '{print $1}' "$old_paths" | sort | uniq > "$services_all" 2>/dev/null; then
        while read -r svc; do
            [ -z "${svc}" ] && continue
            local old_svc_paths new_svc_paths
            old_svc_paths=$(awk -F'\t' -v s="$svc" '$1==s {print $2}' "$old_paths" | sort)
            new_svc_paths=$(awk -F'\t' -v s="$svc" '$1==s {print $2}' "$new_paths" | sort)
            if [ -n "$old_svc_paths" ] && [ -n "$new_svc_paths" ]; then
                local old_temp="${TMP_PREFIX}_old_${svc//[^a-zA-Z0-9]/_}.txt"
                local new_temp="${TMP_PREFIX}_new_${svc//[^a-zA-Z0-9]/_}.txt"
                printf "%s\n" "$old_svc_paths" > "$old_temp"
                printf "%s\n" "$new_svc_paths" > "$new_temp"
                if ! diff "$old_temp" "$new_temp" >/dev/null 2>&1; then
                    if [ "$has_modified" = false ]; then
                        echo ""
                        info "Modified paths (service/path changed):"
                        has_modified=true
                    fi
                    printf "    %s\n" "$svc"
                    diff "$old_temp" "$new_temp" 2>/dev/null | grep -E '^[<>]' \
                        | sed 's/^</      old: /;s/^>/      new: /' || true
                fi
                rm -f "$old_temp" "$new_temp" 2>/dev/null || true
            fi
        done < "$services_all"
    fi

    rm -f "$old_paths" "$new_paths" "$services_all" 2>/dev/null || true

    echo ""
    success "Comparison complete"
    return 0
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/compare_ingress_services.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add lib/compare_ingress_services.sh
git commit -m "refactor: compare_ingress_services — EN, conditional sections, collapsed unchanged"
```

---

### Task 6: Update `lib/post_apply_validation.sh` — health check countdown

**Files:**
- Modify: `lib/post_apply_validation.sh`

- [ ] **Step 1: Replace static "Waiting..." message with single-line header**

Replace:
```bash
        echo -e "${YELLOW}Waiting for all backend health checks to return 2xx/3xx. Re-checking every ${HEALTHCHECK_INTERVAL}s. Press Ctrl+C to abort.${NC}"
```
With:
```bash
        info "Waiting for backend health checks (timeout: ${HEALTHCHECK_TIMEOUT}s, interval: ${HEALTHCHECK_INTERVAL}s)"
```

- [ ] **Step 2: Replace `sleep $HEALTHCHECK_INTERVAL` with countdown loop**

Find:
```bash
                warn "Some backend health checks are failing. Rechecking in ${HEALTHCHECK_INTERVAL}s..."
                sleep $HEALTHCHECK_INTERVAL
```
Replace with:
```bash
                warn "Some checks failing."
                local j
                for ((j=HEALTHCHECK_INTERVAL; j>0; j--)); do
                    printf "\r  ${CYAN}Next check in: %ds  [Ctrl+C to abort]${NC}  " "$j"
                    sleep 1
                done
                printf "\r%-60s\r" ""
```

- [ ] **Step 3: Syntax check**

```bash
bash -n lib/post_apply_validation.sh
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add lib/post_apply_validation.sh
git commit -m "feat: replace static health check sleep with live countdown"
```

---

### Task 7: Update `bin/update_ingress.v2.sh` — single banner, EN strings, summary box

**Files:**
- Modify: `bin/update_ingress.v2.sh`

- [ ] **Step 1: Collapse double banner to single**

Replace:
```bash
print_banner_box "GNP Cloud Infrastructure Team"
print_banner_box "Kubernetes Ingress Updater — v2"
```
With:
```bash
print_banner_box "Kubernetes Ingress Updater — v2"
info "GNP Cloud Infrastructure Team"
```

- [ ] **Step 2: Translate ticket section strings**

Replace:
```bash
    step "Configuración de Ticket"
```
With:
```bash
    step "Ticket configuration"
```

Replace:
```bash
        info "Ticket detectado desde directorio actual: $TICKET_ID"
```
With:
```bash
        info "Ticket detected from current directory: $TICKET_ID"
```

Replace:
```bash
        read_input TICKET_ID "${CYAN}Ingrese el ID del Ticket (ej: CTASK0337281): ${WHITE}${BOLD}"
```
With:
```bash
        read_input TICKET_ID "${CYAN}Enter Ticket ID (e.g. CTASK0337281): ${WHITE}${BOLD}"
```

Replace:
```bash
            error "El ID del ticket no puede estar vacío"
```
With:
```bash
            error "Ticket ID cannot be empty"
```

Replace:
```bash
            error "Formato de ticket inválido. Use CTASK######## o TASK#######"
```
With:
```bash
            error "Invalid ticket format. Use CTASK######## or TASK########"
```

Replace:
```bash
        warn "El directorio del ticket no existe: $TICKET_DIR"
        read_input CREATE_DIR "${CYAN}¿Desea crear el directorio? (Y/N): ${NC}"
```
With:
```bash
        warn "Ticket directory not found: $TICKET_DIR"
        read_input CREATE_DIR "${CYAN}Create it? (Y/N): ${NC}"
```

Replace:
```bash
                success "Directorio creado: $TICKET_DIR"
```
With:
```bash
                success "Directory created: $TICKET_DIR"
```

Replace:
```bash
                error "No se pudo crear el directorio"
```
With:
```bash
                error "Failed to create directory"
```

Replace:
```bash
            error "Operación cancelada: El directorio del ticket es necesario"
```
With:
```bash
            error "Cancelled: ticket directory is required"
```

Replace:
```bash
        success "Trabajando en: $TICKET_DIR"
```
With:
```bash
        success "Working in: $TICKET_DIR"
```

Replace:
```bash
        error "No se pudo cambiar al directorio: $TICKET_DIR"
```
With:
```bash
        error "Failed to change to directory: $TICKET_DIR"
```

- [ ] **Step 3: Replace `Script finished.` with `print_summary_box`**

Replace:
```bash
echo -e "${CYAN}Script finished.${NC}"
```
With:
```bash
print_summary_box
```

- [ ] **Step 4: Syntax check**

```bash
bash -n bin/update_ingress.v2.sh
```
Expected: no output.

- [ ] **Step 5: Integration smoke test**

```bash
NO_CLUSTER=1 bash bin/update_ingress.v2.sh --dry-run 2>&1 | head -20
```
Expected: single banner box, `• GNP Cloud Infrastructure Team` info line, English prereq messages, clean exit.

- [ ] **Step 6: Verify no Spanish characters remain in lib/ and bin/**

```bash
grep -rn '[áéíóúñ¿¡ÁÉÍÓÚÑü]' lib/ bin/
```
Expected: no output.

- [ ] **Step 7: Verify no `═══` decorators remain in lib/ and bin/**

```bash
grep -rn '═══' lib/ bin/
```
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add bin/update_ingress.v2.sh
git commit -m "feat: single banner, EN strings, deployment summary box in entrypoint"
```
