#!/bin/bash
# =============================================================================
# Workload Identity Manager
# Configure GCP Workload Identity between GCP SA and Kubernetes SA
# =============================================================================

set -e

# --- Colors ---
LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[0;31m'
GRAY='\033[0;37m'
NC='\033[0m'

# --- Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TICKETS_DIR="$BASE_DIR/Tickets"
CONTROL_FILE="$SCRIPT_DIR/workload-identity-registry.csv"
LOG_DIR=""
LOG_FILE=""
TICKET_ID=""
NAMESPACE="apps"

# --- Initialize control file if not exists ---
init_control_file() {
    if [[ ! -f "$CONTROL_FILE" ]]; then
        echo "Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA,Status" > "$CONTROL_FILE"
    else
        # Migrate old format (without Status column) to new format
        local header=$(head -1 "$CONTROL_FILE")
        if [[ ! "$header" =~ "Status" ]]; then
            # Add Status column to header and 'activo' to all existing records
            sed -i '1s/$/,Status/' "$CONTROL_FILE"
            sed -i '2,$s/$/,activo/' "$CONTROL_FILE"
        fi
    fi
}

# --- Register execution in control file ---
register_execution() {
    local ticket="$1"
    local project="$2"
    local cluster="$3"
    local location="$4"
    local namespace="$5"
    local ksa="$6"
    local iam_sa="$7"
    local status="${8:-activo}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Use "-" if no ticket
    [[ -z "$ticket" ]] && ticket="-"
    
    echo "${timestamp},${ticket},${project},${cluster},${location},${namespace},${ksa},${iam_sa},${status}" >> "$CONTROL_FILE"
}

# --- Update registry status (mark as eliminated) ---
update_registry_status() {
    local project="$1"
    local cluster="$2"
    local namespace="$3"
    local ksa="$4"
    local new_status="$5"
    
    if [[ ! -f "$CONTROL_FILE" ]]; then
        return 1
    fi
    
    # Create temp file with updated status
    local temp_file=$(mktemp)
    
    # Keep header
    head -1 "$CONTROL_FILE" > "$temp_file"
    
    # Process data lines
    tail -n +2 "$CONTROL_FILE" | while IFS=',' read -r fecha ticket proj clust loc ns ksa_name iam_sa status; do
        if [[ "$proj" == "$project" && "$clust" == "$cluster" && "$ns" == "$namespace" && "$ksa_name" == "$ksa" ]]; then
            echo "${fecha},${ticket},${proj},${clust},${loc},${ns},${ksa_name},${iam_sa},${new_status}"
        else
            echo "${fecha},${ticket},${proj},${clust},${loc},${ns},${ksa_name},${iam_sa},${status}"
        fi
    done >> "$temp_file"
    
    mv "$temp_file" "$CONTROL_FILE"
}

# --- Setup log directory (called after ticket input) ---
setup_log_directory() {
    local ticket="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [[ -n "$ticket" ]]; then
        # Create ticket folder structure
        LOG_DIR="$TICKETS_DIR/$ticket/logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/workload_identity_${timestamp}.log"
        
        # Create additional folders for ticket
        mkdir -p "$TICKETS_DIR/$ticket/docs"
        mkdir -p "$TICKETS_DIR/$ticket/scripts"
    else
        # Use default logs folder
        LOG_DIR="$SCRIPT_DIR/logs"
        mkdir -p "$LOG_DIR"
        LOG_FILE="$LOG_DIR/workload_identity_${timestamp}.log"
    fi
}

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local message="$1"
    # Only log if LOG_FILE is set
    [[ -z "$LOG_FILE" ]] && return 0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

log_and_print() {
    local message="$1"
    local color="${2:-$NC}"
    echo -e "${color}${message}${NC}"
    log "$message"
}

print_header() {
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${LGREEN} $1${NC}"
    echo -e "${LGREEN}========================================${NC}"
    log "========================================"
    log " $1"
    log "========================================"
}

print_info() {
    local label="$1"
    local value="$2"
    echo -e "${WHITE}${label}:${NC} ${LCYAN}${value}${NC}"
    log "${label}: ${value}"
}

print_success() {
    echo -e "${LGREEN}✓ $1${NC}"
    log "✓ $1"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    log "✗ $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log "⚠ $1"
}

# =============================================================================
# Input Functions
# =============================================================================

prompt_input() {
    local prompt_text="$1"
    local variable_name="$2"
    local default_value="$3"
    
    if [[ -n "$default_value" ]]; then
        echo -ne "${YELLOW}${prompt_text} [${default_value}]: ${NC}"
    else
        echo -ne "${YELLOW}${prompt_text}: ${NC}"
    fi
    
    read input_value
    
    if [[ -z "$input_value" ]] && [[ -n "$default_value" ]]; then
        input_value="$default_value"
    fi
    
    eval "$variable_name='$input_value'"
    log "Input - ${prompt_text}: ${input_value}"
}

prompt_selection() {
    local prompt_text="$1"
    local options_var="$2"
    local result_var="$3"
    
    local -n options="$options_var"
    local count=${#options[@]}
    
    echo -e "${WHITE}${prompt_text}${NC}"
    echo ""
    
    for i in "${!options[@]}"; do
        echo -e "  ${LCYAN}$((i+1)))${NC} ${options[$i]}"
    done
    
    echo ""
    echo -ne "${YELLOW}Seleccione una opción [1-${count}]: ${NC}"
    read selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
        eval "$result_var='${options[$((selection-1))]}'"
        log "Selection - ${prompt_text}: ${options[$((selection-1))]}"
        return 0
    else
        print_error "Selección inválida"
        return 1
    fi
}

# =============================================================================
# GCP Functions
# =============================================================================

get_current_project() {
    gcloud config get-value project 2>/dev/null
}

list_gke_clusters() {
    local project_id="$1"
    gcloud container clusters list --project "$project_id" --format="value(name,location)" 2>/dev/null
}

connect_to_cluster() {
    local cluster_name="$1"
    local location="$2"
    local project_id="$3"
    
    log "Connecting to cluster: $cluster_name in $location"
    
    # Determine if regional or zonal
    if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
        # Regional (e.g., us-central1)
        if [[ -n "$LOG_FILE" ]]; then
            gcloud container clusters get-credentials "$cluster_name" \
                --region "$location" \
                --project "$project_id" 2>&1 | tee -a "$LOG_FILE"
        else
            gcloud container clusters get-credentials "$cluster_name" \
                --region "$location" \
                --project "$project_id" &>/dev/null
        fi
    else
        # Zonal (e.g., us-central1-a)
        if [[ -n "$LOG_FILE" ]]; then
            gcloud container clusters get-credentials "$cluster_name" \
                --zone "$location" \
                --project "$project_id" 2>&1 | tee -a "$LOG_FILE"
        else
            gcloud container clusters get-credentials "$cluster_name" \
                --zone "$location" \
                --project "$project_id" &>/dev/null
        fi
    fi
}

verify_iam_sa() {
    local sa_email="$1"
    local project_id="$2"
    
    gcloud iam service-accounts describe "$sa_email" --project "$project_id" &>/dev/null
}

create_iam_sa() {
    local sa_name="$1"
    local project_id="$2"
    local display_name="${3:-$sa_name}"
    
    gcloud iam service-accounts create "$sa_name" \
        --project "$project_id" \
        --display-name "$display_name" 2>&1 | tee -a "$LOG_FILE"
}

create_namespace() {
    local namespace="$1"
    
    if kubectl get namespace "$namespace" &>/dev/null; then
        log "Namespace $namespace already exists"
        return 0
    fi
    
    kubectl create namespace "$namespace" 2>&1 | tee -a "$LOG_FILE"
}

create_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        log "KSA $ksa_name already exists in $namespace"
        return 0
    fi
    
    kubectl create serviceaccount "$ksa_name" -n "$namespace" 2>&1 | tee -a "$LOG_FILE"
}

add_iam_binding() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"
    
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    
    gcloud iam service-accounts add-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" \
        --role "roles/iam.workloadIdentityUser" \
        --member "$member" 2>&1 | tee -a "$LOG_FILE"
}

annotate_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    local iam_sa_email="$3"
    
    kubectl annotate serviceaccount "$ksa_name" \
        --namespace "$namespace" \
        "iam.gke.io/gcp-service-account=${iam_sa_email}" \
        --overwrite 2>&1 | tee -a "$LOG_FILE"
}

remove_iam_binding() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"
    
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    
    gcloud iam service-accounts remove-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" \
        --role "roles/iam.workloadIdentityUser" \
        --member "$member" 2>&1 | tee -a "$LOG_FILE"
}

delete_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    kubectl delete serviceaccount "$ksa_name" -n "$namespace" 2>&1 | tee -a "$LOG_FILE"
}

get_ksa_annotation() {
    local ksa_name="$1"
    local namespace="$2"
    
    kubectl get serviceaccount "$ksa_name" -n "$namespace" \
        -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null
}

list_workload_identities() {
    local namespace="$1"
    
    echo -e "${WHITE}Kubernetes Service Accounts con Workload Identity en namespace: ${LCYAN}${namespace}${NC}"
    echo ""
    
    local ksas=$(kubectl get serviceaccounts -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    local found=false
    for ksa in $ksas; do
        local annotation=$(get_ksa_annotation "$ksa" "$namespace")
        if [[ -n "$annotation" ]]; then
            echo -e "  ${LCYAN}$ksa${NC} → ${LGREEN}$annotation${NC}"
            found=true
        fi
    done
    
    if [[ "$found" == "false" ]]; then
        echo -e "  ${GRAY}No se encontraron KSAs con Workload Identity configurado${NC}"
    fi
}

# =============================================================================
# Menu Functions
# =============================================================================

show_main_menu() {
    clear
    echo -e "${LGREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}║${NC}   ${WHITE}Workload Identity Manager${NC}            ${LGREEN}║${NC}"
    echo -e "${LGREEN}╠════════════════════════════════════════╣${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}1)${NC} Configurar Workload Identity       ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}2)${NC} Verificar Configuración            ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}3)${NC} Eliminar Workload Identity         ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}4)${NC} Listar Bindings en Namespace       ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}5)${NC} Ver Registro de Operaciones        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}0)${NC} Salir                               ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${YELLOW}Seleccione una opción: ${NC}"
}

# =============================================================================
# Operation: Setup Workload Identity
# =============================================================================

operation_setup() {
    clear
    print_header "Configurar Workload Identity"
    echo ""
    
    # --- Step 0: Ticket/CTask (Optional) ---
    echo -e "${GRAY}(Opcional) Asociar a un ticket para organizar los logs${NC}"
    prompt_input "Ingrese el número de Ticket o CTask (Enter para omitir)" "TICKET_ID" ""
    
    # Setup log directory based on ticket
    setup_log_directory "$TICKET_ID"
    
    if [[ -n "$TICKET_ID" ]]; then
        echo -e "${LGREEN}✓ Logs se guardarán en: ${LCYAN}Tickets/$TICKET_ID/logs/${NC}"
    fi
    
    echo ""
    log "Session started - Operation: SETUP"
    [[ -n "$TICKET_ID" ]] && log "Ticket/CTask: $TICKET_ID"
    
    # --- Step 1: Project ID ---
    local current_project=$(get_current_project)
    prompt_input "Ingrese el Project ID" "project_id" "$current_project"
    
    if [[ -z "$project_id" ]]; then
        print_error "Project ID es requerido"
        exit 1
    fi
    
    echo ""
    
    # --- Step 2: IAM Service Account ---
    prompt_input "Ingrese el nombre de la cuenta de servicio IAM (sin @...)" "iam_sa_name"
    
    if [[ -z "$iam_sa_name" ]]; then
        print_error "IAM Service Account es requerido"
        exit 1
    fi
    
    # Build full email
    local iam_sa_email="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"
    local iam_sa_exists=true
    
    # Verify IAM SA exists (just check, don't create yet)
    echo ""
    echo -ne "${GRAY}Verificando cuenta IAM...${NC}"
    if verify_iam_sa "$iam_sa_email" "$project_id"; then
        echo -e "\r${LGREEN}✓ Cuenta IAM verificada${NC}     "
        log "IAM SA verified: $iam_sa_email"
    else
        echo -e "\r${YELLOW}⚠ Cuenta IAM no existe (se creará)${NC}     "
        log "IAM SA not found, will be created: $iam_sa_email"
        iam_sa_exists=false
    fi
    
    echo ""
    
    # --- Step 3: Kubernetes Service Account ---
    prompt_input "Ingrese el nombre de la cuenta de servicio de Kubernetes (KSA)" "ksa_name"
    
    if [[ -z "$ksa_name" ]]; then
        print_error "Kubernetes Service Account es requerido"
        exit 1
    fi
    
    echo ""
    
    # --- Step 4: List and Select Cluster ---
    echo -ne "${GRAY}Buscando clusters en el proyecto...${NC}"
    
    local clusters_raw=$(list_gke_clusters "$project_id")
    
    if [[ -z "$clusters_raw" ]]; then
        echo -e "\r${RED}✗ No se encontraron clusters${NC}     "
        print_error "No hay clusters GKE en el proyecto $project_id"
        exit 1
    fi
    
    echo -e "\r${LGREEN}✓ Clusters encontrados${NC}          "
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
    
    # Show selection menu
    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        selected_cluster="${cluster_names[0]}"
        selected_location="${cluster_locations[0]}"
        print_info "Cluster único encontrado" "$selected_cluster ($selected_location)"
    else
        prompt_selection "Seleccione el cluster GKE:" cluster_options selected_option
        
        # Find selected cluster
        for i in "${!cluster_options[@]}"; do
            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                selected_cluster="${cluster_names[$i]}"
                selected_location="${cluster_locations[$i]}"
                break
            fi
        done
    fi
    
    echo ""
    
    # --- Step 5: Connect to Cluster ---
    echo -ne "${GRAY}Conectando al cluster...${NC}"
    
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Conectado al cluster${NC}          "
        log "Connected to cluster: $selected_cluster"
    else
        echo -e "\r${RED}✗ Error al conectar${NC}          "
        print_error "No se pudo conectar al cluster"
        exit 1
    fi
    
    echo ""
    
    # --- Step 6: Namespace Selection ---
    prompt_input "Ingrese el namespace" "namespace" "apps"
    
    echo ""
    
    # --- Confirmation ---
    print_header "Configuración"
    if [[ -n "$TICKET_ID" ]]; then
        print_info "Ticket/CTask" "$TICKET_ID"
    fi
    print_info "Project ID" "$project_id"
    print_info "Cluster" "$selected_cluster"
    print_info "Location" "$selected_location"
    print_info "Namespace" "$namespace"
    print_info "Kubernetes SA" "$ksa_name"
    if [[ "$iam_sa_exists" == "false" ]]; then
        echo -e "${WHITE}IAM SA:${NC} ${YELLOW}${iam_sa_email} (nueva)${NC}"
        log "IAM SA: ${iam_sa_email} (nueva)"
    else
        print_info "IAM SA" "$iam_sa_email"
    fi
    echo -e "${LGREEN}========================================${NC}"
    
    echo ""
    echo -ne "${YELLOW}¿Desea continuar con la configuración? (Y/N): ${NC}"
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Operación cancelada"
        exit 0
    fi
    
    echo ""
    
    # --- Step 7: Execute Configuration ---
    print_header "Ejecutando Configuración"
    echo ""
    
    local step=1
    local total_steps=4
    
    # Create IAM SA if needed
    if [[ "$iam_sa_exists" == "false" ]]; then
        total_steps=5
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creando cuenta IAM..."
        if create_iam_sa "$iam_sa_name" "$project_id" >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creando cuenta IAM... ${LGREEN}✓${NC}"
            log "IAM SA created: $iam_sa_email"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creando cuenta IAM... ${RED}✗${NC}"
            print_error "Error al crear cuenta IAM"
            exit 1
        fi
        ((step++))
    fi
    
    # Create namespace
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creando namespace..."
    if create_namespace "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creando namespace... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creando namespace... ${YELLOW}(existente)${NC}"
    fi
    ((step++))
    
    # Create KSA
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creando Kubernetes SA..."
    if create_ksa "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creando Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creando Kubernetes SA... ${YELLOW}(existente)${NC}"
    fi
    ((step++))
    
    # Add IAM binding
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Agregando IAM binding..."
    if add_iam_binding "$iam_sa_email" "$project_id" "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Agregando IAM binding... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Agregando IAM binding... ${RED}✗${NC}"
        print_error "Error al agregar IAM binding"
    fi
    ((step++))
    
    # Annotate KSA
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Anotando Kubernetes SA..."
    if annotate_ksa "$ksa_name" "$namespace" "$iam_sa_email" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Anotando Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Anotando Kubernetes SA... ${RED}✗${NC}"
        print_error "Error al anotar KSA"
    fi
    
    echo ""
    
    # --- Register in control file ---
    register_execution "$TICKET_ID" "$project_id" "$selected_cluster" "$selected_location" "$namespace" "$ksa_name" "$iam_sa_email"
    
    # --- Final Summary ---
    print_header "Workload Identity Configurado"
    if [[ -n "$TICKET_ID" ]]; then
        print_info "Ticket" "$TICKET_ID"
    fi
    print_info "Project" "$project_id"
    print_info "Cluster" "$selected_cluster"
    print_info "Namespace" "$namespace"
    print_info "Kubernetes SA" "$ksa_name"
    print_info "IAM SA" "$iam_sa_email"
    echo -e "${LGREEN}========================================${NC}"
    
    echo ""
    echo -e "${GRAY}Log guardado en: $LOG_FILE${NC}"
    echo -e "${GRAY}Registro agregado a: $CONTROL_FILE${NC}"
    log "Session completed successfully"
    log "Registered in control file: $CONTROL_FILE"
    
    echo ""
    echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
    read
}

# =============================================================================
# Operation: Verify Workload Identity
# =============================================================================

operation_verify() {
    clear
    print_header "Verificar Workload Identity"
    echo ""
    
    # Setup temporary log
    setup_log_directory ""
    log "Session started - Operation: VERIFY"
    
    # --- Project ID ---
    local current_project=$(get_current_project)
    prompt_input "Ingrese el Project ID" "project_id" "$current_project"
    
    if [[ -z "$project_id" ]]; then
        print_error "Project ID es requerido"
        return 1
    fi
    
    echo ""
    
    # --- List and Select Cluster ---
    echo -ne "${GRAY}Buscando clusters en el proyecto...${NC}"
    
    local clusters_raw=$(list_gke_clusters "$project_id")
    
    if [[ -z "$clusters_raw" ]]; then
        echo -e "\r${RED}✗ No se encontraron clusters${NC}     "
        return 1
    fi
    
    echo -e "\r${LGREEN}✓ Clusters encontrados${NC}          "
    echo ""
    
    declare -a cluster_names
    declare -a cluster_locations
    declare -a cluster_options
    
    while IFS=$'\t' read -r name location; do
        cluster_names+=("$name")
        cluster_locations+=("$location")
        cluster_options+=("$name ($location)")
    done <<< "$clusters_raw"
    
    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        selected_cluster="${cluster_names[0]}"
        selected_location="${cluster_locations[0]}"
    else
        prompt_selection "Seleccione el cluster GKE:" cluster_options selected_option
        for i in "${!cluster_options[@]}"; do
            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                selected_cluster="${cluster_names[$i]}"
                selected_location="${cluster_locations[$i]}"
                break
            fi
        done
    fi
    
    echo ""
    
    # --- Connect to Cluster ---
    echo -ne "${GRAY}Conectando al cluster...${NC}"
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Conectado al cluster${NC}          "
    else
        echo -e "\r${RED}✗ Error al conectar${NC}          "
        return 1
    fi
    
    echo ""
    
    # --- KSA and Namespace ---
    prompt_input "Ingrese el namespace" "namespace" "apps"
    prompt_input "Ingrese el nombre del KSA a verificar" "ksa_name"
    prompt_input "Ingrese el nombre del IAM Service Account (sin @...)" "iam_sa_name" "$ksa_name"
    
    local iam_sa_email="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"
    
    echo ""
    
    # --- Verify ---
    print_header "Resultado de Verificación"
    
    local ksa_exists=false
    local iam_sa_exists=false
    local annotation=""
    
    # Check IAM SA exists
    echo -ne "Verificando IAM SA..."
    if gcloud iam service-accounts describe "$iam_sa_email" --project "$project_id" &>/dev/null; then
        echo -e "\r${LGREEN}✓ IAM SA existe${NC}                 "
        print_info "IAM SA" "$iam_sa_email"
        iam_sa_exists=true
    else
        echo -e "\r${RED}✗ IAM SA no encontrado${NC}          "
    fi
    
    # Check KSA exists
    echo -ne "Verificando KSA..."
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        echo -e "\r${LGREEN}✓ KSA existe${NC}                    "
        ksa_exists=true
    else
        echo -e "\r${RED}✗ KSA no encontrado${NC}             "
    fi
    
    # Check annotation (only if KSA exists)
    if [[ "$ksa_exists" == "true" ]]; then
        annotation=$(get_ksa_annotation "$ksa_name" "$namespace")
        echo -ne "Verificando anotación..."
        if [[ -n "$annotation" ]]; then
            echo -e "\r${LGREEN}✓ Anotación configurada${NC}         "
            print_info "Anotación" "$annotation"
        else
            echo -e "\r${YELLOW}⚠ Sin anotación de Workload Identity${NC}"
        fi
    fi
    
    # Check IAM binding (only if IAM SA exists)
    if [[ "$iam_sa_exists" == "true" ]]; then
        echo -ne "Verificando IAM binding..."
        local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
        if gcloud iam service-accounts get-iam-policy "$iam_sa_email" --project "$project_id" 2>/dev/null | grep -q "$member"; then
            echo -e "\r${LGREEN}✓ IAM binding configurado${NC}       "
        else
            echo -e "\r${YELLOW}⚠ IAM binding no encontrado${NC}     "
        fi
    fi
    
    echo ""
    
    # Summary
    print_header "Resumen"
    echo ""
    echo -e "  IAM Service Account: $([ "$iam_sa_exists" == "true" ] && echo "${LGREEN}Existe${NC}" || echo "${RED}No existe${NC}")"
    echo -e "  Kubernetes SA:       $([ "$ksa_exists" == "true" ] && echo "${LGREEN}Existe${NC}" || echo "${RED}No existe${NC}")"
    if [[ "$ksa_exists" == "true" ]]; then
        echo -e "  Anotación WI:        $([ -n "$annotation" ] && echo "${LGREEN}Configurada${NC}" || echo "${YELLOW}No configurada${NC}")"
    fi
    echo ""
    print_header "Verificación Completada"
    
    echo ""
    echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
    read
}

# =============================================================================
# Operation: Cleanup Workload Identity
# =============================================================================

operation_cleanup() {
    clear
    print_header "Eliminar Workload Identity"
    echo ""
    
    # Setup temporary log
    setup_log_directory ""
    log "Session started - Operation: CLEANUP"
    
    # --- Check if registry has active records ---
    local project_id=""
    local selected_cluster=""
    local selected_location=""
    local namespace=""
    local ksa_name=""
    local annotation=""
    
    if [[ -f "$CONTROL_FILE" ]]; then
        # Get active records from CSV
        local active_records=$(tail -n +2 "$CONTROL_FILE" | awk -F',' '$9 == "activo"')
        
        if [[ -n "$active_records" ]]; then
            echo -e "${WHITE}Configuraciones activas en el registro:${NC}"
            echo ""
            
            declare -a record_options
            declare -a record_projects
            declare -a record_clusters
            declare -a record_locations
            declare -a record_namespaces
            declare -a record_ksas
            declare -a record_iam_sas
            local idx=1
            
            while IFS=',' read -r fecha ticket proj clust loc ns ksa iam_sa status; do
                record_options+=("$proj | $clust | $ns | $ksa")
                record_projects+=("$proj")
                record_clusters+=("$clust")
                record_locations+=("$loc")
                record_namespaces+=("$ns")
                record_ksas+=("$ksa")
                record_iam_sas+=("$iam_sa")
                echo -e "  ${LCYAN}${idx})${NC} ${WHITE}$proj${NC} | ${YELLOW}$clust${NC} | ${LCYAN}$ns${NC} | ${LGREEN}$ksa${NC}"
                ((idx++))
            done <<< "$active_records"
            
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Eliminar configuración manualmente${NC}"
            echo ""
            
            local max_opt=${#record_options[@]}
            ((max_opt++))
            
            echo -ne "${WHITE}Seleccione una opción [1-${max_opt}]:${NC} "
            read selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_opt" ]]; then
                if [[ "$selection" -eq "$max_opt" ]]; then
                    # Manual selection - continue with normal flow
                    :
                else
                    # Use selected record
                    local sel_idx=$((selection-1))
                    project_id="${record_projects[$sel_idx]}"
                    selected_cluster="${record_clusters[$sel_idx]}"
                    selected_location="${record_locations[$sel_idx]}"
                    namespace="${record_namespaces[$sel_idx]}"
                    ksa_name="${record_ksas[$sel_idx]}"
                    annotation="${record_iam_sas[$sel_idx]}"
                    
                    echo ""
                    echo -e "${LGREEN}✓ Seleccionado:${NC} ${WHITE}$ksa_name${NC} en ${LCYAN}$namespace${NC}"
                    
                    # Connect to cluster
                    echo ""
                    echo -ne "${GRAY}Conectando al cluster...${NC}"
                    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
                        echo -e "\r${LGREEN}✓ Conectado al cluster${NC}          "
                    else
                        echo -e "\r${RED}✗ Error al conectar${NC}          "
                        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
                        read
                        return 1
                    fi
                fi
            else
                echo -e "${RED}Opción inválida${NC}"
                echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
                read
                return 1
            fi
        fi
    fi
    
    # --- Manual selection if not selected from registry ---
    if [[ -z "$project_id" ]]; then
        local current_project=$(get_current_project)
        prompt_input "Ingrese el Project ID" "project_id" "$current_project"
        
        echo ""
        
        # --- List and Select Cluster ---
        echo -ne "${GRAY}Buscando clusters en el proyecto...${NC}"
        
        local clusters_raw=$(list_gke_clusters "$project_id")
        
        if [[ -z "$clusters_raw" ]]; then
            echo -e "\r${RED}✗ No se encontraron clusters${NC}     "
            return 1
        fi
        
        echo -e "\r${LGREEN}✓ Clusters encontrados${NC}          "
        echo ""
        
        declare -a cluster_names
        declare -a cluster_locations
        declare -a cluster_options
        
        while IFS=$'\t' read -r name location; do
            cluster_names+=("$name")
            cluster_locations+=("$location")
            cluster_options+=("$name ($location)")
        done <<< "$clusters_raw"
        
        if [[ ${#cluster_options[@]} -eq 1 ]]; then
            selected_cluster="${cluster_names[0]}"
            selected_location="${cluster_locations[0]}"
        else
            prompt_selection "Seleccione el cluster GKE:" cluster_options selected_option
            for i in "${!cluster_options[@]}"; do
                if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                    selected_cluster="${cluster_names[$i]}"
                    selected_location="${cluster_locations[$i]}"
                    break
                fi
            done
        fi
        
        echo ""
        
        # --- Connect to Cluster ---
        echo -ne "${GRAY}Conectando al cluster...${NC}"
        if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
            echo -e "\r${LGREEN}✓ Conectado al cluster${NC}          "
        else
            echo -e "\r${RED}✗ Error al conectar${NC}          "
            return 1
        fi
        
        echo ""
        
        # --- KSA and Namespace ---
        prompt_input "Ingrese el namespace" "namespace" "apps"
        prompt_input "Ingrese el nombre del KSA a eliminar" "ksa_name"
        
        # Get current annotation
        annotation=$(get_ksa_annotation "$ksa_name" "$namespace")
    fi
    
    if [[ -z "$annotation" ]]; then
        print_warning "El KSA no tiene Workload Identity configurado"
        echo ""
        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
        read
        return 0
    fi
    
    echo ""
    
    # --- Confirmation ---
    print_header "Configuración a Eliminar"
    print_info "Project" "$project_id"
    print_info "Cluster" "$selected_cluster"
    print_info "Namespace" "$namespace"
    print_info "KSA" "$ksa_name"
    print_info "IAM SA" "$annotation"
    echo -e "${LGREEN}========================================${NC}"
    
    echo ""
    echo -e "${WHITE}¿Qué desea eliminar?${NC}"
    echo -e "  ${LCYAN}1)${NC} Solo el binding (mantener KSA e IAM SA)"
    echo -e "  ${LCYAN}2)${NC} Binding + KSA (mantener IAM SA)"
    echo -e "  ${LCYAN}3)${NC} Todo (Binding + KSA + IAM SA)"
    echo -e "  ${LCYAN}0)${NC} Cancelar"
    echo ""
    echo -ne "${YELLOW}Seleccione una opción: ${NC}"
    read cleanup_option
    
    if [[ "$cleanup_option" == "0" ]]; then
        print_warning "Operación cancelada"
        echo ""
        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
        read
        return 0
    fi
    
    if [[ ! "$cleanup_option" =~ ^[1-3]$ ]]; then
        print_error "Opción inválida"
        echo ""
        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
        read
        return 0
    fi
    
    echo ""
    echo -e "${RED}⚠ Esta acción no se puede deshacer${NC}"
    echo -ne "${YELLOW}¿Está seguro? (Y/N): ${NC}"
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Operación cancelada"
        echo ""
        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
        read
        return 0
    fi
    
    echo ""
    
    # --- Execute Cleanup ---
    print_header "Ejecutando Limpieza"
    echo ""
    
    local total_steps=2
    [[ "$cleanup_option" == "2" ]] && total_steps=3
    [[ "$cleanup_option" == "3" ]] && total_steps=4
    local step=1
    
    # Step 1: Remove IAM binding
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Eliminando IAM binding..."
    if remove_iam_binding "$annotation" "$project_id" "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando IAM binding... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando IAM binding... ${YELLOW}(puede no existir)${NC}"
    fi
    ((step++))
    
    # Step 2: Remove annotation
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Eliminando anotación del KSA..."
    if kubectl annotate serviceaccount "$ksa_name" -n "$namespace" "iam.gke.io/gcp-service-account-" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando anotación del KSA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando anotación del KSA... ${YELLOW}(puede no existir)${NC}"
    fi
    ((step++))
    
    # Step 3: Delete KSA (if option 2 or 3)
    if [[ "$cleanup_option" =~ ^[23]$ ]]; then
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Eliminando KSA..."
        if delete_ksa "$ksa_name" "$namespace" >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando KSA... ${LGREEN}✓${NC}"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando KSA... ${RED}✗${NC}"
        fi
        ((step++))
    fi
    
    # Step 4: Delete IAM SA (if option 3)
    if [[ "$cleanup_option" == "3" ]]; then
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Eliminando cuenta IAM..."
        if gcloud iam service-accounts delete "$annotation" --project "$project_id" --quiet >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando cuenta IAM... ${LGREEN}✓${NC}"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Eliminando cuenta IAM... ${RED}✗${NC}"
        fi
    fi
    
    echo ""
    
    # --- Update registry status ---
    local status_text=""
    case "$cleanup_option" in
        1) status_text="eliminado-binding" ;;
        2) status_text="eliminado-binding-ksa" ;;
        3) status_text="eliminado-todo" ;;
    esac
    
    # Get cluster info from current context
    local current_context=$(kubectl config current-context 2>/dev/null)
    local current_cluster=$(echo "$current_context" | grep -oP 'gke_[^_]+_[^_]+_\K[^_]+')
    
    if update_registry_status "$project_id" "$current_cluster" "$namespace" "$ksa_name" "$status_text"; then
        echo -e "${GRAY}Registro actualizado con estado: ${status_text}${NC}"
    fi
    
    print_header "Limpieza Completada"
    log "Cleanup completed for $ksa_name in $namespace - Status: $status_text"
    
    echo ""
    echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
    read
}

# =============================================================================
# Operation: List Workload Identities
# =============================================================================

operation_list() {
    clear
    print_header "Listar Workload Identities"
    echo ""
    
    # --- Project Selection from Registry or Manual ---
    local project_id=""
    local current_project=$(get_current_project)
    
    # Check if registry has projects (only active ones)
    if [[ -f "$CONTROL_FILE" ]]; then
        # Get unique projects from CSV (column 3) - only active records (Status = activo)
        local registry_projects=$(tail -n +2 "$CONTROL_FILE" | awk -F',' '$9 == "activo" {print $3}' | sort -u | grep -v '^$')
        
        if [[ -n "$registry_projects" ]]; then
            echo -e "${WHITE}Proyectos en el registro:${NC}"
            echo ""
            
            declare -a project_options
            local idx=1
            
            while IFS= read -r proj; do
                project_options+=("$proj")
                echo -e "  ${LCYAN}${idx})${NC} $proj"
                ((idx++))
            done <<< "$registry_projects"
            
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Ingresar otro proyecto manualmente${NC}"
            echo ""
            
            local max_opt=${#project_options[@]}
            ((max_opt++))
            
            echo -ne "${WHITE}Seleccione una opción [1-${max_opt}]:${NC} "
            read selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_opt" ]]; then
                if [[ "$selection" -eq "$max_opt" ]]; then
                    # Manual input
                    prompt_input "Ingrese el Project ID" "project_id" "$current_project"
                else
                    project_id="${project_options[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Proyecto seleccionado:${NC} ${WHITE}$project_id${NC}"
                fi
            else
                echo -e "${RED}Opción inválida${NC}"
                echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
                read
                return 1
            fi
        else
            prompt_input "Ingrese el Project ID" "project_id" "$current_project"
        fi
    else
        prompt_input "Ingrese el Project ID" "project_id" "$current_project"
    fi
    
    echo ""
    
    # --- Cluster Selection from Registry or GCP ---
    local selected_cluster=""
    local selected_location=""
    
    # Check if registry has clusters for this project
    if [[ -f "$CONTROL_FILE" ]]; then
        # Get unique clusters for this project (columns 4=cluster, 5=location) - only active records
        local registry_clusters=$(tail -n +2 "$CONTROL_FILE" | awk -F',' -v proj="$project_id" '$3 == proj && $9 == "activo" {print $4 "," $5}' | sort -u | grep -v '^,$')
        
        if [[ -n "$registry_clusters" ]]; then
            echo -e "${WHITE}Clusters en el registro para ${LCYAN}$project_id${NC}:${NC}"
            echo ""
            
            declare -a reg_cluster_names
            declare -a reg_cluster_locations
            local idx=1
            
            while IFS=',' read -r cluster_name cluster_location; do
                reg_cluster_names+=("$cluster_name")
                reg_cluster_locations+=("$cluster_location")
                echo -e "  ${LCYAN}${idx})${NC} $cluster_name (${cluster_location})"
                ((idx++))
            done <<< "$registry_clusters"
            
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Buscar otros clusters en GCP${NC}"
            echo ""
            
            local max_opt=${#reg_cluster_names[@]}
            ((max_opt++))
            
            echo -ne "${WHITE}Seleccione una opción [1-${max_opt}]:${NC} "
            read selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_opt" ]]; then
                if [[ "$selection" -eq "$max_opt" ]]; then
                    # Search clusters in GCP
                    echo ""
                    echo -ne "${GRAY}Buscando clusters en el proyecto...${NC}"
                    
                    local clusters_raw=$(list_gke_clusters "$project_id")
                    
                    if [[ -z "$clusters_raw" ]]; then
                        echo -e "\r${RED}✗ No se encontraron clusters${NC}     "
                        echo ""
                        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
                        read
                        return 1
                    fi
                    
                    echo -e "\r${LGREEN}✓ Clusters encontrados${NC}          "
                    echo ""
                    
                    declare -a cluster_names
                    declare -a cluster_locations
                    declare -a cluster_options
                    
                    while IFS=$'\t' read -r name location; do
                        cluster_names+=("$name")
                        cluster_locations+=("$location")
                        cluster_options+=("$name ($location)")
                    done <<< "$clusters_raw"
                    
                    if [[ ${#cluster_options[@]} -eq 1 ]]; then
                        selected_cluster="${cluster_names[0]}"
                        selected_location="${cluster_locations[0]}"
                    else
                        prompt_selection "Seleccione el cluster GKE:" cluster_options selected_option
                        for i in "${!cluster_options[@]}"; do
                            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                                selected_cluster="${cluster_names[$i]}"
                                selected_location="${cluster_locations[$i]}"
                                break
                            fi
                        done
                    fi
                else
                    selected_cluster="${reg_cluster_names[$((selection-1))]}"
                    selected_location="${reg_cluster_locations[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Cluster seleccionado:${NC} ${WHITE}$selected_cluster${NC}"
                fi
            else
                echo -e "${RED}Opción inválida${NC}"
                echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
                read
                return 1
            fi
        fi
    fi
    
    # If no cluster selected from registry, search in GCP
    if [[ -z "$selected_cluster" ]]; then
        echo -ne "${GRAY}Buscando clusters en el proyecto...${NC}"
        
        local clusters_raw=$(list_gke_clusters "$project_id")
        
        if [[ -z "$clusters_raw" ]]; then
            echo -e "\r${RED}✗ No se encontraron clusters${NC}     "
            echo ""
            echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
            read
            return 1
        fi
        
        echo -e "\r${LGREEN}✓ Clusters encontrados${NC}          "
        echo ""
        
        declare -a cluster_names
        declare -a cluster_locations
        declare -a cluster_options
        
        while IFS=$'\t' read -r name location; do
            cluster_names+=("$name")
            cluster_locations+=("$location")
            cluster_options+=("$name ($location)")
        done <<< "$clusters_raw"
        
        if [[ ${#cluster_options[@]} -eq 1 ]]; then
            selected_cluster="${cluster_names[0]}"
            selected_location="${cluster_locations[0]}"
        else
            prompt_selection "Seleccione el cluster GKE:" cluster_options selected_option
            for i in "${!cluster_options[@]}"; do
                if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                    selected_cluster="${cluster_names[$i]}"
                    selected_location="${cluster_locations[$i]}"
                    break
                fi
            done
        fi
    fi
    
    echo ""
    
    # --- Connect to Cluster ---
    echo -ne "${GRAY}Conectando al cluster...${NC}"
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Conectado al cluster${NC}          "
    else
        echo -e "\r${RED}✗ Error al conectar${NC}          "
        echo ""
        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
        read
        return 1
    fi
    
    echo ""
    
    # --- Namespace ---
    prompt_input "Ingrese el namespace (o 'all' para todos)" "namespace" "apps"
    
    echo ""
    print_header "Workload Identities Configurados"
    echo ""
    
    if [[ "$namespace" == "all" ]]; then
        local namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        for ns in $namespaces; do
            list_workload_identities "$ns"
            echo ""
        done
    else
        list_workload_identities "$namespace"
    fi
    
    echo ""
    echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
    read
}

# =============================================================================
# Operation: View Registry
# =============================================================================

operation_view_registry() {
    clear
    print_header "Registro de Operaciones"
    echo ""
    
    if [[ ! -f "$CONTROL_FILE" ]]; then
        print_warning "No hay registros disponibles"
        echo ""
        echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
        read
        return 0
    fi
    
    # Count records
    local total=$(($(wc -l < "$CONTROL_FILE") - 1))
    local activos=$(tail -n +2 "$CONTROL_FILE" | awk -F',' '$9 == "activo"' | wc -l)
    local eliminados=$((total - activos))
    echo -e "${WHITE}Total de registros:${NC} ${LCYAN}${total}${NC} (${LGREEN}${activos} activos${NC}, ${RED}${eliminados} eliminados${NC})"
    echo ""
    
    # Show last 20 records
    echo -e "${WHITE}Últimos registros:${NC}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    # Header
    echo -e "${WHITE}Fecha               | Ticket     | Project          | Namespace | KSA              | Status${NC}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    # Data (skip header, show last 15)
    tail -n +2 "$CONTROL_FILE" | tail -15 | while IFS=',' read -r fecha ticket project cluster location namespace ksa iam_sa status; do
        local status_color="${LGREEN}"
        [[ "$status" =~ ^eliminado ]] && status_color="${RED}"
        printf "${LCYAN}%-19s${NC} | ${YELLOW}%-10s${NC} | ${WHITE}%-16s${NC} | ${LCYAN}%-9s${NC} | ${LGREEN}%-16s${NC} | ${status_color}%s${NC}\n" \
            "$fecha" "$ticket" "$project" "$namespace" "$ksa" "$status"
    done
    
    echo -e "${GRAY}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${GRAY}Archivo: $CONTROL_FILE${NC}"
    
    echo ""
    echo -ne "${YELLOW}Presione Enter para continuar...${NC}"
    read
}

# =============================================================================
# Main Menu Loop
# =============================================================================

main() {
    while true; do
        show_main_menu
        read option
        
        case $option in
            1) operation_setup ;;
            2) operation_verify ;;
            3) operation_cleanup ;;
            4) operation_list ;;
            5) operation_view_registry ;;
            0) 
                clear
                echo -e "${LGREEN}¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opción inválida${NC}"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

# Check dependencies
for cmd in gcloud kubectl; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}Error: $cmd no está instalado${NC}"
        exit 1
    fi
done

# Initialize control file
init_control_file

main "$@"
