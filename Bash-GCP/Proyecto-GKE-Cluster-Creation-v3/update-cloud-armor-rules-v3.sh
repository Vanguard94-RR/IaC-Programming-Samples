#!/bin/bash
################################################################################
# Script: update-cloud-armor-rules.sh
# Descripción: Actualiza reglas de Cloud Armor en proyectos QA/UAT (Refactorizado)
# Autor: Juan Manuel Cortes
# Fecha: 2026-03-11
# Versión: 3.0
#
# Mejoras v3.0:
# - Código refactorizado: 443 líneas → ~250 líneas (reducción ~43%)
# - Funciones genéricas para eliminación y actualización
# - Configuración centralizada en variables
# - Mantiene idempotencia y resumen dinámico
# - Más fácil de mantener y extender
################################################################################

# ═══════════════════════════════════════════════════════════════════════
# CONFIGURACIÓN
# ═══════════════════════════════════════════════════════════════════════

# Colores
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m' NC='\033[0m'

# Variables
PROJECT_ID="${1:-gnp-gmmeot-qa}"
readonly POLICY_NAME="cve-canary"
readonly BACKUP_FILE="cloud-armor-backup-${PROJECT_ID}-$(date +%Y%m%d_%H%M%S).json"
readonly LOG_FILE="cloud-armor-update-${PROJECT_ID}-$(date +%Y%m%d_%H%M%S).log"

# Contadores
CHANGES_MADE=0 RULES_VERIFIED=0 RULES_DELETED=0 RULES_ALREADY_CORRECT=0

# Configuración de reglas esperadas
declare -A RULES_TO_DELETE=(
    [93]="VM Servicio de cuentas"
    [95]="F5 WAF duplicado"
)

# Configuración de reglas QA/UAT (Priority:Type:Action:Description:IPs)
declare -A RULES_CONFIG=(
    [1]="expression:deny-403:Default CVE Rule valuation:evaluatePreconfiguredExpr('cve-canary')"
    [90]="ip:allow:NAT IP addressess on gnp-red-data-central for shared services (eg. Apigee, Nexus, etc.):35.223.194.216,34.121.174.67,35.194.4.57,35.223.189.203,35.194.34.199,34.41.162.56,35.225.224.36,34.55.188.137,34.16.70.194,104.197.124.115"
    [91]="ip:allow:IP addressess related to F5:34.123.237.82,35.184.162.71,35.238.84.248,34.121.197.40,34.71.3.13,34.123.202.20"
    [92]="ip:allow:IP segment related to ZSCaler:10.67.126.0/24"
    [2147483647]="ip:deny-403:The Internet:*"
)

# ═══════════════════════════════════════════════════════════════════════
# FUNCIONES AUXILIARES
# ═══════════════════════════════════════════════════════════════════════

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓] $1${NC}" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[!] $1${NC}" | tee -a "$LOG_FILE"; }
log_info() { echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"; }

rule_exists() {
    gcloud compute security-policies rules describe "$1" \
        --security-policy="$POLICY_NAME" --project="$PROJECT_ID" &>/dev/null
}

get_rule_attr() {
    local priority=$1 attr=$2
    gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" --project="$PROJECT_ID" \
        --format="value($attr)" 2>/dev/null
}

get_rule_ips() {
    get_rule_attr "$1" "match.config.srcIpRanges" | tr '\n' ',' | sed 's/,$//'
}

normalize_ips() {
    echo "$1" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//'
}

# ═══════════════════════════════════════════════════════════════════════
# FUNCIONES DE GESTIÓN DE REGLAS
# ═══════════════════════════════════════════════════════════════════════

delete_rule_if_exists() {
    local priority=$1 description=$2
    ((RULES_VERIFIED++))
    
    log_info "Verificando regla ${priority} (${description})..."
    if rule_exists "$priority"; then
        log_info "Eliminando regla ${priority}..."
        if gcloud compute security-policies rules delete "$priority" \
            --security-policy="$POLICY_NAME" --project="$PROJECT_ID" \
            --quiet 2>>"$LOG_FILE"; then
            log_success "Regla ${priority} eliminada"
            ((RULES_DELETED++)) && ((CHANGES_MADE++))
        else
            log_error "Error al eliminar regla ${priority}"
            return 1
        fi
    else
        log_success "Regla ${priority} ya no existe (OK)"
        ((RULES_ALREADY_CORRECT++))
    fi
}

update_rule() {
    local priority=$1
    IFS=':' read -r rule_type action description ips <<< "${RULES_CONFIG[$priority]}"
    
    ((RULES_VERIFIED++))
    log_info "Verificando regla ${priority} (${description:0:50}...)..."
    
    # Obtener estado actual
    local current_desc=$(get_rule_attr "$priority" "description")
    local current_action=$(get_rule_attr "$priority" "action")
    
    # Verificar si necesita actualización
    local needs_update=false
    
    if [ "$current_desc" != "$description" ] || [ "$current_action" != "$action" ]; then
        needs_update=true
    fi
    
    # Para reglas IP, verificar también las IPs
    if [ "$rule_type" = "ip" ]; then
        local current_ips=$(get_rule_ips "$priority")
        local current_sorted=$(normalize_ips "$current_ips")
        local expected_sorted=$(normalize_ips "$ips")
        
        if [ "$current_sorted" != "$expected_sorted" ]; then
            needs_update=true
        fi
    fi
    
    # Aplicar actualización si es necesaria
    if [ "$needs_update" = true ]; then
        log_info "Actualizando regla ${priority}..."
        
        local cmd="gcloud compute security-policies rules update ${priority} \
            --security-policy=\"$POLICY_NAME\" --project=\"$PROJECT_ID\" \
            --action=$action --description=\"$description\""
        
        if [ "$rule_type" = "expression" ]; then
            cmd="$cmd --expression=\"$ips\""
        else
            cmd="$cmd --src-ip-ranges=\"$ips\""
        fi
        
        if eval "$cmd 2>>\"$LOG_FILE\""; then
            log_success "Regla ${priority} actualizada"
            ((CHANGES_MADE++))
        else
            log_error "Falló actualización de regla ${priority}"
            log_error "Consulte el backup: ${BACKUP_FILE}"
            return 1
        fi
    else
        log_success "Regla ${priority} ya está correcta (sin cambios)"
        ((RULES_ALREADY_CORRECT++))
    fi
}

# ═══════════════════════════════════════════════════════════════════════
# VALIDACIÓN INICIAL
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     ACTUALIZACIÓN DE REGLAS DE CLOUD ARMOR v3.0               ║"
echo "║     Proyecto: ${PROJECT_ID}"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Validando dependencias..."
for cmd in gcloud jq; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "${cmd} no está instalado"
        exit 1
    fi
done
log_success "Dependencias validadas"

log_info "Validando acceso al proyecto ${PROJECT_ID}..."
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    log_error "No se puede acceder al proyecto ${PROJECT_ID}"
    exit 1
fi
log_success "Acceso al proyecto validado"

log_info "Creando backup de reglas actuales..."
if gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" --format=json > "$BACKUP_FILE" 2>>"$LOG_FILE"; then
    log_success "Backup guardado en: ${BACKUP_FILE}"
else
    log_error "No se pudo crear backup"
    exit 1
fi

log_info "Reglas actuales:"
gcloud compute security-policies describe "$POLICY_NAME" --project="$PROJECT_ID" \
    --format="table(rules.priority,rules.action,rules.description)" 2>>"$LOG_FILE" | tee -a "$LOG_FILE"

echo ""
log_warning "IMPORTANTE: Este script modificará las reglas de Cloud Armor"
log_warning "Backup guardado en: ${BACKUP_FILE}"
echo ""
read -p "¿Desea continuar? (yes/no): " confirm
[ "$confirm" != "yes" ] && { log_info "Operación cancelada por el usuario"; exit 0; }

# ═══════════════════════════════════════════════════════════════════════
# FASE 1: ELIMINACIÓN DE REGLAS OBSOLETAS
# ═══════════════════════════════════════════════════════════════════════

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 1: ELIMINANDO REGLAS OBSOLETAS"
log_info "════════════════════════════════════════════════════════════════"

for priority in "${!RULES_TO_DELETE[@]}"; do
    delete_rule_if_exists "$priority" "${RULES_TO_DELETE[$priority]}" || exit 1
done

# ═══════════════════════════════════════════════════════════════════════
# FASE 2: ACTUALIZACIÓN DE REGLAS
# ═══════════════════════════════════════════════════════════════════════

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 2: ACTUALIZANDO REGLAS EXISTENTES"
log_info "════════════════════════════════════════════════════════════════"

for priority in 1 90 91 92 2147483647; do
    update_rule "$priority" || exit 1
done

# ═══════════════════════════════════════════════════════════════════════
# FASE 3: VERIFICACIÓN Y RESUMEN
# ═══════════════════════════════════════════════════════════════════════

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 3: VERIFICACIÓN FINAL"
log_info "════════════════════════════════════════════════════════════════"

log_info "Configuración final:"
gcloud compute security-policies describe "$POLICY_NAME" --project="$PROJECT_ID" \
    --format="table(rules.priority,rules.action,rules.description)" 2>>"$LOG_FILE" | tee -a "$LOG_FILE"

RULE_COUNT=$(gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" --format=json 2>>"$LOG_FILE" | jq '[.[0].rules[]] | length')

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_success "ACTUALIZACIÓN COMPLETADA"
log_info "════════════════════════════════════════════════════════════════"
log_info "Total de reglas: ${RULE_COUNT}"
log_info "Backup: ${BACKUP_FILE}"
log_info "Log: ${LOG_FILE}"
echo ""

# Resumen dinámico
cat << EOF | tee -a "$LOG_FILE"

╔════════════════════════════════════════════════════════════════╗
║                   RESUMEN DE EJECUCIÓN                         ║
╚════════════════════════════════════════════════════════════════╝

ESTADÍSTICAS:
  → Total de reglas verificadas: ${RULES_VERIFIED}
  → Reglas ya correctas (sin cambios): ${RULES_ALREADY_CORRECT}
  → Reglas eliminadas: ${RULES_DELETED}
  → Reglas actualizadas/creadas: $((CHANGES_MADE - RULES_DELETED))
  → Total de cambios aplicados: ${CHANGES_MADE}

EOF

if [ $CHANGES_MADE -gt 0 ]; then
    cat << EOF | tee -a "$LOG_FILE"
CAMBIOS APLICADOS EN ESTA EJECUCIÓN:
$([ $RULES_DELETED -gt 0 ] && echo "  ✓ Reglas obsoletas eliminadas: ${RULES_DELETED}")
$([ $((CHANGES_MADE - RULES_DELETED)) -gt 0 ] && echo "  ✓ Reglas actualizadas: $((CHANGES_MADE - RULES_DELETED))")

EOF
else
    cat << EOF | tee -a "$LOG_FILE"
✓ SISTEMA YA CONFIGURADO CORRECTAMENTE
  No se requirieron cambios. Todas las reglas están alineadas
  con el estándar gnp-covid-qa.

EOF
fi

cat << EOF | tee -a "$LOG_FILE"
═══════════════════════════════════════════════════════════════

CONFIGURACIÓN FINAL (5 reglas esperadas):
1. Priority 1: CVE-Canary (deny-403)
2. Priority 90: NAT servicios compartidos (allow - 10 IPs)
3. Priority 91: F5 IPs (allow - 6 IPs)
4. Priority 92: ZSCaler (allow - 10.67.126.0/24)
5. Priority 2147483647: Default Deny (deny-403)

⚠️  IMPORTANTE: La política implementa modelo de seguridad "deny by default".
   Solo se permite tráfico desde IPs/rangos específicos configurados.

EOF

log_success "Script completado exitosamente"
log_info "Si necesita revertir los cambios, use el archivo: ${BACKUP_FILE}"
echo ""
