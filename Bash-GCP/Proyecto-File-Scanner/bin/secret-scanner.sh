#!/bin/bash
# Script wrapper para detectar secretos en repositorios
# Soporta URLs de Git y rutas locales

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mostrar uso
usage() {
    cat << 'EOF'
┌─────────────────────────────────────────────────────────────┐
│     Secret Scanner - Detector de Valores Críticos Expuestos │
└─────────────────────────────────────────────────────────────┘

Uso:
    ./secret-scanner.sh <ruta-o-url> [archivo-salida.html]

Ejemplos:
    # Escanear directorio local
    ./secret-scanner.sh /home/usuario/mi-proyecto

    # Escanear repositorio GitHub
    ./secret-scanner.sh https://github.com/usuario/repo.git

    # Escanear con salida personalizada
    ./secret-scanner.sh /ruta/proyecto reporte-seguridad.html

Soporta:
    ✓ Rutas locales de directorios
    ✓ URLs de GitHub
    ✓ URLs de GitLab
    ✓ URLs HTTPS de repositorios Git

Detecta:
    🔴 CRÍTICO: Claves privadas, credenciales de base de datos, GCP credentials
    🟠 ALTO: Tokens, JWT, API Keys
    🟡 MEDIO: Contraseñas, claves de encriptación

EOF
    exit 1
}

# Validar entrada
if [ $# -lt 1 ]; then
    usage
fi

INPUT="$1"
OUTPUT_HTML="${2:-/tmp/secret-scan-$(date +%s).html}"

# Ruta Python
PYTHON_SCRIPT="${SCRIPT_DIR}/detect-secrets.py"
REPORT_SCRIPT="${SCRIPT_DIR}/generate-report.py"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo -e "${RED}❌ Error: No se encontró $PYTHON_SCRIPT${NC}"
    exit 1
fi

if [ ! -f "$REPORT_SCRIPT" ]; then
    echo -e "${RED}❌ Error: No se encontró $REPORT_SCRIPT${NC}"
    exit 1
fi

echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│  Secret Scanner - Análisis en Progreso                     │${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "📍 Objetivo: ${YELLOW}${INPUT}${NC}"
echo -e "📊 Reporte: ${YELLOW}${OUTPUT_HTML}${NC}"
echo ""

# Escanear
echo -e "${BLUE}🔍 Iniciando escaneo...${NC}"
JSON_REPORT=$(mktemp)
python3 "$PYTHON_SCRIPT" "$INPUT" "$JSON_REPORT"

echo ""
echo -e "${BLUE}📊 Generando reporte HTML...${NC}"
python3 "$REPORT_SCRIPT" "$JSON_REPORT" "$OUTPUT_HTML"

# Limpiar
rm -f "$JSON_REPORT"

echo ""
echo -e "${GREEN}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│  ✅ Escaneo Completado Exitosamente                         │${NC}"
echo -e "${GREEN}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "📄 Reporte disponible en: ${YELLOW}${OUTPUT_HTML}${NC}"
echo ""
echo -e "💡 Próximos pasos:"
echo -e "   1. Abre el reporte HTML en tu navegador"
echo -e "   2. Revisa todos los hallazgos marcados como 🔴 CRÍTICO"
echo -e "   3. Rota o elimina los secretos expuestos inmediatamente"
echo -e "   4. Implementa un .gitignore adecuado"
echo ""

# Intentar abrir el reporte
if command -v xdg-open &> /dev/null; then
    xdg-open "$OUTPUT_HTML" 2>/dev/null || true
elif command -v open &> /dev/null; then
    open "$OUTPUT_HTML" 2>/dev/null || true
fi
