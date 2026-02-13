#!/bin/bash
# Script para asociar proyecto al Shared VPC manualmente
# Uso: ./fix-shared-vpc-association.sh <PROJECT_SERVICE> <PROJECT_HOST>

# --- Colores ---
LGREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
LCYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Validar argumentos
if [[ $# -ne 2 ]]; then
    echo -e "${RED}[ERROR] Uso incorrecto${NC}"
    echo -e "Uso: ${WHITE}$0 <PROJECT_SERVICE> <PROJECT_HOST>${NC}"
    echo ""
    echo "Ejemplo:"
    echo -e "  ${LCYAN}$0 gnp-ods-pro gnp-red-data-central${NC}"
    exit 1
fi

SERVICE_PROJECT="$1"
HOST_PROJECT="$2"

echo -e "${LGREEN}========================================${NC}"
echo -e "${LGREEN}  Shared VPC Association Fix${NC}"
echo -e "${LGREEN}========================================${NC}"
echo -e "${WHITE}Proyecto Servicio:${NC} ${LCYAN}$SERVICE_PROJECT${NC}"
echo -e "${WHITE}Proyecto Host:${NC} ${LCYAN}$HOST_PROJECT${NC}"
echo ""

# Paso 1: Verificar estado actual
echo -e "${YELLOW}[1/4] Verificando estado actual...${NC}"
CURRENT_ASSOCIATION=$(gcloud compute shared-vpc associated-projects list "$HOST_PROJECT" \
    --format="value(id)" 2>/dev/null | grep "^${SERVICE_PROJECT}$" || echo "")

if [[ -n "$CURRENT_ASSOCIATION" ]]; then
    echo -e "${LGREEN}[✓] Proyecto ya está asociado${NC}"
    echo ""
    echo "Verificando configuración en el proyecto servicio..."
    XPNHOST=$(gcloud compute shared-vpc get-host-project "$SERVICE_PROJECT" 2>/dev/null || echo "")
    if [[ "$XPNHOST" == "$HOST_PROJECT" ]]; then
        echo -e "${LGREEN}[✓] Configuración correcta en ambos lados${NC}"
        exit 0
    else
        echo -e "${YELLOW}[!] Inconsistencia detectada${NC}"
        echo "Host esperado: $HOST_PROJECT"
        echo "Host actual: $XPNHOST"
    fi
else
    echo -e "${YELLOW}[!] Proyecto NO está asociado${NC}"
fi

# Paso 2: Verificar permisos del usuario actual
echo ""
echo -e "${YELLOW}[2/4] Verificando permisos...${NC}"
CURRENT_USER=$(gcloud config get-value account 2>/dev/null)
echo "Usuario actual: $CURRENT_USER"

# Intentar obtener permisos en el proyecto host
USER_ROLES=$(gcloud projects get-iam-policy "$HOST_PROJECT" \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:$CURRENT_USER" \
    --format="value(bindings.role)" 2>/dev/null | grep -E "(roles/compute.xpnAdmin|roles/owner)" || echo "")

if [[ -z "$USER_ROLES" ]]; then
    echo -e "${RED}[ERROR] No tiene permisos suficientes en el proyecto HOST${NC}"
    echo ""
    echo -e "${YELLOW}Roles requeridos:${NC}"
    echo "  • roles/compute.xpnAdmin (Shared VPC Admin)"
    echo "  • roles/owner"
    echo ""
    echo -e "${YELLOW}Solicite a un administrador que ejecute:${NC}"
    echo ""
    echo -e "${LCYAN}gcloud projects add-iam-policy-binding $HOST_PROJECT \\${NC}"
    echo -e "${LCYAN}    --member=\"user:$CURRENT_USER\" \\${NC}"
    echo -e "${LCYAN}    --role=\"roles/compute.xpnAdmin\"${NC}"
    echo ""
    exit 1
else
    echo -e "${LGREEN}[✓] Permisos adecuados: $USER_ROLES${NC}"
fi

# Paso 3: Asociar proyecto
echo ""
echo -e "${YELLOW}[3/4] Asociando proyecto al Shared VPC...${NC}"

if gcloud compute shared-vpc associated-projects add "$SERVICE_PROJECT" \
    --host-project="$HOST_PROJECT" 2>&1; then
    echo -e "${LGREEN}[✓] Proyecto asociado exitosamente${NC}"
else
    echo -e "${RED}[ERROR] Falló la asociación${NC}"
    exit 1
fi

# Paso 4: Verificar asociación
echo ""
echo -e "${YELLOW}[4/4] Verificando asociación...${NC}"
sleep 3

VERIFICATION=$(gcloud compute shared-vpc associated-projects list "$HOST_PROJECT" \
    --format="value(id)" 2>/dev/null | grep "^${SERVICE_PROJECT}$" || echo "")

if [[ -n "$VERIFICATION" ]]; then
    echo -e "${LGREEN}[✓] Asociación verificada correctamente${NC}"
    
    # Verificar desde el proyecto servicio
    XPNHOST=$(gcloud compute shared-vpc get-host-project "$SERVICE_PROJECT" 2>/dev/null || echo "")
    if [[ "$XPNHOST" == "$HOST_PROJECT" ]]; then
        echo -e "${LGREEN}[✓] Configuración completa y validada${NC}"
    else
        echo -e "${YELLOW}[!] Esperando propagación... reintente en 1 minuto${NC}"
    fi
else
    echo -e "${RED}[ERROR] No se pudo verificar la asociación${NC}"
    exit 1
fi

echo ""
echo -e "${LGREEN}========================================${NC}"
echo -e "${LGREEN}  Asociación Completada${NC}"
echo -e "${LGREEN}========================================${NC}"
echo ""
echo "Ahora puede ejecutar nuevamente el script de creación de cluster."
echo ""
