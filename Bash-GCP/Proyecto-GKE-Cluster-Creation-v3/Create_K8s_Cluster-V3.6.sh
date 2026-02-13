#!/bin/bash
# File name      : Create_K8s_Cluster.sh  
# Description    : Script to create a Kubernetes Cluster in a specified project
# Author         : Erick Alvarado
# Date           : 20250918
# Version        : v3.6.0-dynamic-ranges (Detección dinámica de rangos secundarios)
# Usage          : ./Create_K8s_Cluster.sh
# Bash_version   : 5.1.16(1)-release
# Dependencies   : gcloud, kubectl, jq

# --- Declaraciones de Colores ---
LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[0;31m'
NC='\033[0m'

# --- Declaración de Variables Globales ---
project_id=""
cluster_name=""
region=""
zone=""
machine_type=""
num_nodes=""
channel=""
private_nodes=""
control_plane_ip=""
cluster_scope=""
fleet_option=""
VPC_NAME=""
SUBNET_NAME=""
SHARED_HOST=""
IS_SHARED_VPC="false"
PODS_RANGE_NAME=""
SERVICES_RANGE_NAME=""
cluster_access_scope=""
fleet_id=""
cluster_version=""

# --- Funciones de Utilidad ---
function ask() {
    echo -ne "${YELLOW}¿Desea continuar? (Y/N): ${NC}"
    read confirm && [[ $confirm =~ ^[Yy]$ ]] || exit 1
}

function prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local variable_name="$3"
    echo -ne "${WHITE}>> ${prompt_text} (Por defecto: ${LCYAN}${default_value}${NC}): "
    read input_value
    eval "$variable_name=${input_value:-$default_value}"
}

function get_cluster_versions() {
    local target_region="${1:-us-central1}"
    local target_channel="${2:-regular}"
    
    echo "[VERSIONS] Obteniendo versiones disponibles de GKE para región: $target_region" >&2
    
    # Obtener configuración del servidor de la región
    local server_config
    server_config=$(gcloud container get-server-config \
        --region="$target_region" \
        --format="json" 2>/dev/null)
    
    if [[ -z "$server_config" ]]; then
        echo -e "${RED}[ERROR] No se pudo obtener configuración del servidor GKE${NC}" >&2
        return 1
    fi
    
    # Obtener versión recomendada para el canal especificado
    local channel_version
    case "$target_channel" in
        rapid)
            channel_version=$(echo "$server_config" | jq -r '.channels[] | select(.channel=="RAPID") | .validVersions[0]')
            ;;
        regular)
            channel_version=$(echo "$server_config" | jq -r '.channels[] | select(.channel=="REGULAR") | .validVersions[0]')
            ;;
        stable)
            channel_version=$(echo "$server_config" | jq -r '.channels[] | select(.channel=="STABLE") | .validVersions[0]')
            ;;
        *)
            echo -e "${RED}[ERROR] Canal inválido: $target_channel${NC}" >&2
            return 1
            ;;
    esac
    
    if [[ -z "$channel_version" ]]; then
        echo -e "${RED}[ERROR] No se pudo obtener versión para el canal: $target_channel${NC}" >&2
        return 1
    fi
    
    echo -e "${LGREEN}[✓] Versión detectada para canal $target_channel: ${LCYAN}${channel_version}${NC}" >&2
    echo "$channel_version"
    return 0
}

function deploy_twistlock() {
    local daemonset_file="./daemonset.yaml"
    local twistlock_namespace="twistlock"
    local max_retries=3
    local retry_delay=10
    
    echo "[TWISTLOCK] Iniciando despliegue de Twistlock DaemonSet..."
    
    # Validar archivo de configuración
    if [[ ! -f "$daemonset_file" ]]; then
        echo -e "${RED}[ERROR] Archivo $daemonset_file no encontrado${NC}"
        echo -e "${YELLOW}[!] Despliegue de Twistlock omitido${NC}"
        return 1
    fi
    
    echo "[TWISTLOCK] Archivo de configuración encontrado: $daemonset_file"
    
    # Verificar credenciales del cluster
    echo "[TWISTLOCK] Verificando credenciales del cluster..."
    if ! gcloud container clusters get-credentials "$cluster_name" \
        --region "$region" \
        --project "$project_id" \
        --quiet 2>/dev/null; then
        echo -e "${RED}[ERROR] No se pudieron obtener credenciales del cluster${NC}"
        return 1
    fi
    
    # Verificar conectividad con el cluster
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}[ERROR] No se puede conectar al cluster${NC}"
        return 1
    fi
    
    echo "[TWISTLOCK] Conexión al cluster verificada"
    
    # Verificar si el namespace existe en el daemonset.yaml
    local detected_namespace=$(grep -E "^\s*namespace:" "$daemonset_file" | head -1 | awk '{print $2}')
    if [[ -n "$detected_namespace" ]]; then
        twistlock_namespace="$detected_namespace"
        echo "[TWISTLOCK] Namespace detectado en archivo: $twistlock_namespace"
    fi
    
    # Crear namespace si no existe
    if ! kubectl get namespace "$twistlock_namespace" &>/dev/null; then
        echo "[TWISTLOCK] Creando namespace: $twistlock_namespace"
        if ! kubectl create namespace "$twistlock_namespace" 2>/dev/null; then
            echo -e "${YELLOW}[!] No se pudo crear namespace, posiblemente ya existe${NC}"
        fi
    else
        echo "[TWISTLOCK] Namespace ya existe: $twistlock_namespace"
    fi
    
    # Verificar si Twistlock ya está desplegado
    local existing_daemonset=$(kubectl get daemonset -n "$twistlock_namespace" 2>/dev/null | grep -i twistlock | awk '{print $1}' | head -1)
    if [[ -n "$existing_daemonset" ]]; then
        echo -e "${YELLOW}[!] Twistlock DaemonSet ya existe: $existing_daemonset${NC}"
        echo -ne "${YELLOW}>> ¿Desea actualizar el despliegue existente? (Y/N): ${NC}"
        read update_confirm
        if [[ ! $update_confirm =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}[!] Actualización de Twistlock omitida${NC}"
            return 0
        fi
    fi
    
    # Aplicar configuración de Twistlock con reintentos
    local attempt=1
    local apply_success=false
    
    while [[ $attempt -le $max_retries ]]; do
        echo "[TWISTLOCK] Intento $attempt de $max_retries: Aplicando $daemonset_file"
        
        if kubectl apply -f "$daemonset_file" 2>&1; then
            apply_success=true
            echo "[TWISTLOCK] Configuración aplicada exitosamente"
            break
        else
            echo -e "${YELLOW}[!] Intento $attempt falló${NC}"
            if [[ $attempt -lt $max_retries ]]; then
                echo "[TWISTLOCK] Esperando ${retry_delay}s antes de reintentar..."
                sleep "$retry_delay"
            fi
            ((attempt++))
        fi
    done
    
    if [[ "$apply_success" != true ]]; then
        echo -e "${RED}[ERROR] No se pudo aplicar la configuración de Twistlock después de $max_retries intentos${NC}"
        return 1
    fi
    
    # Verificar despliegue del DaemonSet
    echo "[TWISTLOCK] Verificando estado del DaemonSet..."
    sleep 5
    
    local daemonset_name=$(kubectl get daemonset -n "$twistlock_namespace" 2>/dev/null | grep -i twistlock | awk '{print $1}' | head -1)
    
    if [[ -z "$daemonset_name" ]]; then
        echo -e "${RED}[ERROR] No se encontró DaemonSet de Twistlock después del despliegue${NC}"
        return 1
    fi
    
    echo "[TWISTLOCK] DaemonSet encontrado: $daemonset_name"
    
    # Esperar a que los pods estén listos (timeout de 120 segundos)
    echo "[TWISTLOCK] Esperando a que los pods estén listos..."
    local timeout=120
    local elapsed=0
    local check_interval=10
    
    while [[ $elapsed -lt $timeout ]]; do
        local desired=$(kubectl get daemonset "$daemonset_name" -n "$twistlock_namespace" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
        local ready=$(kubectl get daemonset "$daemonset_name" -n "$twistlock_namespace" -o jsonpath='{.status.numberReady}' 2>/dev/null)
        
        if [[ -n "$desired" ]] && [[ -n "$ready" ]] && [[ "$desired" -eq "$ready" ]] && [[ "$ready" -gt 0 ]]; then
            echo -e "${LGREEN}[✓] Twistlock desplegado exitosamente: $ready/$desired pods listos${NC}"
            
            # Mostrar información de pods
            echo "[TWISTLOCK] Estado de pods:"
            kubectl get pods -n "$twistlock_namespace" -l app=twistlock 2>/dev/null || \
                kubectl get pods -n "$twistlock_namespace" 2>/dev/null
            
            return 0
        fi
        
        echo "[TWISTLOCK] Esperando pods: $ready/$desired listos (${elapsed}s/${timeout}s)"
        sleep "$check_interval"
        ((elapsed += check_interval))
    done
    
    # Timeout alcanzado
    echo -e "${YELLOW}[!] Timeout alcanzado esperando pods de Twistlock${NC}"
    echo "[TWISTLOCK] Estado actual del DaemonSet:"
    kubectl get daemonset "$daemonset_name" -n "$twistlock_namespace" 2>/dev/null
    echo "[TWISTLOCK] Estado de pods:"
    kubectl get pods -n "$twistlock_namespace" 2>/dev/null
    
    echo -e "${YELLOW}[!] Twistlock desplegado pero pods no están completamente listos${NC}"
    echo -e "${YELLOW}[!] Verifique el estado manualmente con: kubectl get pods -n $twistlock_namespace${NC}"
    
    return 0
}

function configure_shared_vpc_permissions() {
    local service_project="$1"
    local host_project="$2"
    
    echo "[SHARED-VPC] Configurando permisos de Shared VPC..."
    echo "[SHARED-VPC] Proyecto servicio: $service_project"
    echo "[SHARED-VPC] Proyecto host: $host_project"
    
    # Obtener número de proyecto del servicio
    echo "[SHARED-VPC] Obteniendo número de proyecto del servicio..."
    local service_project_number
    service_project_number=$(gcloud projects describe "$service_project" --format="value(projectNumber)" 2>/dev/null)
    
    if [[ -z "$service_project_number" ]]; then
        echo -e "${RED}[ERROR] No se pudo obtener el número del proyecto: $service_project${NC}"
        return 1
    fi
    
    echo "[SHARED-VPC] Número de proyecto servicio: $service_project_number"
    
    # Cuentas de servicio de GKE
    local gke_service_account="service-${service_project_number}@container-engine-robot.iam.gserviceaccount.com"
    local gke_api_account="${service_project_number}@cloudservices.gserviceaccount.com"
    
    echo "[SHARED-VPC] Cuenta de servicio GKE: $gke_service_account"
    echo "[SHARED-VPC] Cuenta de servicio API: $gke_api_account"
    
    # Verificar si el proyecto servicio ya está asociado
    echo "[SHARED-VPC] Verificando asociación Shared VPC..."
    local is_associated
    is_associated=$(gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep -c "^${service_project}$" || echo "0")
    
    if [[ "$is_associated" == "0" ]]; then
        echo "[SHARED-VPC] Asociando proyecto al Shared VPC host..."
        local associate_output
        associate_output=$(gcloud compute shared-vpc associated-projects add "$service_project" \
            --host-project="$host_project" 2>&1)
        local associate_status=$?
        
        if [[ $associate_status -eq 0 ]]; then
            echo -e "${LGREEN}[✓] Proyecto asociado al Shared VPC${NC}"
            sleep 5  # Esperar a que la asociación se propague
        else
            echo -e "${RED}[ERROR] No se pudo asociar el proyecto al Shared VPC${NC}"
            echo -e "${YELLOW}Detalles del error:${NC}"
            echo "$associate_output"
            echo ""
            echo -e "${YELLOW}[ACCIÓN REQUERIDA] Ejecute el siguiente comando manualmente:${NC}"
            echo ""
            echo -e "${LCYAN}gcloud compute shared-vpc associated-projects add $service_project \\${NC}"
            echo -e "${LCYAN}    --host-project=$host_project${NC}"
            echo ""
            echo -e "${YELLOW}Esto requiere uno de estos roles en el proyecto HOST ($host_project):${NC}"
            echo -e "  • ${WHITE}roles/compute.xpnAdmin${NC}"
            echo -e "  • ${WHITE}roles/owner${NC}"
            echo ""
            return 1
        fi
        
        # Verificar que la asociación fue exitosa
        sleep 2
        is_associated=$(gcloud compute shared-vpc associated-projects list "$host_project" \
            --format="value(id)" 2>/dev/null | grep -c "^${service_project}$" || echo "0")
        
        if [[ "$is_associated" == "0" ]]; then
            echo -e "${RED}[ERROR] La asociación no se completó correctamente${NC}"
            return 1
        fi
    else
        echo -e "${LGREEN}[✓] Proyecto ya asociado al Shared VPC${NC}"
    fi
    
    # Otorgar permisos en el proyecto host
    echo "[SHARED-VPC] Configurando permisos IAM en proyecto host..."
    
    # Rol: Compute Network User
    echo "[SHARED-VPC]   • Otorgando roles/compute.networkUser a GKE service account..."
    gcloud projects add-iam-policy-binding "$host_project" \
        --member="serviceAccount:${gke_service_account}" \
        --role="roles/compute.networkUser" \
        --condition=None \
        --quiet 2>/dev/null || echo -e "${YELLOW}    [!] Rol ya asignado${NC}"
    
    gcloud projects add-iam-policy-binding "$host_project" \
        --member="serviceAccount:${gke_api_account}" \
        --role="roles/compute.networkUser" \
        --condition=None \
        --quiet 2>/dev/null || echo -e "${YELLOW}    [!] Rol ya asignado${NC}"
    
    # Rol: Host Service Agent User (requerido para usar Shared VPC)
    echo "[SHARED-VPC]   • Otorgando roles/container.hostServiceAgentUser a GKE service account..."
    gcloud projects add-iam-policy-binding "$host_project" \
        --member="serviceAccount:${gke_service_account}" \
        --role="roles/container.hostServiceAgentUser" \
        --condition=None \
        --quiet 2>/dev/null || echo -e "${YELLOW}    [!] Rol ya asignado${NC}"
    
    # Esperar propagación de permisos
    echo "[SHARED-VPC] Esperando propagación de permisos (10s)..."
    sleep 10
    
    echo -e "${LGREEN}[✓] Permisos de Shared VPC configurados${NC}"
    return 0
}

function detect_secondary_ranges() {
    local subnet_to_check="${1:-$SUBNET_NAME}"
    local host_project="${2:-$SHARED_HOST}"
    
    echo "[SHARED-VPC] Detectando rangos secundarios en la subred '$subnet_to_check'..."
    
    # Validar que jq está instalado
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}[ERROR] La utilidad 'jq' es necesaria para la detección dinámica de rangos.${NC}"
        echo -e "${YELLOW}[!] Instale jq con: sudo apt-get install jq (Debian/Ubuntu) o sudo yum install jq (RHEL/CentOS)${NC}"
        return 1
    fi
    
    # Obtener detalles de la subred en formato JSON
    echo "[SHARED-VPC] Consultando subred en proyecto '$host_project', región '$region'..."
    local subnet_details
    subnet_details=$(gcloud compute networks subnets describe "$subnet_to_check" \
        --project="$host_project" \
        --region="$region" \
        --format="json" 2>/dev/null)
    
    if [[ -z "$subnet_details" ]]; then
        echo -e "${RED}[ERROR] No se pudo obtener la información de la subred '$subnet_to_check'.${NC}"
        echo -e "${YELLOW}[!] Verifique:${NC}"
        echo -e "${YELLOW}    - Nombre de subred: $subnet_to_check${NC}"
        echo -e "${YELLOW}    - Proyecto host: $host_project${NC}"
        echo -e "${YELLOW}    - Región: $region${NC}"
        echo -e "${YELLOW}    - Permisos de lectura en el proyecto host${NC}"
        return 1
    fi
    
    # Mostrar rangos secundarios disponibles
    local all_ranges
    all_ranges=$(echo "$subnet_details" | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null)
    
    if [[ -z "$all_ranges" ]]; then
        echo -e "${RED}[ERROR] La subred '$subnet_to_check' no tiene rangos secundarios configurados.${NC}"
        return 1
    fi
    
    echo "[SHARED-VPC] Rangos secundarios encontrados:"
    echo "$all_ranges" | while IFS= read -r range_name; do
        local range_cidr
        range_cidr=$(echo "$subnet_details" | jq -r ".secondaryIpRanges[] | select(.rangeName==\"$range_name\") | .ipCidrRange")
        echo "  • $range_name → $range_cidr"
    done
    
    # Buscar el rango de Pods (debe contener "pods" o "pod")
    PODS_RANGE_NAME=$(echo "$subnet_details" | jq -r '.secondaryIpRanges[]? | select(.rangeName | test("pods?"; "i")) | .rangeName' | head -n 1)
    
    # Buscar el rango de Servicios (debe contener "services", "servicios" o "service")
    SERVICES_RANGE_NAME=$(echo "$subnet_details" | jq -r '.secondaryIpRanges[]? | select(.rangeName | test("servic(e|io)s?"; "i")) | .rangeName' | head -n 1)
    
    # Validar que ambos rangos fueron encontrados
    if [[ -z "$PODS_RANGE_NAME" ]]; then
        echo -e "${RED}[ERROR] No se encontró un rango secundario para 'Pods' en la subred '$subnet_to_check'.${NC}"
        echo -e "${YELLOW}[!] Se esperaba un rango con nombre conteniendo 'pod' o 'pods'.${NC}"
        echo -e "${YELLOW}[!] Rangos disponibles: $all_ranges${NC}"
        return 1
    fi
    
    if [[ -z "$SERVICES_RANGE_NAME" ]]; then
        echo -e "${RED}[ERROR] No se encontró un rango secundario para 'Servicios' en la subred '$subnet_to_check'.${NC}"
        echo -e "${YELLOW}[!] Se esperaba un rango con nombre conteniendo 'service', 'services' o 'servicios'.${NC}"
        echo -e "${YELLOW}[!] Rangos disponibles: $all_ranges${NC}"
        return 1
    fi
    
    # Obtener los rangos de IP para mostrar al usuario
    local pods_cidr
    local services_cidr
    pods_cidr=$(echo "$subnet_details" | jq -r ".secondaryIpRanges[] | select(.rangeName==\"$PODS_RANGE_NAME\") | .ipCidrRange")
    services_cidr=$(echo "$subnet_details" | jq -r ".secondaryIpRanges[] | select(.rangeName==\"$SERVICES_RANGE_NAME\") | .ipCidrRange")
    
    echo -e "${LGREEN}[✓] Rango de Pods detectado: ${LCYAN}${PODS_RANGE_NAME}${NC} ${WHITE}(${pods_cidr})${NC}"
    echo -e "${LGREEN}[✓] Rango de Servicios detectado: ${LCYAN}${SERVICES_RANGE_NAME}${NC} ${WHITE}(${services_cidr})${NC}"
    
    return 0
}

function apply_cluster_hardening() {
    local security_policy_name="cve-canary"
    local ssl_policy_name="sslsecure"
    local waf_allowed_ips="35.238.84.248,34.121.197.40"
    local hardening_log="./hardening_${cluster_name}_$(date +%Y%m%d_%H%M%S).log"
    
    echo "[HARDENING] Iniciando endurecimiento de seguridad del cluster..."
    echo "[HARDENING] Log: $hardening_log"
    
    # Validar dependencias
    echo "[HARDENING] Validando dependencias..."
    local missing_deps=()
    
    command -v jq &>/dev/null || missing_deps+=("jq")
    command -v kubectl &>/dev/null || missing_deps+=("kubectl")
    command -v gcloud &>/dev/null || missing_deps+=("gcloud")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}[ERROR] Dependencias faltantes: ${missing_deps[*]}${NC}" | tee -a "$hardening_log"
        echo -e "${YELLOW}[!] Instale las dependencias requeridas${NC}"
        return 1
    fi
    
    echo "[HARDENING] Todas las dependencias disponibles" | tee -a "$hardening_log"
    
    # Verificar conectividad con GCP
    echo "[HARDENING] Verificando conectividad con GCP..."
    if ! gcloud projects describe "$project_id" &>/dev/null; then
        echo -e "${RED}[ERROR] No se puede acceder al proyecto $project_id${NC}" | tee -a "$hardening_log"
        return 1
    fi
    
    # Obtener credenciales del cluster
    echo "[HARDENING] Obteniendo credenciales del cluster..." | tee -a "$hardening_log"
    if ! gcloud container clusters get-credentials "$cluster_name" \
        --region "$region" \
        --project "$project_id" \
        --quiet 2>>"$hardening_log"; then
        echo -e "${RED}[ERROR] No se pudieron obtener credenciales del cluster${NC}" | tee -a "$hardening_log"
        return 1
    fi
    
    # Verificar conectividad con el cluster
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}[ERROR] No se puede conectar al cluster${NC}" | tee -a "$hardening_log"
        return 1
    fi
    
    echo "[HARDENING] Conexión al cluster verificada" | tee -a "$hardening_log"
    
    # 1. Crear política de seguridad (CVE-Canary)
    echo "[HARDENING] === PASO 1/6: Política de Seguridad ===" | tee -a "$hardening_log"
    if gcloud compute security-policies describe "$security_policy_name" --project="$project_id" &>/dev/null; then
        echo -e "${YELLOW}[!] Política de seguridad '$security_policy_name' ya existe${NC}" | tee -a "$hardening_log"
    else
        echo "[HARDENING] Creando política de seguridad: $security_policy_name" | tee -a "$hardening_log"
        if gcloud compute security-policies create "$security_policy_name" \
            --project="$project_id" 2>>"$hardening_log"; then
            echo -e "${LGREEN}[✓] Política de seguridad creada${NC}" | tee -a "$hardening_log"
        else
            echo -e "${RED}[ERROR] Falló creación de política de seguridad${NC}" | tee -a "$hardening_log"
            return 1
        fi
    fi
    
    # Determinar ambiente (PRO vs QA/UAT)
    local is_production=false
    if [[ "$project_id" =~ -pro$ ]]; then
        is_production=true
        echo "[HARDENING] Ambiente detectado: PRODUCCIÓN" | tee -a "$hardening_log"
    else
        echo "[HARDENING] Ambiente detectado: QA/UAT" | tee -a "$hardening_log"
    fi
    
    # 2. Configurar reglas según ambiente
    if [[ "$is_production" == true ]]; then
        # === REGLAS PARA PRODUCCIÓN (3 reglas) ===
        echo "[HARDENING] === PASO 2/6: Aplicando reglas para ambiente PRO ===" | tee -a "$hardening_log"
        
        # Regla 1: CVE-Canary (Prioridad 1)
        echo "[HARDENING]   • Regla 1: CVE-Canary (deny-403)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 1 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla CVE (1) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 1 \
                --action=deny-403 \
                --security-policy="$security_policy_name" \
                --expression="evaluatePreconfiguredExpr('cve-canary')" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla CVE-Canary creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${RED}    [ERROR] Falló creación de regla CVE${NC}" | tee -a "$hardening_log"
                return 1
            fi
        fi
        
        # Regla 2: IPs WAF permitidas (Prioridad 100)
        echo "[HARDENING]   • Regla 2: IPs WAF (allow)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 100 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla IPs WAF (100) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 100 \
                --action=allow \
                --security-policy="$security_policy_name" \
                --description="IPs WAF" \
                --src-ip-ranges="35.238.84.248,34.121.197.40,34.123.202.20,34.71.3.13" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla IPs WAF creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${RED}    [ERROR] Falló creación de regla IPs WAF${NC}" | tee -a "$hardening_log"
                return 1
            fi
        fi
        
        # Regla 3: Default rule - Deny all (Prioridad 2147483647)
        echo "[HARDENING]   • Regla 3: Default rule (deny-502)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 2147483647 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla por defecto (2147483647) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 2147483647 \
                --action=deny-502 \
                --security-policy="$security_policy_name" \
                --description="default rule" \
                --src-ip-ranges='*' \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla por defecto creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${RED}    [ERROR] Falló creación de regla por defecto${NC}" | tee -a "$hardening_log"
                return 1
            fi
        fi
        
    else
        # === REGLAS PARA QA/UAT (7 reglas) ===
        echo "[HARDENING] === PASO 2/6: Aplicando reglas para ambiente QA/UAT ===" | tee -a "$hardening_log"
        
        # Regla 1: CVE-Canary (Prioridad 1)
        echo "[HARDENING]   • Regla 1: CVE-Canary (deny-403)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 1 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla CVE (1) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 1 \
                --action=deny-403 \
                --security-policy="$security_policy_name" \
                --expression="evaluatePreconfiguredExpr('cve-canary')" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla CVE-Canary creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${RED}    [ERROR] Falló creación de regla CVE${NC}" | tee -a "$hardening_log"
                return 1
            fi
        fi
        
        # Regla 2: API Manager VMs Public IP for QA (Prioridad 90)
        echo "[HARDENING]   • Regla 2: API Manager VMs Public IP for QA (allow)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 90 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla API Manager (90) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 90 \
                --action=allow \
                --security-policy="$security_policy_name" \
                --description="API Manager VMs Public IP for QA" \
                --src-ip-ranges="34.10.190.252,34.10.190.252,34.10.190.252,34.10.190.252" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla API Manager creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${YELLOW}    [!] Falló creación de regla API Manager${NC}" | tee -a "$hardening_log"
            fi
        fi
        
        # Regla 3: Apigee NAT red central IPs (Prioridad 91)
        echo "[HARDENING]   • Regla 3: Apigee NAT red central IPs (allow)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 91 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla Apigee NAT (91) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 91 \
                --action=allow \
                --security-policy="$security_policy_name" \
                --description="Apigee NAT red central IPs" \
                --src-ip-ranges="35.223.194.216,34.121.174.67,35.194.4.57,35.223.189.203" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla Apigee NAT creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${YELLOW}    [!] Falló creación de regla Apigee NAT${NC}" | tee -a "$hardening_log"
            fi
        fi
        
        # Regla 4: ZScaler IP Range (Prioridad 92)
        echo "[HARDENING]   • Regla 4: ZScaler IP Range (allow)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 92 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla ZScaler (92) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 92 \
                --action=allow \
                --security-policy="$security_policy_name" \
                --description="ZScaler IP Range" \
                --src-ip-ranges="10.67.126.0/24" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla ZScaler creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${YELLOW}    [!] Falló creación de regla ZScaler${NC}" | tee -a "$hardening_log"
            fi
        fi
        
        # Regla 5: VM Servicio de cuentas para ambientes QA (Prioridad 93)
        echo "[HARDENING]   • Regla 5: VM Servicio de cuentas para ambientes QA (allow)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 93 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla VM Servicio (93) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 93 \
                --action=allow \
                --security-policy="$security_policy_name" \
                --description="VM Servicio de cuentas para ambientes QA" \
                --src-ip-ranges="34.172.162.222,34.59.214.51" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla VM Servicio creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${YELLOW}    [!] Falló creación de regla VM Servicio${NC}" | tee -a "$hardening_log"
            fi
        fi
        
        # Regla 6: F5 WAF IP Addresses (Prioridad 95)
        echo "[HARDENING]   • Regla 6: F5 WAF IP Addresses (allow)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 95 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla F5 WAF (95) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 95 \
                --action=allow \
                --security-policy="$security_policy_name" \
                --description="F5 WAF IP Addresses" \
                --src-ip-ranges="34.123.237.82,35.184.162.71,35.238.84.248,34.121.197.40,34.71.3.13,34.123.202.20,55.239.56.35" \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla F5 WAF creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${YELLOW}    [!] Falló creación de regla F5 WAF${NC}" | tee -a "$hardening_log"
            fi
        fi
        
        # Regla 7: Default rule - Deny all (Prioridad 2147483647)
        echo "[HARDENING]   • Regla 7: Default rule (deny-403)" | tee -a "$hardening_log"
        if gcloud compute security-policies rules describe 2147483647 \
            --security-policy="$security_policy_name" \
            --project="$project_id" &>/dev/null; then
            echo -e "${YELLOW}    [!] Regla por defecto (2147483647) ya existe${NC}" | tee -a "$hardening_log"
        else
            if gcloud compute security-policies rules create 2147483647 \
                --action=deny-403 \
                --security-policy="$security_policy_name" \
                --description="Default rule, higher priority overrides it" \
                --src-ip-ranges='*' \
                --project="$project_id" 2>>"$hardening_log"; then
                echo -e "${LGREEN}    [✓] Regla por defecto creada${NC}" | tee -a "$hardening_log"
            else
                echo -e "${RED}    [ERROR] Falló creación de regla por defecto${NC}" | tee -a "$hardening_log"
                return 1
            fi
        fi
    fi
    
    echo "[HARDENING] === PASO 3/6: Reglas de seguridad completadas ===" | tee -a "$hardening_log"
    
    # 4. (Anteriormente paso 5) Aplicar política a Backend Services
    echo "[HARDENING] === PASO 4/6: Aplicar a Backend Services ===" | tee -a "$hardening_log"
    
    # 5. Aplicar política a Backend Services
    echo "[HARDENING] === PASO 5/6: Aplicar a Backend Services ===" | tee -a "$hardening_log"
    
    # Actualizar política con JSON parsing
    echo "[HARDENING] Configurando JSON parsing STANDARD..." | tee -a "$hardening_log"
    gcloud compute security-policies update "$security_policy_name" \
        --json-parsing=STANDARD \
        --project="$project_id" 2>>"$hardening_log" || \
        echo -e "${YELLOW}[!] JSON parsing ya configurado${NC}" | tee -a "$hardening_log"
    
    # Obtener backend services
    echo "[HARDENING] Obteniendo lista de backend-services..." | tee -a "$hardening_log"
    local backend_services
    backend_services=$(gcloud compute backend-services list \
        --project="$project_id" \
        --format=json 2>>"$hardening_log" | jq -r '.[].name' 2>>"$hardening_log")
    
    if [[ -z "$backend_services" ]]; then
        echo -e "${YELLOW}[!] No se encontraron backend-services${NC}" | tee -a "$hardening_log"
    else
        local backend_count=0
        local backend_updated=0
        local backend_failed=0
        
        while IFS= read -r backend_svc; do
            if [[ -n "$backend_svc" ]]; then
                ((backend_count++))
                echo "[HARDENING] Aplicando política a: $backend_svc" | tee -a "$hardening_log"
                
                if gcloud compute backend-services update "$backend_svc" \
                    --security-policy="$security_policy_name" \
                    --global \
                    --project="$project_id" 2>>"$hardening_log"; then
                    ((backend_updated++))
                    echo -e "${LGREEN}  [✓] $backend_svc actualizado${NC}" | tee -a "$hardening_log"
                else
                    ((backend_failed++))
                    echo -e "${YELLOW}  [!] Falló actualización de $backend_svc${NC}" | tee -a "$hardening_log"
                fi
            fi
        done <<< "$backend_services"
        
        echo "[HARDENING] Backend Services: $backend_updated/$backend_count actualizados, $backend_failed fallidos" | tee -a "$hardening_log"
    fi
    
    # 5. Crear política SSL (TLS 1.2+)
    echo "[HARDENING] === PASO 5/6: Política SSL ===" | tee -a "$hardening_log"
    if gcloud compute ssl-policies describe "$ssl_policy_name" --project="$project_id" &>/dev/null; then
        echo -e "${YELLOW}[!] Política SSL '$ssl_policy_name' ya existe${NC}" | tee -a "$hardening_log"
    else
        echo "[HARDENING] Creando política SSL con TLS 1.2+ (MODERN)" | tee -a "$hardening_log"
        if gcloud compute ssl-policies create "$ssl_policy_name" \
            --profile=MODERN \
            --min-tls-version=1.2 \
            --project="$project_id" 2>>"$hardening_log"; then
            echo -e "${LGREEN}[✓] Política SSL creada${NC}" | tee -a "$hardening_log"
        else
            echo -e "${RED}[ERROR] Falló creación de política SSL${NC}" | tee -a "$hardening_log"
            return 1
        fi
    fi
    
    # 6. Habilitar Container Security API
    echo "[HARDENING] === PASO 6/6: Habilitando APIs de Seguridad ===" | tee -a "$hardening_log"
    if gcloud services enable containersecurity.googleapis.com \
        --project="$project_id" 2>>"$hardening_log"; then
        echo -e "${LGREEN}[✓] Container Security API habilitada${NC}" | tee -a "$hardening_log"
    else
        echo -e "${YELLOW}[!] Container Security API ya estaba habilitada${NC}" | tee -a "$hardening_log"
    fi
    
    # 7. Desplegar Twistlock (solo en PRO)
    if [[ "$is_production" == true ]]; then
        echo "[HARDENING] === Desplegando Twistlock (ambiente PRO) ===" | tee -a "$hardening_log"
        if deploy_twistlock; then
            echo -e "${LGREEN}[✓] Twistlock desplegado exitosamente${NC}" | tee -a "$hardening_log"
        else
            echo -e "${YELLOW}[!] Twistlock no pudo ser desplegado completamente${NC}" | tee -a "$hardening_log"
        fi
    else
        echo "[HARDENING] === Twistlock omitido (solo se aplica en ambiente PRO) ===" | tee -a "$hardening_log"
    fi
    
    # Resumen final
    echo "" | tee -a "$hardening_log"
    echo "[HARDENING] ==========================================" | tee -a "$hardening_log"
    echo "[HARDENING]   HARDENING COMPLETADO" | tee -a "$hardening_log"
    echo "[HARDENING] ==========================================" | tee -a "$hardening_log"
    echo "[HARDENING] Cluster: $cluster_name" | tee -a "$hardening_log"
    echo "[HARDENING] Proyecto: $project_id" | tee -a "$hardening_log"
    echo "[HARDENING] Política de Seguridad: $security_policy_name" | tee -a "$hardening_log"
    echo "[HARDENING] Política SSL: $ssl_policy_name" | tee -a "$hardening_log"
    echo "[HARDENING] Log completo: $hardening_log" | tee -a "$hardening_log"
    echo "[HARDENING] ==========================================" | tee -a "$hardening_log"
    
    return 0
}

# 1. Recopilación de Parámetros
echo -e "${LGREEN}========================================${NC}"
echo -e "${LGREEN}  GNP Cloud Infrastructure Team${NC}"
echo -e "${LGREEN}  Standard Cluster Creation v3.6.0${NC}"
echo -e "${LGREEN}  Dynamic Secondary Range Detection${NC}"
echo -e "${LGREEN}========================================${NC}"
echo ""

prompt_input "Ingrese el ID del Proyecto de GKE" "my-project" project_id
prompt_input "Ingrese el Nombre del Clúster" "gke-${project_id}" cluster_name
prompt_input "Ingrese la Región de GCP" "us-central1" region
prompt_input "Ingrese la Zona de GCP" "us-central1-f" zone

[[ "$project_id" =~ -pro$ ]] && default_machine="n2-standard-2" || default_machine="n1-standard-2"
prompt_input "Ingrese el Tipo de Máquina" "$default_machine" machine_type

[[ "$project_id" =~ -pro$ ]] && default_nodes="2" || default_nodes="1"
prompt_input "Ingrese el Número de Nodos" "$default_nodes" num_nodes

# Sugerencia de canal según ambiente
if [[ "$project_id" =~ -pro$ ]]; then
    default_channel="regular"
else
    default_channel="rapid"
fi
prompt_input "Seleccione Canal (stable, regular, rapid)" "$default_channel" channel
prompt_input "¿Clúster privado? ([1]Privado, [2]Público)" "1" private_nodes

[[ "$private_nodes" == "1" ]] && prompt_input "Rango IP Control Plane" "172.19.0.0/28" control_plane_ip
prompt_input "Acceso API ([1]Defecto, [2]Completo)" "1" cluster_scope

[[ "$project_id" =~ -pro$ ]] && prompt_input "Flota GKE ([1]qa, [2]uat, [3]pro)" "3" fleet_option
[[ "$project_id" =~ -uat$ ]] && [[ ! "$project_id" =~ -pro$ ]] && prompt_input "Flota GKE ([1]qa, [2]uat, [3]pro)" "2" fleet_option
[[ ! "$project_id" =~ -pro$ ]] && [[ ! "$project_id" =~ -uat$ ]] && prompt_input "Flota GKE ([1]qa, [2]uat, [3]pro)" "1" fleet_option

# Obtener versión de cluster dinámicamente desde GCP
echo -e "${LGREEN}Obteniendo versión de cluster desde GCP...${NC}"
if ! cluster_version=$(get_cluster_versions "$region" "$channel"); then
    echo -e "${YELLOW}[!] No se pudo obtener versión dinámica. Usando versión manual...${NC}"
    # Fallback a versiones por defecto si falla la obtención dinámica
    case "$channel" in
        rapid)  cluster_version="1.32.11-gke.1174000" ;;
        regular) cluster_version="1.32.11-gke.1038000" ;;
        stable) cluster_version="1.32.9-gke.1728000" ;;
        *) echo -e "${RED}[ERROR] Canal inválido${NC}"; exit 1 ;;
    esac
fi

case "$cluster_scope" in
    1) cluster_access_scope="https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append" ;;
    2) cluster_access_scope="https://www.googleapis.com/auth/cloud-platform" ;;
    *) echo -e "${RED}[ERROR] Scope inválido${NC}"; exit 1 ;;
esac

case "$fleet_option" in
    1) fleet_id="gnp-fleets-qa" ;;
    2) fleet_id="gnp-fleets-uat" ;;
    3) fleet_id="gnp-fleets-pro" ;;
    *) echo -e "${RED}[ERROR] Flota inválida${NC}"; exit 1 ;;
esac

# 2. Resumen
echo -e "${YELLOW}Resumen de configuración:${NC}"
echo -e "${WHITE}  Proyecto: ${LCYAN}$project_id${NC}"
echo -e "${WHITE}  Clúster: ${LCYAN}$cluster_name${NC}"
echo -e "${WHITE}  Región/Zona: ${LCYAN}$region / $zone${NC}"
echo -e "${WHITE}  Máquina: ${LCYAN}$machine_type x $num_nodes nodos${NC}"
echo -e "${WHITE}  Canal: ${LCYAN}$channel ($cluster_version)${NC}"
echo -e "${WHITE}  Tipo: ${LCYAN}$([ "$private_nodes" == "1" ] && echo "Privado" || echo "Público")${NC}"
echo -e "${WHITE}  Flota: ${LCYAN}$fleet_id${NC}"
ask

# 3. Ejecución
echo -e "${LGREEN}Configurando proyecto...${NC}"
gcloud config set project "$project_id"
gcloud services enable container.googleapis.com --project="$project_id"
gcloud services enable gkehub.googleapis.com --project="$project_id"
gcloud services enable compute.googleapis.com --project="$project_id"

# 3.2 VPC
echo -e "${LGREEN}Configurando VPC...${NC}"

vpc_exists=$(gcloud compute networks list --project="$project_id" --filter="name:$project_id" --format="value(NAME)" 2>/dev/null)

if [[ -n "$vpc_exists" ]]; then
    echo -e "${LGREEN}VPC existente encontrada: ${LCYAN}$vpc_exists${NC}"
    prompt_input "¿Qué desea hacer? ([1]Usar actual, [2]Crear nueva, [3]Usar Shared VPC)" "1" vpc_choice
else
    echo -e "${YELLOW}No existe VPC ${project_id}.${NC}"
    prompt_input "¿Qué desea hacer? ([1]Crear nueva, [2]Usar Shared VPC)" "1" vpc_choice
fi

case "$vpc_choice" in
    1)
        if [[ -n "$vpc_exists" ]]; then
            echo -e "${LGREEN}Usando VPC actual: ${LCYAN}$vpc_exists${NC}"
            VPC_NAME="$vpc_exists"
            SUBNET_NAME="$vpc_exists"
            
            # Verificar y agregar rangos secundarios si no existen
            echo -e "${LGREEN}Verificando rangos secundarios...${NC}"
            gcloud compute networks subnets update "$project_id" \
                --project="$project_id" \
                --region="$region" \
                --add-secondary-ranges pods=10.88.8.0/21,servicios=10.82.4.64/27 2>/dev/null || \
                echo -e "${YELLOW}[!] Rangos secundarios ya existen o subnet no encontrada${NC}"
        else
            echo -e "${LGREEN}Creando VPC nueva...${NC}"
            prompt_input "Ingrese rango IP (Ej: 10.0.0.0/16)" "10.0.0.0/16" vpc_ip
            
            gcloud compute networks create "$project_id" \
                --project="$project_id" \
                --subnet-mode=custom \
                --mtu=1460 \
                --bgp-routing-mode=regional 2>/dev/null || \
                echo -e "${YELLOW}[!] VPC ya existe${NC}"
            
            gcloud compute networks subnets create "$project_id" \
                --project="$project_id" \
                --range="$vpc_ip" \
                --stack-type=IPV4_ONLY \
                --network="$project_id" \
                --region="$region" \
                --secondary-range pods=10.88.8.0/21,servicios=10.82.4.64/27 \
                --enable-private-ip-google-access 2>/dev/null || {
                echo -e "${YELLOW}[!] Subred ya existe, actualizando rangos secundarios...${NC}"
                gcloud compute networks subnets update "$project_id" \
                    --project="$project_id" \
                    --region="$region" \
                    --add-secondary-ranges pods=10.88.8.0/21,servicios=10.82.4.64/27 2>/dev/null || \
                    echo -e "${YELLOW}[!] Rangos secundarios ya existen${NC}"
            }
            
            VPC_NAME="$project_id"
            SUBNET_NAME="$project_id"
        fi
        ;;
    2)
        if [[ -n "$vpc_exists" ]]; then
            echo -e "${LGREEN}Creando VPC nueva...${NC}"
            prompt_input "Ingrese rango IP (Ej: 10.0.0.0/16)" "10.0.0.0/16" vpc_ip
            
            gcloud compute networks create "$project_id" \
                --project="$project_id" \
                --subnet-mode=custom \
                --mtu=1460 \
                --bgp-routing-mode=regional 2>/dev/null || \
                echo -e "${YELLOW}[!] VPC ya existe${NC}"
            
            gcloud compute networks subnets create "$project_id" \
                --project="$project_id" \
                --range="$vpc_ip" \
                --stack-type=IPV4_ONLY \
                --network="$project_id" \
                --region="$region" \
                --secondary-range pods=10.88.8.0/21,servicios=10.82.4.64/27 \
                --enable-private-ip-google-access 2>/dev/null || {
                echo -e "${YELLOW}[!] Subred ya existe, actualizando rangos secundarios...${NC}"
                gcloud compute networks subnets update "$project_id" \
                    --project="$project_id" \
                    --region="$region" \
                    --add-secondary-ranges pods=10.88.8.0/21,servicios=10.82.4.64/27 2>/dev/null || \
                    echo -e "${YELLOW}[!] Rangos secundarios ya existen${NC}"
            }
            
            VPC_NAME="$project_id"
            SUBNET_NAME="$project_id"
        else
            echo -e "${LGREEN}Configurando Shared VPC...${NC}"
            prompt_input "ID del proyecto anfitrión" "gnp-red-data-central" shared_host
            SHARED_HOST="$shared_host"
            prompt_input "Nombre de VPC compartida" "gnp-datalake-qa" vpc_name
            VPC_NAME="$vpc_name"
            prompt_input "Nombre de subnet compartida" "$project_id" subnet_name
            SUBNET_NAME="$subnet_name"
            IS_SHARED_VPC="true"
        fi
        ;;
    3)
        echo -e "${LGREEN}Configurando Shared VPC...${NC}"
        prompt_input "ID del proyecto anfitrión" "gnp-red-data-central" shared_host
        SHARED_HOST="$shared_host"
        prompt_input "Nombre de VPC compartida del proyecto anfitrión" "gnp-datalake-qa" vpc_name
        VPC_NAME="$vpc_name"
        prompt_input "Nombre de subnet compartida del proyecto anfitrión" "$project_id" subnet_name
        SUBNET_NAME="$subnet_name"
        IS_SHARED_VPC="true"
        ;;
    *)
        echo -e "${RED}[ERROR] Opción inválida. Abortando.${NC}"
        exit 1
        ;;
esac

echo -e "${LGREEN}[✓] VPC: ${LCYAN}$VPC_NAME${NC}"

# 3.3 Cloud NAT (Opcional para QA/UAT, Obligatorio para PRO)
echo -e "${LGREEN}Configurando Cloud NAT...${NC}"

# Verificar si Cloud Router existe (validación más robusta)
router_exists=false
if gcloud compute routers describe "$project_id-router" --region="$region" --project="$project_id" &>/dev/null; then
    router_exists=true
fi

if [[ "$router_exists" == "true" ]]; then
    # Verificar si el NAT existe en el router
    if gcloud compute routers nats describe "${project_id}-nat" --router="${project_id}-router" --region="$region" --project="$project_id" &>/dev/null; then
        echo -e "${LGREEN}[✓] Cloud NAT existente encontrado: ${LCYAN}${project_id}-nat${NC}"
        echo -e "${LGREEN}[✓] Cloud Router: ${LCYAN}${project_id}-router${NC}"
        echo -e "${YELLOW}[!] Saltando creación de Cloud NAT y Router${NC}"
    else
        echo -e "${YELLOW}[!] Router existe pero sin NAT configurado${NC}"
        # Preguntar si se quiere crear NAT en el router existente
        prompt_input "¿Desea crear Cloud NAT en el router existente? ([1]Sí, [2]No/Saltar)" "1" create_nat_only_choice
        
        if [[ "$create_nat_only_choice" == "1" ]]; then
            echo -e "${LGREEN}  • Creando Cloud NAT en router existente...${NC}"
            NAT_CREATE_OUTPUT=$(gcloud compute routers nats create "$project_id-nat" \
                --router="$project_id-router" \
                --region="$region" \
                --project="$project_id" \
                --auto-allocate-nat-external-ips \
                --nat-all-subnet-ip-ranges \
                --icmp-idle-timeout=30s \
                --tcp-established-idle-timeout=1200s \
                --tcp-transitory-idle-timeout=30s \
                --udp-idle-timeout=30s 2>&1)
            
            NAT_CREATE_STATUS=$?
            
            if [ $NAT_CREATE_STATUS -ne 0 ]; then
                echo -e "${RED}[ERROR] Fallo al crear NAT:${NC}"
                echo "$NAT_CREATE_OUTPUT"
                exit 1
            fi
            
            echo -e "${LGREEN}[✓] Cloud NAT creado exitosamente${NC}"
        else
            echo -e "${YELLOW}[!] Creación de Cloud NAT omitida${NC}"
        fi
    fi
else
    # No existe Router ni NAT, preguntar si se quiere crear
    echo -e "${YELLOW}No existe Cloud Router ni Cloud NAT en la región${NC}"
    
    # Determinar si crear NAT por defecto según ambiente
    if [[ "$project_id" =~ -pro$ ]]; then
        default_create_nat="1"
        echo -e "${YELLOW}Ambiente PRO: Cloud NAT es recomendado${NC}"
    else
        default_create_nat="2"
        echo -e "${YELLOW}Ambiente QA/UAT: Cloud NAT es opcional${NC}"
    fi
    
    prompt_input "¿Desea crear Cloud NAT y Router? ([1]Sí, [2]No/Saltar)" "$default_create_nat" create_nat_choice
    
    if [[ "$create_nat_choice" == "1" ]]; then
        # Crear Router
        echo -e "${LGREEN}  • Creando Cloud Router...${NC}"
        ROUTER_CREATE_OUTPUT=$(gcloud compute routers create "$project_id-router" \
            --network="$VPC_NAME" \
            --region="$region" \
            --project="$project_id" 2>&1)
        
        ROUTER_CREATE_STATUS=$?
        
        if [ $ROUTER_CREATE_STATUS -ne 0 ]; then
            # Verificar si el error es porque el router ya existe
            if echo "$ROUTER_CREATE_OUTPUT" | grep -q "already exists"; then
                echo -e "${YELLOW}    [!] Router ya existe${NC}"
            else
                echo -e "${RED}[ERROR] Fallo al crear Cloud Router:${NC}"
                echo "$ROUTER_CREATE_OUTPUT"
                exit 1
            fi
        fi
        
        # Validar que el router existe
        if ! gcloud compute routers describe "$project_id-router" --region="$region" --project="$project_id" &>/dev/null; then
            echo -e "${RED}[ERROR] Router no válido o no se pudo crear${NC}"
            exit 1
        fi
        
        echo -e "${LGREEN}  ✓ Cloud Router validado correctamente${NC}"
        
        # Crear Cloud NAT
        echo -e "${LGREEN}  • Creando Cloud NAT...${NC}"
        NAT_CREATE_OUTPUT=$(gcloud compute routers nats create "$project_id-nat" \
            --router="$project_id-router" \
            --region="$region" \
            --project="$project_id" \
            --auto-allocate-nat-external-ips \
            --nat-all-subnet-ip-ranges \
            --icmp-idle-timeout=30s \
            --tcp-established-idle-timeout=1200s \
            --tcp-transitory-idle-timeout=30s \
            --udp-idle-timeout=30s 2>&1)
        
        NAT_CREATE_STATUS=$?
        
        if [ $NAT_CREATE_STATUS -ne 0 ]; then
            echo -e "${RED}[ERROR] Fallo al crear NAT:${NC}"
            echo "$NAT_CREATE_OUTPUT"
            exit 1
        fi
        
        # Esperar a que la NAT esté disponible
        echo -e "${LGREEN}  • Esperando a que Cloud NAT esté disponible...${NC}"
        sleep 5
        
        # Validar que NAT existe (con reintentos)
        max_retries=5
        retry=0
        while [ $retry -lt $max_retries ]; do
            if gcloud compute routers nats describe "$project_id-nat" --router="$project_id-router" --region="$region" --project="$project_id" &>/dev/null; then
                echo -e "${LGREEN}[✓] Cloud NAT configurado y validado${NC}"
                break
            fi
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                echo -e "${YELLOW}    Reintentando validación... ($retry/$max_retries)${NC}"
                sleep 3
            fi
        done
        
        if [ $retry -ge $max_retries ]; then
            echo -e "${RED}[ERROR] Cloud NAT no se puede validar después de $max_retries intentos${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}[!] Cloud NAT y Router omitidos${NC}"
    fi
fi

# 3.4 GKE Cluster
echo -e "${LGREEN}Creando clúster GKE...${NC}"

# Verificar si el clúster ya existe
if gcloud container clusters describe "$cluster_name" --region="$region" --project="$project_id" &>/dev/null; then
    echo -e "${YELLOW}[!] Clúster ya existe: $cluster_name${NC}"
else
    echo -e "${LGREEN}Creando nuevo clúster: $cluster_name${NC}"
    
    PRIVATE_FLAGS=""
    if [[ "$private_nodes" == "1" ]]; then
        PRIVATE_FLAGS="--enable-private-nodes"
    fi

    LOCATION_FLAG="--region=$region"
    NODE_LOCATIONS_OPTION="--node-locations=$zone"

    # Construir comando basado en tipo de VPC
    if [[ "$IS_SHARED_VPC" == "true" ]]; then
        # Detectar rangos dinámicamente ANTES de configurar permisos
        echo -e "${LGREEN}Validando configuración de Shared VPC...${NC}"
        if ! detect_secondary_ranges "$SUBNET_NAME" "$SHARED_HOST"; then
            echo -e "${RED}[ERROR] Falló la detección de rangos secundarios. Abortando.${NC}"
            exit 1
        fi
        
        # Configurar permisos de Shared VPC antes de crear el cluster
        echo -e "${LGREEN}Configurando permisos de Shared VPC...${NC}"
        if ! configure_shared_vpc_permissions "$project_id" "$SHARED_HOST"; then
            echo -e "${RED}[ERROR] No se pudieron configurar los permisos de Shared VPC${NC}"
            echo -e "${YELLOW}[!] Verifique que tenga permisos de administrador en el proyecto host: $SHARED_HOST${NC}"
            exit 1
        fi
        
        # Usar Shared VPC con proyecto anfitrión
        gcloud container clusters create "$cluster_name" \
            --project="$project_id" \
            $LOCATION_FLAG \
            --release-channel="$channel" \
            --cluster-version="$cluster_version" \
            --machine-type="$machine_type" \
            --image-type="COS_CONTAINERD" \
            --disk-type="pd-balanced" \
            --disk-size="100" \
            --metadata=disable-legacy-endpoints=true \
            --num-nodes="$num_nodes" \
            --logging=SYSTEM,WORKLOAD \
            --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,JOBSET,CADVISOR,KUBELET,DCGM \
            --scopes="$cluster_access_scope" \
            --no-enable-intra-node-visibility \
            --enable-ip-alias \
            --cluster-secondary-range-name="$PODS_RANGE_NAME" \
            --services-secondary-range-name="$SERVICES_RANGE_NAME" \
            --security-posture=standard \
            --workload-vulnerability-scanning=disabled \
            --no-enable-google-cloud-access \
            --network="projects/$SHARED_HOST/global/networks/$VPC_NAME" \
            --subnetwork="projects/$SHARED_HOST/regions/$region/subnetworks/$SUBNET_NAME" \
            --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,GcpFilestoreCsiDriver \
            --enable-autoupgrade \
            --enable-autorepair \
            --max-surge-upgrade=1 \
            --max-unavailable-upgrade=0 \
            --binauthz-evaluation-mode=DISABLED \
            --enable-managed-prometheus \
            --enable-shielded-nodes --shielded-secure-boot --shielded-integrity-monitoring \
            --enable-secret-manager \
            --workload-pool="${project_id}.svc.id.goog" \
            $NODE_LOCATIONS_OPTION \
            $PRIVATE_FLAGS
    else
        # Usar VPC local del proyecto actual
        # Establecer valores por defecto si no se detectaron (VPC local creada por el script)
        if [[ -z "$PODS_RANGE_NAME" ]]; then
            PODS_RANGE_NAME="pods"
        fi
        if [[ -z "$SERVICES_RANGE_NAME" ]]; then
            SERVICES_RANGE_NAME="servicios"
        fi
        
        echo "[VPC-LOCAL] Usando rangos: pods=$PODS_RANGE_NAME, services=$SERVICES_RANGE_NAME"
        
        gcloud container clusters create "$cluster_name" \
            --project="$project_id" \
            $LOCATION_FLAG \
            --release-channel="$channel" \
            --cluster-version="$cluster_version" \
            --machine-type="$machine_type" \
            --image-type="COS_CONTAINERD" \
            --disk-type="pd-balanced" \
            --disk-size="100" \
            --metadata=disable-legacy-endpoints=true \
            --num-nodes="$num_nodes" \
            --logging=SYSTEM,WORKLOAD \
            --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,JOBSET,CADVISOR,KUBELET,DCGM \
            --scopes="$cluster_access_scope" \
            --no-enable-intra-node-visibility \
            --enable-ip-alias \
            --cluster-secondary-range-name="$PODS_RANGE_NAME" \
            --services-secondary-range-name="$SERVICES_RANGE_NAME" \
            --security-posture=standard \
            --workload-vulnerability-scanning=disabled \
            --no-enable-google-cloud-access \
            --network="projects/$project_id/global/networks/$VPC_NAME" \
            --subnetwork="projects/$project_id/regions/$region/subnetworks/$SUBNET_NAME" \
            --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,GcpFilestoreCsiDriver \
            --enable-autoupgrade \
            --enable-autorepair \
            --max-surge-upgrade=1 \
            --max-unavailable-upgrade=0 \
            --binauthz-evaluation-mode=DISABLED \
            --enable-managed-prometheus \
            --enable-shielded-nodes --shielded-secure-boot --shielded-integrity-monitoring \
            --enable-secret-manager \
            --workload-pool="${project_id}.svc.id.goog" \
            $NODE_LOCATIONS_OPTION \
            $PRIVATE_FLAGS
    fi

    [[ $? -ne 0 ]] && echo -e "${RED}[ERROR] Fallo al crear clúster${NC}" && exit 1
fi

echo -e "${LGREEN}[✓] Clúster creado: $cluster_name${NC}"

# 3.5 Fleet Registration
echo -e "${LGREEN}Registrando en Fleet...${NC}"

# Paso 1: Obtener el número de proyecto de la flota
echo -e "${LGREEN}  • Obteniendo número de proyecto de la flota...${NC}"
fleet_project_number=$(gcloud projects describe "$fleet_id" --format="value(projectNumber)" 2>/dev/null)

if [ -z "$fleet_project_number" ]; then
    echo -e "${RED}[ERROR] No se pudo obtener el número de proyecto de la flota: $fleet_id${NC}"
    exit 1
fi

echo -e "${LCYAN}    Número de proyecto de flota: $fleet_project_number${NC}"

# Paso 2: Agregar permisos IAM al proyecto del cluster
echo -e "${LGREEN}  • Configurando permisos IAM...${NC}"
gcloud projects add-iam-policy-binding "$project_id" \
    --member="serviceAccount:service-${fleet_project_number}@gcp-sa-gkehub.iam.gserviceaccount.com" \
    --role="roles/container.serviceAgent" \
    --quiet 2>/dev/null || echo -e "${YELLOW}    [!] Permisos IAM ya configurados${NC}"

echo -e "${LCYAN}    Permisos IAM configurados${NC}"

# Paso 3: Registrar membership en la flota
echo -e "${LGREEN}  • Registrando membership en la flota...${NC}"
gke_uri="https://container.googleapis.com/v1/projects/${project_id}/locations/${region}/clusters/${cluster_name}"

gcloud container fleet memberships register "$cluster_name" \
    --project="$fleet_id" \
    --gke-uri="$gke_uri" \
    --location=global \
    --enable-workload-identity \
    --quiet 2>/dev/null || echo -e "${YELLOW}    [!] Ya registrado en la flota${NC}"

echo -e "${LGREEN}[✓] Clúster registrado en la flota: $fleet_id${NC}"

# 3.6 Cluster Hardening
echo -e "${LGREEN}Aplicando Cluster Hardening...${NC}"

echo -ne "${YELLOW}>> ¿Ejecutar hardening? (Y/N): ${NC}"
read confirm_hardening

if [[ $confirm_hardening =~ ^[Yy]$ ]]; then
    if apply_cluster_hardening; then
        echo -e "${LGREEN}[✓] Hardening completado exitosamente${NC}"
    else
        echo -e "${RED}[ERROR] Hardening falló o se completó parcialmente${NC}"
        echo -e "${YELLOW}[!] Revise el log de hardening para más detalles${NC}"
    fi
else
    echo -e "${YELLOW}[!] Hardening omitido${NC}"
fi

# 3.7 Creación de Assets
echo -e "${LGREEN}Creando Assets de Infraestructura...${NC}"

echo -ne "${YELLOW}>> ¿Desea crear los assets de infraestructura? (Y/N): ${NC}"
read create_assets_confirm

if [[ $create_assets_confirm =~ ^[Yy]$ ]]; then
    # Obtener credenciales del cluster
    echo -e "${LGREEN}  • Configurando credenciales de cluster...${NC}"
    gcloud container clusters get-credentials "$cluster_name" \
        --project="$project_id" \
        --region="$region" \
        --quiet 2>/dev/null
    
    # Crear namespace (siempre 'apps')
    echo -ne "${YELLOW}  >> ¿Crear namespace 'apps'? (Y/N): ${NC}"
    read create_namespace_confirm
    if [[ $create_namespace_confirm =~ ^[Yy]$ ]]; then
        kubectl create namespace apps 2>/dev/null || \
            echo -e "${YELLOW}    [!] Namespace apps ya existe${NC}"
        echo -e "[DONE] Namespace 'apps' creado o ya existe"
    fi
    
    # Solicitar nombres de cuentas de servicio
    echo -e "${LGREEN}  • Configurando cuentas de servicio...${NC}"
    prompt_input "Nombre de Kubernetes Service Account" "apps-gke" k8s_sa_name
    prompt_input "Nombre de IAM Service Account" "apps-sa" iam_sa_name
    
    # Crear cuenta de servicio en Kubernetes
    echo -ne "${YELLOW}  >> ¿Crear Kubernetes Service Account '${k8s_sa_name}'? (Y/N): ${NC}"
    read create_k8s_sa_confirm
    if [[ $create_k8s_sa_confirm =~ ^[Yy]$ ]]; then
        kubectl create serviceaccount "$k8s_sa_name" -n apps 2>/dev/null || \
            echo -e "${YELLOW}    [!] Service account ${k8s_sa_name} ya existe${NC}"
        echo -e "[DONE] Kubernetes Service Account '${k8s_sa_name}' creado."
    fi
    
    # Crear cuenta de servicio en IAM
    echo -ne "${YELLOW}  >> ¿Crear IAM Service Account '${iam_sa_name}'? (Y/N): ${NC}"
    read create_iam_sa_confirm
    if [[ $create_iam_sa_confirm =~ ^[Yy]$ ]]; then
        gcloud iam service-accounts create "$iam_sa_name" \
            --project="$project_id" \
            --display-name="Workload Identity" \
            --description="Workload Identity service account for GKE cluster $cluster_name" 2>/dev/null || \
            echo -e "${YELLOW}    [!] Service account ${iam_sa_name} ya existe${NC}"
        echo -e "[DONE] IAM Service Account '${iam_sa_name}' creado."
    fi
    
    # Configurar Workload Identity
    echo -ne "${YELLOW}  >> ¿Configurar Workload Identity? (Y/N): ${NC}"
    read configure_wi_confirm
    if [[ $configure_wi_confirm =~ ^[Yy]$ ]]; then
        # Crear binding entre K8s SA y IAM SA
        gcloud iam service-accounts add-iam-policy-binding "${iam_sa_name}@${project_id}.iam.gserviceaccount.com" \
            --project="$project_id" \
            --role="roles/iam.workloadIdentityUser" \
            --member="serviceAccount:${project_id}.svc.id.goog[apps/${k8s_sa_name}]" 2>/dev/null || \
            echo -e "${YELLOW}    [!] Binding ya existe${NC}"
        
        # Anotar la cuenta de servicio de Kubernetes
        kubectl annotate serviceaccount "$k8s_sa_name" \
            -n apps \
            "iam.gke.io/gcp-service-account=${iam_sa_name}@${project_id}.iam.gserviceaccount.com" \
            --overwrite 2>/dev/null
        
        echo -e "[DONE] Workload Identity configurado."
    fi
    
    echo -e "${LGREEN}[✓] Assets de infraestructura completados${NC}"
else
    echo -e "${YELLOW}[!] Creación de assets omitida${NC}"
fi

# 4. Resumen Final
echo -e "${LGREEN}========================================${NC}"
echo -e "${LGREEN}     CREACION COMPLETADA${NC}"
echo -e "${LGREEN}========================================${NC}"
echo -e "${WHITE}Proyecto:${NC} ${LCYAN}$project_id${NC}"
echo -e "${WHITE}Clúster:${NC} ${LCYAN}$cluster_name${NC}"
echo -e "${WHITE}Flota:${NC} ${LCYAN}$fleet_id${NC}"
echo -e "${WHITE}VPC:${NC} ${LCYAN}$VPC_NAME${NC}"
echo -e "${WHITE}Cloud Router:${NC} ${LCYAN}$project_id-router${NC}"
echo -e "${WHITE}Cloud NAT:${NC} ${LCYAN}$project_id-nat${NC}"

# Mostrar cuentas de servicio si fueron creadas
if [[ -n "$k8s_sa_name" ]] && [[ -n "$iam_sa_name" ]]; then
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${LGREEN} Workload Identity${NC}"
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${WHITE}Namespace:${NC} ${LCYAN}apps${NC}"
    echo -e "${WHITE}Kubernetes SA:${NC} ${LCYAN}${k8s_sa_name}${NC}"
    echo -e "${WHITE}IAM SA:${NC} ${LCYAN}${iam_sa_name}@${project_id}.iam.gserviceaccount.com${NC}"
    echo -e "${LGREEN}========================================${NC}"
fi

echo -e "${LGREEN}========================================${NC}"
echo -e " Cluster listo en región $region"
echo -e "${LGREEN}========================================${NC}"