#!/bin/bash
# Test script para get_cluster_versions

LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

function get_cluster_versions() {
    local target_region="${1:-us-central1}"
    local target_channel="${2:-regular}"
    
    echo "[VERSIONS] Obteniendo versiones disponibles de GKE para región: $target_region"
    
    # Obtener configuración del servidor de la región
    local server_config
    server_config=$(gcloud container get-server-config \
        --region="$target_region" \
        --format="json" 2>/dev/null)
    
    if [[ -z "$server_config" ]]; then
        echo -e "${RED}[ERROR] No se pudo obtener configuración del servidor GKE${NC}"
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
            echo -e "${RED}[ERROR] Canal inválido: $target_channel${NC}"
            return 1
            ;;
    esac
    
    if [[ -z "$channel_version" ]]; then
        echo -e "${RED}[ERROR] No se pudo obtener versión para el canal: $target_channel${NC}"
        return 1
    fi
    
    echo -e "${LGREEN}[✓] Versión detectada para canal $target_channel: ${LCYAN}${channel_version}${NC}"
    echo "$channel_version"
    return 0
}

echo -e "${LGREEN}========================================${NC}"
echo -e "${LGREEN}  Test: get_cluster_versions${NC}"
echo -e "${LGREEN}========================================${NC}"
echo ""

# Test 1: Canal RAPID en us-central1
echo -e "${YELLOW}[TEST 1] Obteniendo versión RAPID en us-central1${NC}"
if version=$(get_cluster_versions "us-central1" "rapid"); then
    echo -e "${LGREEN}  ✓ PASSED: $version${NC}"
else
    echo -e "${RED}  ✗ FAILED${NC}"
fi
echo ""

# Test 2: Canal REGULAR en us-central1
echo -e "${YELLOW}[TEST 2] Obteniendo versión REGULAR en us-central1${NC}"
if version=$(get_cluster_versions "us-central1" "regular"); then
    echo -e "${LGREEN}  ✓ PASSED: $version${NC}"
else
    echo -e "${RED}  ✗ FAILED${NC}"
fi
echo ""

# Test 3: Canal STABLE en us-central1
echo -e "${YELLOW}[TEST 3] Obteniendo versión STABLE en us-central1${NC}"
if version=$(get_cluster_versions "us-central1" "stable"); then
    echo -e "${LGREEN}  ✓ PASSED: $version${NC}"
else
    echo -e "${RED}  ✗ FAILED${NC}"
fi
echo ""

# Test 4: Canal inválido (debe fallar)
echo -e "${YELLOW}[TEST 4] Prueba con canal inválido (debe fallar)${NC}"
if version=$(get_cluster_versions "us-central1" "invalid" 2>/dev/null); then
    echo -e "${RED}  ✗ FAILED: Se esperaba error${NC}"
else
    echo -e "${LGREEN}  ✓ PASSED: Falló como se esperaba${NC}"
fi
