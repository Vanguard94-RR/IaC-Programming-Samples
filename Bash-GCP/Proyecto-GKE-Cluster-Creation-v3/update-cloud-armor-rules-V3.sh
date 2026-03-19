#!/bin/bash
################################################################################
# Script: update-cloud-armor-rules.sh
# Descripción: Actualiza reglas de Cloud Armor con configuración unificada
#              Aplica las mismas 5 reglas para todos los ambientes (PRO/QA/UAT)
# Autor: Juan Manuel Cortes
# Fecha: 2026-03-18
# Versión: 3.0
#
# Características:
# - Se puede ejecutar múltiples veces sin efectos secundarios
# - Verifica estado actual antes de aplicar cambios
# - Solo actualiza reglas que necesiten cambios
# - Crea backup automático antes de modificaciones
# - Logging detallado de todas las operaciones
# - Reglas unificadas para PRO, QA y UAT
################################################################################

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
PROJECT_ID="${1}"
POLICY_NAME="cve-canary"
BACKUP_FILE="cloud-armor-backup-${PROJECT_ID}-$(date +%Y%m%d_%H%M%S).json"
LOG_FILE="cloud-armor-update-${PROJECT_ID}-$(date +%Y%m%d_%H%M%S).log"

# Validar que se proporcione el proyecto
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] Debe especificar el ID del proyecto${NC}"
    echo "Uso: $0 <PROJECT_ID>"
    echo "Ejemplo: $0 gnp-gmmeot-qa"
    exit 1
fi

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

# Eliminar reglas antiguas PRO/QA (93, 95, 100 si existen)
for old_rule in 93 95 100; do
    log_info "Verificando regla ${old_rule}..."
    if rule_exists "$old_rule"; then
        log_info "Eliminando regla ${old_rule}..."
        if gcloud compute security-policies rules delete "$old_rule" \
            --security-policy="$POLICY_NAME" \
            --project="$PROJECT_ID" \
            --quiet 2>>"$LOG_FILE"; then
            log_success "Regla ${old_rule} eliminada"
            ((RULES_DELETED++))
            ((CHANGES_MADE++))
        else
            log_warning "No se pudo eliminar regla ${old_rule} (puede que no exista)"
        fi
    else
        log_success "Regla ${old_rule} ya no existe (OK)"
        ((RULES_ALREADY_CORRECT++))
    fi
    ((RULES_VERIFIED++))
done

echo ""
log_info "════════════════════════════════════════════════════════════════"
log_info "FASE 2: ACTUALIZANDO REGLAS EXISTENTES"
log_info "════════════════════════════════════════════════════════════════"

# Actualizar/Crear regla 1 (CVE-Canary)
log_info "Verificando regla 1 (CVE-Canary)..."
EXPECTED_DESC="Default CVE Rule valuation"

if rule_exists 1; then
    CURRENT_DESC=$(get_rule_description 1)
    if [ "$CURRENT_DESC" = "$EXPECTED_DESC" ]; then
        log_success "Regla 1 ya tiene la descripción correcta (sin cambios)"
        ((RULES_ALREADY_CORRECT++))
    else
        log_info "Actualizando descripción de regla 1..."
        if gcloud compute security-policies rules update 1 \
            --security-policy="$POLICY_NAME" \
            --project="$PROJECT_ID" \
            --description="$EXPECTED_DESC" \
            2>>"$LOG_FILE"; then
            log_success "Regla 1 actualizada"
            ((CHANGES_MADE++))
        else
            log_warning "Regla 1 no pudo actualizarse"
        fi
    fi
else
    log_info "Creando regla 1 (CVE-Canary)..."
    if gcloud compute security-policies rules create 1 \
        --action=deny-403 \
        --security-policy="$POLICY_NAME" \
        --description="$EXPECTED_DESC" \
        --expression="evaluatePreconfiguredExpr('cve-canary')" \
        --project="$PROJECT_ID" 2>>"$LOG_FILE"; then
        log_success "Regla 1 creada"
        ((CHANGES_MADE++))
    else
        log_error "Error al crear regla 1"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar/Crear regla 90
log_info "Verificando regla 90 (NAT servicios compartidos)..."
EXPECTED_IPS="35.223.194.216,34.121.174.67,35.194.4.57,35.223.189.203,35.194.34.199,34.41.162.56,35.225.224.36,34.55.188.137,34.16.70.194,104.197.124.115"
EXPECTED_DESC="NAT IP addressess on gnp-red-data-central for shared services (eg. Apigee, Nexus, etc.)"

if rule_exists 90; then
    CURRENT_IPS=$(get_rule_ips 90)
    CURRENT_DESC=$(get_rule_description 90)
    
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
            exit 1
        fi
    fi
else
    log_info "Creando regla 90 (NAT servicios compartidos)..."
    if gcloud compute security-policies rules create 90 \
        --action=allow \
        --security-policy="$POLICY_NAME" \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="$EXPECTED_IPS" \
        --project="$PROJECT_ID" 2>>"$LOG_FILE"; then
        log_success "Regla 90 creada"
        ((CHANGES_MADE++))
    else
        log_error "Error al crear regla 90"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar/Crear regla 91
log_info "Verificando regla 91 (F5 IPs)..."
EXPECTED_IPS="34.123.237.82,35.184.162.71,35.238.84.248,34.121.197.40,34.71.3.13,34.123.202.20"
EXPECTED_DESC="IP addressess related to F5"

if rule_exists 91; then
    CURRENT_IPS=$(get_rule_ips 91)
    CURRENT_DESC=$(get_rule_description 91)
    
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
            exit 1
        fi
    fi
else
    log_info "Creando regla 91 (F5 IPs)..."
    if gcloud compute security-policies rules create 91 \
        --action=allow \
        --security-policy="$POLICY_NAME" \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="$EXPECTED_IPS" \
        --project="$PROJECT_ID" 2>>"$LOG_FILE"; then
        log_success "Regla 91 creada"
        ((CHANGES_MADE++))
    else
        log_error "Error al crear regla 91"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar/Crear regla 92
log_info "Verificando regla 92 (ZSCaler)..."
EXPECTED_DESC="IP segment related to ZSCaler"
EXPECTED_IPS="10.67.126.0/24"

if rule_exists 92; then
    CURRENT_DESC=$(get_rule_description 92)
    CURRENT_IPS=$(get_rule_ips 92)
    
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
            exit 1
        fi
    fi
else
    log_info "Creando regla 92 (ZSCaler)..."
    if gcloud compute security-policies rules create 92 \
        --action=allow \
        --security-policy="$POLICY_NAME" \
        --description="$EXPECTED_DESC" \
        --src-ip-ranges="$EXPECTED_IPS" \
        --project="$PROJECT_ID" 2>>"$LOG_FILE"; then
        log_success "Regla 92 creada"
        ((CHANGES_MADE++))
    else
        log_error "Error al crear regla 92"
        exit 1
    fi
fi
((RULES_VERIFIED++))

# Actualizar regla default (2147483647)
# Nota: La regla por defecto NO se puede eliminar, solo actualizar
log_info "Verificando regla por defecto (2147483647)..."
EXPECTED_ACTION="deny(403)"
EXPECTED_DESC="The Internet"

if rule_exists 2147483647; then
    CURRENT_ACTION=$(get_rule_action 2147483647)
    CURRENT_DESC=$(get_rule_description 2147483647)
    
    if [ "$CURRENT_ACTION" = "$EXPECTED_ACTION" ] && [ "$CURRENT_DESC" = "$EXPECTED_DESC" ]; then
        log_success "Regla por defecto ya está correcta (sin cambios)"
        ((RULES_ALREADY_CORRECT++))
    else
        log_info "Actualizando regla por defecto..."
        if [ "$CURRENT_ACTION" != "$EXPECTED_ACTION" ]; then
            log_warning "CRÍTICO: Cambiando acción de ${CURRENT_ACTION} a DENY-403"
        fi
        if gcloud compute security-policies rules update 2147483647 \
            --security-policy="$POLICY_NAME" \
            --project="$PROJECT_ID" \
            --action=deny-403 \
            --description="$EXPECTED_DESC" \
            2>>"$LOG_FILE"; then
            log_success "Regla por defecto actualizada (DENY-403)"
            ((CHANGES_MADE++))
        else
            log_error "Falló actualización de regla por defecto"
            exit 1
        fi
    fi
else
    log_warning "Regla por defecto no existe (esto no debería ocurrir)"
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

CONFIGURACIÓN UNIFICADA (5 reglas estándar para PRO/QA/UAT):
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

⚠️  IMPORTANTE: Las mismas reglas se aplican a TODOS los ambientes.
   Modelo de seguridad "deny by default" - Solo tráfico explícito permitido.

EOF

echo ""
log_success "Script completado exitosamente"
log_info "Si necesita revertir los cambios, use el archivo: ${BACKUP_FILE}"
echo ""
