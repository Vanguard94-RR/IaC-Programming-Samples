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
        echo "Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA" > "$CONTROL_FILE"
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Use "-" if no ticket
    [[ -z "$ticket" ]] && ticket="-"
    
    echo "${timestamp},${ticket},${project},${cluster},${location},${namespace},${ksa},${iam_sa}" >> "$CONTROL_FILE"
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
        gcloud container clusters get-credentials "$cluster_name" \
            --region "$location" \
            --project "$project_id" 2>&1 | tee -a "$LOG_FILE"
    else
        # Zonal (e.g., us-central1-a)
        gcloud container clusters get-credentials "$cluster_name" \
            --zone "$location" \
            --project "$project_id" 2>&1 | tee -a "$LOG_FILE"
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

# =============================================================================
# Main Flow
# =============================================================================

main() {
    clear
    print_header "Workload Identity Manager"
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
    log "Session started"
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
