#!/bin/bash
# File name      : validators.sh
# Description    : Funciones de validación para Shared VPC Subnet
# Author         : Erick Alvarado
# Date           : 20251113
# Version        : 1.0.0
# Usage          : source lib/validators.sh
# Bash_version   : 5.1.16(1)-release

# --- Función: Validar Región GCP ---
function validate_region() {
    local region="$1"
    local project_id="$2"
    
    print_info "Validando región: $region"
    
    local valid_regions=$(gcloud compute regions list --project="$project_id" --format="value(name)" 2>/dev/null)
    
    if echo "$valid_regions" | grep -q "^${region}$"; then
        print_success "Región válida: $region"
        return 0
    else
        print_error "Región inválida: $region"
        echo -e "${YELLOW}Regiones disponibles:${NC}"
        echo "$valid_regions" | head -10
        return 1
    fi
}

# --- Función: Validar Rango IP no se superpone ---
function check_ip_overlap() {
    local project_id="$1"
    local vpc_name="$2"
    local new_cidr="$3"
    
    print_info "Verificando superposición de rangos IP..."
    
    # Obtener todas las subnets existentes en la VPC
    local existing_subnets=$(gcloud compute networks subnets list \
        --network="$vpc_name" \
        --project="$project_id" \
        --format="table[no-heading](name,region,ipCidrRange)" 2>/dev/null)
    
    if [[ -z "$existing_subnets" ]]; then
        print_info "No hay subnets existentes en la VPC"
        return 0
    fi
    
    # Mostrar subnets existentes
    echo -e "\n${YELLOW}Subnets existentes en $vpc_name:${NC}"
    echo "$existing_subnets"
    
    print_warning "Verificar manualmente que el rango $new_cidr no se superponga"
    ask "¿El rango IP $new_cidr NO se superpone con las subnets existentes?"
    
    return 0
}

# --- Función: Validar Formato de Nombre ---
function validate_name() {
    local name="$1"
    local type="${2:-subnet}"
    
    # GCP naming rules: lowercase, numbers, hyphens, 1-63 chars
    if [[ ! $name =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
        print_error "Nombre inválido para $type: $name"
        print_info "Reglas: minúsculas, números, guiones, 1-63 caracteres, debe empezar con letra"
        return 1
    fi
    
    return 0
}

# --- Función: Validar Permisos en Host Project ---
function validate_host_project_permissions() {
    local project_id="$1"
    
    print_info "Validando permisos en Host Project..."
    
    # Obtener la cuenta actual
    local current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
    
    if [[ -z "$current_account" ]]; then
        print_error "No se pudo determinar la cuenta activa"
        return 1
    fi
    
    print_info "Cuenta activa: $current_account"
    
    # Verificar permisos para crear subnets
    local required_permissions=(
        "compute.networks.get"
        "compute.subnetworks.create"
        "compute.subnetworks.get"
    )
    
    local has_permissions=true
    
    for permission in "${required_permissions[@]}"; do
        if gcloud projects get-iam-policy "$project_id" \
            --flatten="bindings[].members" \
            --filter="bindings.members:user:$current_account OR bindings.members:serviceAccount:$current_account" \
            --format="value(bindings.role)" 2>/dev/null | grep -q "compute"; then
            continue
        else
            print_warning "No se pudo verificar el permiso: $permission"
            has_permissions=false
        fi
    done
    
    if [[ "$has_permissions" == "false" ]]; then
        print_warning "No se pudieron verificar todos los permisos necesarios"
        print_info "Permisos requeridos: roles/compute.networkAdmin o roles/compute.securityAdmin"
        ask "¿Continuar de todas formas?"
    else
        print_success "Permisos validados correctamente"
    fi
    
    return 0
}

# --- Función: Validar que es Shared VPC ---
function validate_shared_vpc() {
    local project_id="$1"
    
    print_info "Verificando si el proyecto es Host de Shared VPC..."
    
    local xpn_hosts=$(gcloud compute shared-vpc get-host-project "$project_id" 2>/dev/null)
    
    if [[ -n "$xpn_hosts" ]]; then
        print_success "Proyecto es Host de Shared VPC: $project_id"
        return 0
    else
        print_warning "El proyecto no parece ser Host de Shared VPC"
        print_info "Nota: La subnet se creará de todas formas en el proyecto especificado"
        ask "¿Continuar?"
        return 0
    fi
}

# --- Función: Validar Rangos Secundarios ---
function validate_secondary_ranges() {
    local pod_range="$1"
    local service_range="$2"
    
    if [[ -n "$pod_range" ]] && ! validate_cidr "$pod_range"; then
        print_error "Rango de Pods inválido: $pod_range"
        return 1
    fi
    
    if [[ -n "$service_range" ]] && ! validate_cidr "$service_range"; then
        print_error "Rango de Services inválido: $service_range"
        return 1
    fi
    
    if [[ -n "$pod_range" && -n "$service_range" ]]; then
        print_success "Rangos secundarios validados"
    fi
    
    return 0
}

# --- Función: Verificar Cuota de Subnets ---
function check_subnet_quota() {
    local project_id="$1"
    local region="$2"
    
    print_info "Verificando cuotas de subnets..."
    
    local subnet_count=$(gcloud compute networks subnets list \
        --project="$project_id" \
        --filter="region:$region" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    print_info "Subnets existentes en región $region: $subnet_count"
    
    # Advertencia si hay muchas subnets (límite típico es 700 por VPC)
    if [[ $subnet_count -gt 600 ]]; then
        print_warning "Alto número de subnets en la región. Verificar cuotas."
    fi
    
    return 0
}

# --- Función: Validar Private Google Access ---
function validate_private_google_access() {
    local choice="$1"
    
    case "$choice" in
        [Yy]|yes|YES|true|TRUE)
            return 0
            ;;
        [Nn]|no|NO|false|FALSE)
            return 0
            ;;
        *)
            print_error "Valor inválido para Private Google Access: $choice"
            return 1
            ;;
    esac
}

# --- Función: Validar Flow Logs ---
function validate_flow_logs() {
    local choice="$1"
    
    case "$choice" in
        [Yy]|yes|YES|true|TRUE)
            return 0
            ;;
        [Nn]|no|NO|false|FALSE)
            return 0
            ;;
        *)
            print_error "Valor inválido para Flow Logs: $choice"
            return 1
            ;;
    esac
}

# --- Función: Pre-flight Check Completo ---
function preflight_check() {
    local project_id="$1"
    local vpc_name="$2"
    local region="$3"
    local subnet_name="$4"
    local ip_range="$5"
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}              VERIFICACIÓN PRE-VUELO (PRE-FLIGHT)          ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
    
    local checks_passed=0
    local checks_total=0
    
    # Check 1: Validar proyecto
    ((checks_total++))
    if validate_gcp_project "$project_id"; then
        ((checks_passed++))
    fi
    
    # Check 2: Validar VPC
    ((checks_total++))
    if validate_vpc "$project_id" "$vpc_name"; then
        ((checks_passed++))
    fi
    
    # Check 3: Validar región
    ((checks_total++))
    if validate_region "$region" "$project_id"; then
        ((checks_passed++))
    fi
    
    # Check 4: Validar nombre de subnet
    ((checks_total++))
    if validate_name "$subnet_name" "subnet"; then
        ((checks_passed++))
    fi
    
    # Check 5: Validar CIDR
    ((checks_total++))
    if validate_cidr "$ip_range"; then
        ((checks_passed++))
    fi
    
    # Check 6: Verificar que subnet no exista
    ((checks_total++))
    if subnet_exists "$project_id" "$region" "$subnet_name"; then
        print_error "La subnet '$subnet_name' ya existe en región $region"
    else
        print_success "Nombre de subnet disponible"
        ((checks_passed++))
    fi
    
    # Check 7: Verificar superposición de IPs
    ((checks_total++))
    if check_ip_overlap "$project_id" "$vpc_name" "$ip_range"; then
        ((checks_passed++))
    fi
    
    echo -e "\n${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo -e "${WHITE}Resultado: ${LCYAN}$checks_passed${NC}/${LCYAN}$checks_total${NC} verificaciones exitosas${NC}"
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}\n"
    
    if [[ $checks_passed -eq $checks_total ]]; then
        print_success "Todas las verificaciones pasaron correctamente"
        return 0
    else
        print_warning "Algunas verificaciones fallaron. Revisar antes de continuar."
        ask "¿Desea continuar de todas formas?"
        return 0
    fi
}
