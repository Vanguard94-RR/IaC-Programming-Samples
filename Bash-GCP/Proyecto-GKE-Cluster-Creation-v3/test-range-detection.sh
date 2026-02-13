#!/bin/bash
# Test script for detect_secondary_ranges function
# Usage: ./test-range-detection.sh <subnet-name> <host-project> <region>

# Colors
LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[0;31m'
NC='\033[0m'

# Variables
PODS_RANGE_NAME=""
SERVICES_RANGE_NAME=""

function detect_secondary_ranges() {
    local subnet_to_check="${1:-$SUBNET_NAME}"
    local host_project="${2:-$SHARED_HOST}"
    local region="${3:-us-central1}"
    
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

# Main
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <subnet-name> <host-project> <region>"
    echo ""
    echo "Example:"
    echo "  $0 gnp-cfdi-uat gnp-red-data-central us-central1"
    exit 1
fi

SUBNET_NAME="$1"
SHARED_HOST="$2"
REGION="$3"

echo -e "${LGREEN}========================================${NC}"
echo -e "${LGREEN}  Test: detect_secondary_ranges${NC}"
echo -e "${LGREEN}========================================${NC}"
echo ""

if detect_secondary_ranges "$SUBNET_NAME" "$SHARED_HOST" "$REGION"; then
    echo ""
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${LGREEN}  TEST PASSED${NC}"
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${WHITE}Variables exportadas:${NC}"
    echo -e "  PODS_RANGE_NAME=${LCYAN}$PODS_RANGE_NAME${NC}"
    echo -e "  SERVICES_RANGE_NAME=${LCYAN}$SERVICES_RANGE_NAME${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  TEST FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
