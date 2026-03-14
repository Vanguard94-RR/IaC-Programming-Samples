# FASE 2 - IMPLEMENTATION PLAN
## Workload Identity Manager - Refactoring & Code Quality

**Start Date**: March 13, 2026  
**Estimated Duration**: 7-9 hours (1 day)  
**Status**: 📋 PLANNED  
**Objective**: Eliminate code duplication, improve consistency, prepare for Phase 3 features

---

## EXECUTIVE SUMMARY

Fase 2 se enfoca en **mejorar la mantenibilidad** del código sin cambiar funcionalidad. Entregaremos:
- ✅ 1 función compartida para cluster selection (elimina 4 copies)
- ✅ Logging consistente en toda la aplicación
- ✅ Configuración externa (config.sh)
- ✅ Código limpio (remove dead code)

**Impacto**: Reducir líneas de código ~200-250 líneas, mejorar testability para Fase 3+

---

## PROBLEMA 1: DRY VIOLATION - Cluster Selection

### 📍 Ubicación del Problema

Código de "seleccionar cluster de proyecto" **REPETIDO 4+ veces**:

| Ubicación | Líneas | Contexto |
|-----------|--------|----------|
| operation_setup | ~750-780 | Configurar WI |
| operation_verify | ~990-1020 | Verificar WI |
| operation_cleanup | ~1270-1300 | Limpiar WI |
| operation_list | ~1550-1580 | Listar WIs |

### 🔍 Patrón Identificado

Cada operación hace EXACTAMENTE ESTO:

```bash
# 1. Prompt para project ID
prompt_input "Enter Project ID" "project_id" "$current_project"

# 2. Obtener clusters
local clusters_raw=$(list_gke_clusters "$project_id")
if [[ -z "$clusters_raw" ]]; then
    echo -e "\r${RED}✗ No clusters found${NC}"
    exit 1
fi

# 3. Parse into arrays
declare -a cluster_names
declare -a cluster_locations
declare -a cluster_options

while IFS=$'\t' read -r name location; do
    cluster_names+=("$name")
    cluster_locations+=("$location")
    cluster_options+=("$name ($location)")
done <<< "$clusters_raw"

# 4. Select if multiple
if [[ ${#cluster_options[@]} -eq 1 ]]; then
    selected_cluster="${cluster_names[0]}"
    selected_location="${cluster_locations[0]}"
else
    prompt_selection "Select GKE cluster:" cluster_options selected_option
    for i in "${!cluster_options[@]}"; do
        if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
            selected_cluster="${cluster_names[$i]}"
            selected_location="${cluster_locations[$i]}"
            break
        fi
    done
fi
```

### ✅ SOLUCIÓN: Extract to Function

**Nueva función** `select_cluster_from_project()`:

```bash
# =============================================================================
# Function: select_cluster_from_project
# Description: Interactive cluster selection with single-choice auto-select
# Parameters:
#   $1 = Project ID
#   $2 = Prompt message (optional, default: "Select GKE cluster:")
# Returns:
#   Sets variables: SELECTED_CLUSTER, SELECTED_LOCATION
#   0 = success, 1 = error/cancelled
# =============================================================================
select_cluster_from_project() {
    local project_id="$1"
    local prompt_msg="${2:-Select GKE cluster:}"
    
    echo -ne "${GRAY}Searching for clusters in project...${NC}"
    
    local clusters_raw=$(list_gke_clusters "$project_id")
    
    if [[ -z "$clusters_raw" ]]; then
        echo -e "\r${RED}✗ No clusters found${NC}"
        print_error "No hay clusters GKE en el proyecto $project_id"
        return 1
    fi
    
    echo -e "\r${LGREEN}✓ Clusters found${NC}          "
    echo ""
    
    # Parse clusters into arrays
    declare -a cluster_names
    declare -a cluster_locations
    declare -a cluster_options
    
    while IFS=$'\t' read -r name location; do
        cluster_names+=("$name")
        cluster_locations+=("$location")
        cluster_options+=("$name ($location)")
    done <<< "$clusters_raw"
    
    # Show selection menu or auto-select
    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        SELECTED_CLUSTER="${cluster_names[0]}"
        SELECTED_LOCATION="${cluster_locations[0]}"
        print_info "Single cluster found" "$SELECTED_CLUSTER ($SELECTED_LOCATION)"
    else
        if ! prompt_selection "$prompt_msg" cluster_options selected_option; then
            return 1
        fi
        
        # Find selected cluster in arrays
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
```

### 🔄 REFACTORING - Reemplazar 4 Instancias

#### INSTANCE 1: operation_setup (lines ~750-780)

**BEFORE** (31 líneas):
```bash
echo -ne "${GRAY}Searching for clusters in the project...${NC}"
local clusters_raw=$(list_gke_clusters "$project_id")
if [[ -z "$clusters_raw" ]]; then
    echo -e "\r${RED}✗ No clusters found${NC}     "
    print_error "No hay clusters GKE..."
    exit 1
fi
echo -e "\r${LGREEN}✓ Clusters found${NC}          "
...
# 25 más líneas de selection logic
```

**AFTER** (2 líneas):
```bash
if ! select_cluster_from_project "$project_id"; then
    exit 1
fi
# Variables SELECTED_CLUSTER, SELECTED_LOCATION ahora disponibles
```

#### INSTANCE 2: operation_verify (lines ~990-1020)

**Reemplazar**:
```bash
# --- Cluster Selection ---
# Get list of available clusters in the project
local clusters_raw=$(list_gke_clusters "$project_id")
...
# 25+ líneas
```

**Con**:
```bash
# --- Cluster Selection ---
if ! select_cluster_from_project "$project_id"; then
    return 1
fi
```

#### INSTANCE 3: operation_cleanup (lines ~1270-1300)

**Reemplazar bloque idéntico**

#### INSTANCE 4: operation_list (lines ~1550-1580)

**Reemplazar bloque idéntico**

### 📊 IMPACT

| Métrica | Antes | Después | Mejora |
|---------|-------|---------|--------|
| Lines de cluster code | 120+ (4x30) | 35 (función) | -85 líneas |
| Duplicación | 4x | 1x | 100% |
| Mantenimiento | Diff 4 places | Change 1 place | 4x más rápido |
| Testing | Test 4 times | Test 1 time | Simpler |

---

## PROBLEMA 2: Inconsistent Logging

### 📍 Ubicación del Problema

**Inconsistencia**: Algunas funciones hacen `tee -a "$G_LOG_FILE"`, otras usan `log()`, otras nada:

```bash
# GOOD: Creates IAM SA (lines ~954)
create_iam_sa() {
    gcloud iam service-accounts create "$sa_name" \
        --project "$project_id" \
        --display-name "$display_name" 2>&1 | tee -a "$G_LOG_FILE"
    ✓ Output va a log + stdout
}

# BAD: Verify IAM SA (lines ~409)
verify_iam_sa() {
    gcloud iam service-accounts describe "$sa_email" --project "$project_id" &>/dev/null
    ✗ CERO logging - output descartado
}

# GOOD: Helper uses log() (lines ~191)
log_and_print() {
    echo -e "${color}${message}${NC}"
    log "$message"
    ✓ Logging inconsistente
}
```

### 📋 AUDIT: Funciones sin Logging

| Función | Línea | Problema | Severidad |
|---------|-------|----------|-----------|
| `verify_iam_sa()` | 409 | Sin logging | Medium |
| `verify_ksa()` | 418 | Sin logging | Medium |
| `delete_ksa()` | 458 | Sin logging | Medium |
| `get_ksa_annotation()` | 468 | Sin logging | Low |
| `get_current_project()` | 354 | Sin logging | Low |
| `list_gke_clusters()` | 356 | Sin logging | Medium |

### ✅ SOLUCIÓN: Audit Log Wrapper

**Nueva función** `log_command_execution()`:

```bash
# =============================================================================
# Function: log_command_execution
# Description: Execute command with automatic logging of success/failure
# Parameters:
#   $1 = Command description (user-friendly)
#   $2 = Command to execute (gcloud/kubectl/etc)
#   $@(3+) = Additional arguments/options
# Returns:
#   0 = success, 1 = failed (command exit code)
# Side Effect:
#   - Logs command + result
#   - Prints progress indicator
# =============================================================================
log_command_execution() {
    local description="$1"
    shift  # Remove description from arguments
    local cmd="$@"
    
    log "▶ Executing: $description"
    
    # Execute and capture both output and exit code
    local output
    if output=$(eval "$cmd" 2>&1); then
        log "✓ Success: $description"
        log "  Output: $output"
        return 0
    else
        local exit_code=$?
        log "✗ Failed: $description (exit code: $exit_code)"
        log "  Error: $output"
        return $exit_code
    fi
}
```

### 🔄 REFACTORING - Add Logging

#### INSTANCE 1: verify_iam_sa (~409)

**BEFORE**:
```bash
verify_iam_sa() {
    local sa_email="$1"
    local project_id="$2"
    
    gcloud iam service-accounts describe "$sa_email" --project "$project_id" &>/dev/null
}
```

**AFTER**:
```bash
verify_iam_sa() {
    local sa_email="$1"
    local project_id="$2"
    
    log "Verifying IAM Service Account: $sa_email"
    
    if gcloud iam service-accounts describe "$sa_email" --project "$project_id" &>/dev/null; then
        log "✓ IAM SA exists: $sa_email"
        return 0
    else
        log "⚠ IAM SA not found: $sa_email"
        return 1
    fi
}
```

#### INSTANCE 2: verify_ksa (~418)

Similar treatment

#### INSTANCE 3: delete_ksa (~458)

```bash
delete_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    log "Deleting KSA: $ksa_name in namespace: $namespace"
    
    if kubectl delete serviceaccount "$ksa_name" -n "$namespace" 2>&1 | tee -a "$G_LOG_FILE"; then
        log "✓ KSA deleted: $ksa_name"
        return 0
    else
        log "✗ Failed to delete KSA: $ksa_name"
        return 1
    fi
}
```

### 📊 IMPACT

| Métrica | Antes | Después |
|---------|-------|---------|
| Functions sin logging | 6 | 0 |
| Log consistency | Inconsistente | ✓ Uniforme |
| Debug troubleshooting | Difícil | ✓ Fácil |
| Audit completeness | Parcial | ✓ Completo |

---

## PROBLEMA 3: Dead Code

### 📍 Ubicación

**Lines 503-507** in `list_workload_identities()`:

```bash
local found=false
...
while ... do
    if [[ -n "$ksa" ]]; then
        found=false  # ← NUNCA se usa, NUNCA es true
    fi
done
```

### ✅ SOLUCIÓN

**REMOVER COMPLETAMENTE estas líneas**:

```bash
# BEFORE (lineas 503-507):
    local found=false
    
    # Parse JSON output
    echo "$ksa_output" | jq -r ... | while IFS='|' read -r ksa annotation; do
        ...
        if [[ -n "$ksa" ]]; then
            found=false  # ← REMOVE
        fi
    done

# AFTER:
    # Parse JSON output  
    echo "$ksa_output" | jq -r ... | while IFS='|' read -r ksa annotation; do
        ...
        if [[ -n "$annotation" ]]; then
            echo -e "  ${LCYAN}•${NC} KSA: ${LGREEN}${ksa}${NC}"
            ...
        fi
    done
```

### 📊 IMPACT

| Métrica | Antes | Después |
|---------|-------|---------|
| Dead code lines | 5 | 0 |
| Readability | Confuso | ✓ Claro |
| Maintenance debt | +5 | 0 |

---

## PROBLEMA 4: Hard-Coded Configuration

### 📍 Ubicación

Valores hard-codeados esparcidos por el script:

| Valor | Línea | Uso | Impacto |
|-------|-------|-----|--------|
| Role: `roles/iam.workloadIdentityUser` | 491 | IAM binding | Medium |
| Namespace default: `apps` | 63 | Input default | Low |
| CSV filename: `workload-identity-registry.csv` | 66 | Path | Low |
| Annotation key: `iam.gke.io/gcp-service-account` | 442, 480 | Kubernetes | Low |

### ✅ SOLUCIÓN: External Config File

**Crear** `config.sh`:

```bash
#!/bin/bash
# =============================================================================
# Workload Identity Manager - Configuration
# Override defaults by setting BEFORE running workload-identity.sh
# =============================================================================

# --- GCP Configuration ---
# IAM Role to bind with Workload Identity
export WI_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"

# Service account naming convention
export WI_SA_PREFIX="${WI_SA_PREFIX:-}"

# --- Kubernetes Configuration ---
# Default namespace for KSA creation
export WI_DEFAULT_NAMESPACE="${WI_DEFAULT_NAMESPACE:-apps}"

# Workload Identity annotation key
export WI_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"

# --- Files and Paths ---
# CSV registry filename
export WI_REGISTRY_FILE="${WI_REGISTRY_FILE:-workload-identity-registry.csv}"

# Log directory
export WI_LOG_DIR="${WI_LOG_DIR:-./logs}"

# Ticket directory prefix
export WI_TICKET_DIR_PREFIX="${WI_TICKET_DIR_PREFIX:-../Tickets}"

# --- Behavior ---
# Max retries for GCP operations
export WI_MAX_RETRIES="${WI_MAX_RETRIES:-3}"

# Timeout for gcloud commands (seconds)
export WI_COMMAND_TIMEOUT="${WI_COMMAND_TIMEOUT:-30}"

# Enable verbose logging
export WI_VERBOSE="${WI_VERBOSE:-0}"

# --- Advanced ---
# gcloud project override (leave empty to use current)
export WI_GCP_PROJECT="${WI_GCP_PROJECT:-}"

# kubectl context override (leave empty to use current)
export WI_KUBECTL_CONTEXT="${WI_KUBECTL_CONTEXT:-}"
```

### 🔄 REFACTORING - Use Config

#### Update workload-identity.sh

**Add at top** (after color definitions, line ~45):

```bash
# --- Load Configuration ---
readonly CONFIG_DIR="$(dirname "${BASH_SOURCE[0]}")"
if [[ -f "$CONFIG_DIR/config.sh" ]]; then
    source "$CONFIG_DIR/config.sh"
fi

# Use config values with fallbacks
readonly G_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"
readonly G_DEFAULT_NAMESPACE="${WI_DEFAULT_NAMESPACE:-apps}"
readonly G_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"
readonly G_MAX_RETRIES="${WI_MAX_RETRIES:-3}"
```

#### Replace hard-coded values

**Line 491** (add_iam_binding):
```bash
# BEFORE:
--role "roles/iam.workloadIdentityUser" \

# AFTER:
--role "$G_IAM_ROLE" \
```

**Line 63** (G_NAMESPACE default):
```bash
# BEFORE:
G_NAMESPACE="apps"

# AFTER:
G_NAMESPACE="${WI_DEFAULT_NAMESPACE:-apps}"
```

**Line 442** (annotate_ksa):
```bash
# BEFORE:
"iam.gke.io/gcp-service-account=\"${iam_sa_email}\""

# AFTER:
"${G_ANNOTATION_KEY}=\"${iam_sa_email}\""
```

### 📊 IMPACT

| Beneficio | Antes | Después |
|-----------|-------|---------|
| Config hard-coded | ✗ 4 lugares | ✓ 1 archivo |
| Customize behavior | Manual edit | Env variables |
| Multi-environment | Imposible | ✓ Fácil |
| Docker-friendly | Mal | ✓ Bueno |

---

## PROBLEMA 5: Duplicate Cluster Connection Logic

### 📍 Ubicación

Código de "conectar a cluster" aparece repetido:

```bash
# Line ~338: connect_to_cluster() - Decide regional vs zonal

# Line ~780: operation_setup() - Llama connect_to_cluster

# Line ~1020: operation_verify() - Llama connect_to_cluster

# Line ~1300: operation_cleanup() - Llama connect_to_cluster

# Line ~1580: operation_list() - Llama connect_to_cluster
```

### ✅ SOLUCIÓN: Centralizar error handling

**Update** `connect_to_cluster()` para manejar errores internamente:

```bash
connect_to_cluster() {
    local cluster_name="$1"
    local location="$2"
    local project_id="$3"
    local attempt=1
    local max_attempts=3
    
    log "Attempting to connect to cluster: $cluster_name in $location (Project: $project_id)"
    
    while [[ $attempt -le $max_attempts ]]; do
        # Determine if regional or zonal
        local region_flag=""
        if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
            region_flag="--region"
        else
            region_flag="--zone"
        fi
        
        # Try connection
        if gcloud container clusters get-credentials "$cluster_name" \
            $region_flag "$location" \
            --project "$project_id" &>/dev/null; then
            log "✓ Successfully connected to cluster: $cluster_name"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "⚠ Connection attempt $attempt failed, retrying..."
            sleep 2
            ((attempt++))
        else
            ((attempt++))
        fi
    done
    
    log "✗ Failed to connect after $max_attempts attempts"
    return 1
}
```

---

## IMPLEMENTATION TIMELINE

### ⏱️ Estimated Effort by Task

| Tarea | Duración | Complejidad | Riesgo |
|-------|----------|-------------|--------|
| **1. Extract select_cluster_from_project()** | 1.5 hrs | Media | 🟡 Medio |
| **2. Refactor 4 instances of cluster selection** | 2 hrs | Media | 🔴 Alto |
| **3. Add logging to 6 functions** | 1.5 hrs | Baja | 🟢 Bajo |
| **4. Remove dead code (lines 503-507)** | 30 min | Trivial | 🟢 Bajo |
| **5. Create config.sh** | 30 min | Baja | 🟢 Bajo |
| **6. Replace hard-coded values** | 1 hr | Baja | 🟡 Medio |
| **7. Testing + Validation** | 1.5 hrs | Media | 🟡 Medio |
| **8. Documentation** | 30 min | Baja | 🟢 Bajo |
| **TOTAL** | **8.5 hrs** | **Media** | **🟡 Medio** |

### 🗓️ EXECUTION SCHEDULE

```
09:00-10:30 → Task 1 (Extract function)
10:30-12:30 → Task 2 (Refactor 4 instances) ← CRITICAL
12:30-13:00 → LUNCH BREAK
13:00-14:30 → Task 3 (Add logging)
14:30-15:00 → Task 4 (Dead code)
15:00-15:30 → Task 5 (config.sh)
15:30-16:30 → Task 6 (Replace values)
16:30-18:00 → Task 7 (Testing)
18:00-18:30 → Task 8 (Docs)
────────────
Total: 8.5 hrs → Completable in 1 day
```

---

## DEPENDENCIES & RISKS

### 🔄 Task Dependencies

```
Task 1 (Extract function)
    ↓
Task 2 (Refactor × 4) ← Depends on Task 1
    ↓
Task 3-6 (Independent) ← Can run in parallel
    ↓
Task 7 (Testing) ← Needs Tasks 2-6 complete
    ↓
Task 8 (Docs)
```

### ⚠️ Risk Analysis

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Refactor breaks cluster selection | 30% | CRITICAL | Parallel testing in Phase 7 |
| Service account logging edge cases | 20% | Medium | Email redaction already in place |
| Config file load fails | 10% | Low | Graceful fallback to defaults |
| Merge conflicts if parallel dev | 15% | Medium | Linear implementation |

### 🛡️ Mitigation Strategy

1. **Before Task 2**: Commit working state (post-Phase 1)
2. **During Task 2**: Test each refactor immediately
3. **After Task 6**: Run full test suite (Phase 7)
4. **Rollback Plan**: `git revert` commit if tests fail

---

## TESTING STRATEGY

### 🧪 Unit Tests

```bash
# Test 1: select_cluster_from_project()
- Input: project_id with 0 clusters → Should fail gracefully
- Input: project_id with 1 cluster → Should auto-select
- Input: project_id with 3+ clusters → Should show menu
- Cancel selection → Should return 1

# Test 2: Logging consistency
- Verify all 6 functions now call log()
- Verify log output contains function name
- Verify email redaction works

# Test 3: Config loading
- config.sh exists → Load values
- config.sh missing → Use defaults
- Environment variable override → Take precedence
```

### 🔗 Integration Tests

```bash
# Test operation_setup with new select_cluster_from_project()
- Create full WI config
- Verify cluster selection works
- Verify logs written correctly

# Test operation_cleanup with new logging
- Delete WI with verbose logging
- Verify all steps logged

# Test operation_list after code cleanup
- List WIs in namespace
- Verify no dead code executed
```

### ✅ Regression Tests

```bash
# Ensure Phase 1 fixes still work:
- jq dependency check still works
- Validations still called
- Shell injection still fixed
- CSV permissions still 600
- Token refresh still works
- Retry logic still works
```

---

## ROLLBACK PLAN

### 📌 If Testing Fails

```bash
# Option 1: Rollback single task
git checkout HEAD -- workload-identity.sh  # Undo last changes

# Option 2: Rollback entire phase
git revert [commit-hash]  # Revert to post-Phase 1 state

# Option 3: Cherry-pick working tasks
git checkout origin/phase1-complete -- workload-identity.sh
# Then manually reapply safe changes (config.sh, dead code removal)
```

---

## SUCCESS CRITERIA

✅ **Phase 2 Complete When**:

- [ ] `select_cluster_from_project()` function exists and tested
- [ ] No code duplication in 4 operation functions (cluster selection)
- [ ] All 6 functions have logging calls
- [ ] Dead code (lines 503-507) removed
- [ ] `config.sh` created with all defaults
- [ ] All hard-coded values replaced with config references
- [ ] Bash syntax check passes: `bash -n workload-identity.sh`
- [ ] Unit tests all pass
- [ ] Integration tests all pass
- [ ] Regression tests all pass (Phase 1 fixes still work)
- [ ] Line count reduced: 1953 → ~1700 (-250 lines)
- [ ] Documentation updated

---

## DELIVERABLES

### 📦 Output Files

1. **workload-identity.sh** (refactored & cleaned)
   - 1 new function: `select_cluster_from_project()`
   - 6 functions with added logging
   - 5 lines dead code removed
   - Config references instead of hard-coded values
   - Syntax validated

2. **config.sh** (new)
   - Environment-based configuration
   - Clear defaults
   - Documentation

3. **PHASE2_COMPLETE.md** (summary)
   - Changes applied
   - Testing results
   - Metrics before/after

4. **workload-identity.sh.backup** (optional safety copy)
   - Pre-Phase 2 version

---

## NEXT STEPS AFTER PHASE 2

### Phase 3: Production Features (12-14 hrs)
- CLI mode (non-interactive)
- Dry-run capability
- Bulk operations
- Audit logging

### Phase 4: Security (8-10 hrs)
- CSV encryption
- Backup/Restore
- State synchronization

### Phase 5: Testing & Docs (8-10 hrs)
- Full test suite
- Playbooks
- Troubleshooting guide

---

**Status**: 📋 Ready for Implementation  
**Owner**: GitHub Copilot  
**Last Updated**: March 13, 2026
