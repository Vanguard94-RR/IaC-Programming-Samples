#!/bin/bash
################################################################################
# Script: rollback-cloud-armor-rules.sh
# Descripción: Restaura reglas de Cloud Armor desde backup JSON
# Autor: Juan Manuel Cortes
# Fecha: 2026-03-11
# Versión: 1.0
################################################################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
BACKUP_FILE="$1"
PROJECT_ID=""
POLICY_NAME="cve-canary"

# Función de logging
log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     ROLLBACK DE REGLAS DE CLOUD ARMOR                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Validar argumentos
if [[ -z "$BACKUP_FILE" ]]; then
    log_error "Uso: $0 <archivo-backup.json>"
    echo ""
    echo "Archivos de backup disponibles:"
    ls -lth cloud-armor-backup-*.json 2>/dev/null | head -5
    echo ""
    exit 1
fi

# Validar que existe el archivo
if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Archivo de backup no encontrado: ${BACKUP_FILE}"
    exit 1
fi

# Extraer project_id del backup
PROJECT_ID=$(jq -r '.[0].selfLink' "$BACKUP_FILE" | grep -oP 'projects/\K[^/]+')

if [[ -z "$PROJECT_ID" ]]; then
    log_error "No se pudo extraer el PROJECT_ID del backup"
    exit 1
fi

log_info "Proyecto: ${PROJECT_ID}"
log_info "Backup: ${BACKUP_FILE}"
log_warning "ADVERTENCIA: Este proceso eliminará todas las reglas actuales"
log_warning "             y restaurará las reglas desde el backup"
echo ""
read -p "¿Desea continuar? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log_info "Operación cancelada"
    exit 0
fi

echo ""
log_info "Iniciando rollback..."

# Obtener reglas actuales para eliminar
log_info "Obteniendo reglas actuales..."
CURRENT_RULES=$(gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null | jq -r '.[0].rules[].priority')

# Eliminar reglas actuales (excepto la default que se actualizará)
log_info "Eliminando reglas actuales..."
for priority in $CURRENT_RULES; do
    if [[ "$priority" != "2147483647" ]]; then
        log_info "  Eliminando regla ${priority}..."
        gcloud compute security-policies rules delete "$priority" \
            --security-policy="$POLICY_NAME" \
            --project="$PROJECT_ID" \
            --quiet 2>/dev/null && log_success "    Regla ${priority} eliminada" || log_warning "    Regla ${priority} no pudo eliminarse"
    fi
done

# Restaurar reglas desde backup
log_info "Restaurando reglas desde backup..."
BACKUP_RULES=$(jq -r '.[0].rules[] | @json' "$BACKUP_FILE")

while IFS= read -r rule; do
    PRIORITY=$(echo "$rule" | jq -r '.priority')
    ACTION=$(echo "$rule" | jq -r '.action')
    DESCRIPTION=$(echo "$rule" | jq -r '.description // ""')
    
    log_info "  Restaurando regla ${PRIORITY}..."
    
    # Verificar si es regla con expresión (CVE)
    if echo "$rule" | jq -e '.match.expr' >/dev/null 2>&1; then
        EXPRESSION=$(echo "$rule" | jq -r '.match.expr.expression')
        
        if [[ "$PRIORITY" == "2147483647" ]]; then
            # Actualizar regla default
            gcloud compute security-policies rules update "$PRIORITY" \
                --security-policy="$POLICY_NAME" \
                --project="$PROJECT_ID" \
                --action="$ACTION" \
                --description="$DESCRIPTION" \
                --expression="$EXPRESSION" 2>/dev/null && log_success "    Regla ${PRIORITY} restaurada" || log_error "    Error restaurando regla ${PRIORITY}"
        else
            # Crear regla con expresión
            gcloud compute security-policies rules create "$PRIORITY" \
                --security-policy="$POLICY_NAME" \
                --project="$PROJECT_ID" \
                --action="$ACTION" \
                --description="$DESCRIPTION" \
                --expression="$EXPRESSION" 2>/dev/null && log_success "    Regla ${PRIORITY} restaurada" || log_error "    Error restaurando regla ${PRIORITY}"
        fi
    else
        # Regla con src-ip-ranges
        SRC_IPS=$(echo "$rule" | jq -r '.match.config.srcIpRanges | join(",")')
        
        if [[ "$PRIORITY" == "2147483647" ]]; then
            # Actualizar regla default
            gcloud compute security-policies rules update "$PRIORITY" \
                --security-policy="$POLICY_NAME" \
                --project="$PROJECT_ID" \
                --action="$ACTION" \
                --description="$DESCRIPTION" \
                --src-ip-ranges="$SRC_IPS" 2>/dev/null && log_success "    Regla ${PRIORITY} restaurada" || log_error "    Error restaurando regla ${PRIORITY}"
        else
            # Crear regla con IPs
            gcloud compute security-policies rules create "$PRIORITY" \
                --security-policy="$POLICY_NAME" \
                --project="$PROJECT_ID" \
                --action="$ACTION" \
                --description="$DESCRIPTION" \
                --src-ip-ranges="$SRC_IPS" 2>/dev/null && log_success "    Regla ${PRIORITY} restaurada" || log_error "    Error restaurando regla ${PRIORITY}"
        fi
    fi
done <<< "$BACKUP_RULES"

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "Configuración restaurada:"
gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" \
    --format="table(rules.priority,rules.action,rules.description)"

echo ""
log_success "Rollback completado"
echo ""
