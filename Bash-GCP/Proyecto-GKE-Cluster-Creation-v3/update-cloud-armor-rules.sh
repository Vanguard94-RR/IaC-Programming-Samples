#!/bin/bash
################################################################################
# Script: update-cloud-armor-rules.sh
# Descripción: Actualiza reglas de Cloud Armor en proyectos QA/UAT
# Autor: Juan Manuel Cortes
# Fecha: 2026-03-11
# Versión: 2.0
#
# Características:
# - Idempotente: Se puede ejecutar múltiples veces sin efectos secundarios
# - Verifica estado actual antes de aplicar cambios
# - Solo actualiza reglas que necesiten cambios
# - Crea backup automático antes de modificaciones
# - Logging detallado de todas las operaciones
################################################################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
PROJECT_ID="${1:-gnp-gmmeot-qa}"
POLICY_NAME="cve-canary"
BACKUP_FILE="cloud-armor-backup-${PROJECT_ID}-$(date +%Y%m%d_%H%M%S).json"
LOG_FILE="cloud-armor-update-${PROJECT_ID}-$(date +%Y%m%d_%H%M%S).log"

# Contadores para resumen
CHANGES_MADE=0
RULES_VERIFIED=0
RULES_DELETED=0
RULES_ALREADY_CORRECT=0

# Función de logging
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓] $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!] $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

# Función para verificar si una regla existe
rule_exists() {
    local priority=$1
    gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" &>/dev/null
    return $?
}

# Función para obtener descripción de una regla
get_rule_description() {
    local priority=$1
    gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --format="value(description)" 2>/dev/null
}

# Función para obtener IPs de una regla
get_rule_ips() {
    local priority=$1
    gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --format="csv[no-heading](match.config.srcIpRanges)" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
}

# Función para obtener acción de una regla
get_rule_action() {
    local priority=$1
    gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --format="value(action)" 2>/dev/null
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     ACTUALIZACIÓN DE REGLAS DE CLOUD ARMOR                    ║"
echo "║     Proyecto: ${PROJECT_ID}"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Validar dependencias
log_info "Validando dependencias..."
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI no está instalado"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq no está instalado"
    exit 1
fi

log_success "Dependencias validadas"

# Validar acceso al proyecto
log_info "Validando acceso al proyecto ${PROJECT_ID}..."
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    log_error "No se puede acceder al proyecto ${PROJECT_ID}"
    exit 1
fi
log_success "Acceso al proyecto validado"

# Backup de configuración actual
log_info "Creando backup de reglas actuales..."
if gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" \
    --format=json > "$BACKUP_FILE" 2>>"$LOG_FILE"; then
    log_success "Backup guardado en: ${BACKUP_FILE}"
else
    log_error "No se pudo crear backup"
    exit 1
fi

# Mostrar reglas actuales
log_info "Reglas actuales:"
gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" \
    --format="table(rules.priority,rules.action,rules.description)" 2>>"$LOG_FILE" | tee -a "$LOG_FILE"

echo ""
log_warning "IMPORTANTE: Este script modificará las reglas de Cloud Armor"
log_warning "La regla por defecto cambiará de ALLOW a DENY"
log_warning "Backup guardado en: ${BACKUP_FILE}"
echo ""
read -p "¿Desea continuar? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log_info "Operación cancelada por el usuario"
    exit 0
fi

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 1: ELIMINANDO REGLAS OBSOLETAS"
log_info "════════════════════════════════════════════════════════════════"

# Eliminar regla 93
log_info "Verificando regla 93 (VM Servicio de cuentas)..."
if rule_exists 93; then
    log_info "Eliminando regla 93..."
    if gcloud compute security-policies rules delete 93 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --quiet 2>>"$LOG_FILE"; then
        log_success "Regla 93 eliminada"
        ((RULES_DELETED++))
        ((CHANGES_MADE++))
    else
        log_error "Error al eliminar regla 93"
        exit 1
    fi
else
    log_success "Regla 93 ya no existe (OK)"
    ((RULES_ALREADY_CORRECT++))
fi
((RULES_VERIFIED++))

# Eliminar regla 95
log_info "Verificando regla 95 (F5 WAF duplicado)..."
if rule_exists 95; then
    log_info "Eliminando regla 95..."
    if gcloud compute security-policies rules delete 95 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --quiet 2>>"$LOG_FILE"; then
        log_success "Regla 95 eliminada"
        ((RULES_DELETED++))
        ((CHANGES_MADE++))
    else
        log_error "Error al eliminar regla 95"
        exit 1
    fi
else
    log_success "Regla 95 ya no existe (OK)"
    ((RULES_ALREADY_CORRECT++))
fi
((RULES_VERIFIED++))

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 2: ACTUALIZANDO REGLAS EXISTENTES"
log_info "════════════════════════════════════════════════════════════════"

# Actualizar regla 1 (CVE-Canary)
log_info "Verificando regla 1 (CVE-Canary)..."
CURRENT_DESC=$(get_rule_description 1)
EXPECTED_DESC="Default CVE Rule valuation"

if [ "$CURRENT_DESC" = "$EXPECTED_DESC" ]; then
    log_success "Regla 1 ya tiene la descripción correcta (sin cambios)"
    ((RULES_ALREADY_CORRECT++))
else
    log_info "Actualizando regla 1 (agregando descripción)..."
    if gcloud compute security-policies rules update 1 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --action=deny-403 \
        --description="$EXPECTED_DESC" \
        --expression="evaluatePreconfiguredExpr('cve-canary')" \
        2>>"$LOG_FILE"; then
        log_success "Regla 1 actualizada"
        ((CHANGES_MADE++))
    else
        log_warning "Regla 1 no pudo actualizarse (puede que ya esté correcta)"
    fi
fi
((RULES_VERIFIED++))

# Actualizar regla 90
log_info "Verificando regla 90 (NAT servicios compartidos)..."
CURRENT_IPS=$(get_rule_ips 90)
EXPECTED_IPS="35.223.194.216,34.121.174.67,35.194.4.57,35.223.189.203,35.194.34.199,34.41.162.56,35.225.224.36,34.55.188.137,34.16.70.194,104.197.124.115"
CURRENT_DESC=$(get_rule_description 90)
EXPECTED_DESC="NAT IP addressess on gnp-red-data-central for shared services (eg. Apigee, Nexus, etc.)"

# Normalizar IPs para comparación (ordenar)
CURRENT_IPS_SORTED=$(echo "$CURRENT_IPS" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
EXPECTED_IPS_SORTED=$(echo "$EXPECTED_IPS" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')

if [ "$CURRENT_IPS_SORTED" = "$EXPECTED_IPS_SORTED" ] && [ "$CURRENT_DESC" = "$EXPECTED_DESC" ]; then
    log_success "Regla 90 ya está correcta (sin cambios)"
    ((RULES_ALREADY_CORRECT++))
else
    log_info "Actualizando regla 90..."
    if gcloud compute security-policies rules update 90 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --action=allow \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="$EXPECTED_IPS" \
        2>>"$LOG_FILE"; then
        log_success "Regla 90 actualizada (10 IPs de servicios compartidos)"
        ((CHANGES_MADE++))
    else
        log_error "Falló actualización de regla 90"
        log_error "Consulte el backup: ${BACKUP_FILE}"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar regla 91
log_info "Verificando regla 91 (F5 IPs)..."
CURRENT_IPS=$(get_rule_ips 91)
EXPECTED_IPS="34.123.237.82,35.184.162.71,35.238.84.248,34.121.197.40,34.71.3.13,34.123.202.20"
CURRENT_DESC=$(get_rule_description 91)
EXPECTED_DESC="IP addressess related to F5"

CURRENT_IPS_SORTED=$(echo "$CURRENT_IPS" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
EXPECTED_IPS_SORTED=$(echo "$EXPECTED_IPS" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')

if [ "$CURRENT_IPS_SORTED" = "$EXPECTED_IPS_SORTED" ] && [ "$CURRENT_DESC" = "$EXPECTED_DESC" ]; then
    log_success "Regla 91 ya está correcta (sin cambios)"
    ((RULES_ALREADY_CORRECT++))
else
    log_info "Actualizando regla 91..."
    if gcloud compute security-policies rules update 91 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --action=allow \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="$EXPECTED_IPS" \
        2>>"$LOG_FILE"; then
        log_success "Regla 91 actualizada (6 IPs de F5)"
        ((CHANGES_MADE++))
    else
        log_error "Falló actualización de regla 91"
        log_error "Consulte el backup: ${BACKUP_FILE}"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar regla 92
log_info "Verificando regla 92 (ZSCaler)..."
CURRENT_DESC=$(get_rule_description 92)
EXPECTED_DESC="IP segment related to ZSCaler"
CURRENT_IPS=$(get_rule_ips 92)
EXPECTED_IPS="10.67.126.0/24"

if [ "$CURRENT_DESC" = "$EXPECTED_DESC" ] && [ "$CURRENT_IPS" = "$EXPECTED_IPS" ]; then
    log_success "Regla 92 ya está correcta (sin cambios)"
    ((RULES_ALREADY_CORRECT++))
else
    log_info "Actualizando regla 92..."
    if gcloud compute security-policies rules update 92 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --action=allow \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="$EXPECTED_IPS" \
        2>>"$LOG_FILE"; then
        log_success "Regla 92 actualizada (ZSCaler)"
        ((CHANGES_MADE++))
    else
        log_error "Falló actualización de regla 92"
        log_error "Consulte el backup: ${BACKUP_FILE}"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar regla default (2147483647)
log_info "Verificando regla por defecto (2147483647)..."
CURRENT_ACTION=$(get_rule_action 2147483647)
CURRENT_DESC=$(get_rule_description 2147483647)
EXPECTED_ACTION="deny(403)"
EXPECTED_DESC="The Internet"

if [ "$CURRENT_ACTION" = "$EXPECTED_ACTION" ] && [ "$CURRENT_DESC" = "$EXPECTED_DESC" ]; then
    log_success "Regla por defecto ya está correcta (sin cambios)"
    ((RULES_ALREADY_CORRECT++))
else
    log_info "Actualizando regla por defecto..."
    log_warning "CRÍTICO: Cambiando de ALLOW a DENY-403"
    if gcloud compute security-policies rules update 2147483647 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --action=deny-403 \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="*" \
        2>>"$LOG_FILE"; then
        log_success "Regla por defecto actualizada (DENY-403)"
        ((CHANGES_MADE++))
    else
        log_error "Falló actualización de regla por defecto"
        log_error "Consulte el backup: ${BACKUP_FILE}"
        exit 1
    fi
fi
((RULES_VERIFIED++))

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 3: VERIFICACIÓN FINAL"
log_info "════════════════════════════════════════════════════════════════"

# Mostrar reglas actualizadas
log_info "Configuración final:"
gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" \
    --format="table(rules.priority,rules.action,rules.description)" 2>>"$LOG_FILE" | tee -a "$LOG_FILE"

# Contar reglas
RULE_COUNT=$(gcloud compute security-policies describe "$POLICY_NAME" \
    --project="$PROJECT_ID" \
    --format=json 2>>"$LOG_FILE" | jq '[.[0].rules[]] | length')

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_success "ACTUALIZACIÓN COMPLETADA"
log_info "════════════════════════════════════════════════════════════════"
log_info "Total de reglas: ${RULE_COUNT}"
log_info "Backup: ${BACKUP_FILE}"
log_info "Log: ${LOG_FILE}"
echo ""

# Resumen de cambios
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

# Mostrar detalle solo si hubo cambios
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
   └─ Descripción: "Default CVE Rule valuation"
   └─ Expression: evaluatePreconfiguredExpr('cve-canary')

2. Priority 90: NAT servicios compartidos (allow)
   └─ Descripción: "NAT IP addressess on gnp-red-data-central..."
   └─ IPs: 10 direcciones IP de servicios compartidos

3. Priority 91: F5 IPs (allow)
   └─ Descripción: "IP addressess related to F5"
   └─ IPs: 6 direcciones IP de F5

4. Priority 92: ZSCaler (allow)
   └─ Descripción: "IP segment related to ZSCaler"
   └─ Range: 10.67.126.0/24

5. Priority 2147483647: Default Deny (deny-403)
   └─ Descripción: "The Internet"
   └─ Policy: Bloquea todo el tráfico no explícitamente permitido

⚠️  IMPORTANTE: La política implementa modelo de seguridad "deny by default".
   Solo se permite tráfico desde IPs/rangos específicos configurados.

EOF

echo ""
log_success "Script completado exitosamente"
log_info "Si necesita revertir los cambios, use el archivo: ${BACKUP_FILE}"
echo ""
