#!/bin/bash

set -e

echo "========================================"
echo "GNP CORS Enabler - Setup Wizard"
echo "========================================"
echo ""

# Leer PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    read -p "Ingrese PROJECT_ID: " PROJECT_ID
fi

# Validate PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: PROJECT_ID no puede estar vacío"
    exit 1
fi

# Leer BUCKET_NAME
if [ -z "$BUCKET_NAME" ]; then
    read -p "Ingrese BUCKET_NAME: " BUCKET_NAME
fi

# Validate BUCKET_NAME
if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: BUCKET_NAME no puede estar vacío"
    exit 1
fi

echo ""
echo "Seleccione plantilla de seguridad CORS:"
echo "  1) RESTRICTED (RECOMENDADO) - Whitelist de dominios específicos"
echo "  2) DEFENSE_IN_DEPTH - Máxima seguridad (solo GET)"
echo "  3) UPLOADS - Para cargas de archivos"
echo "  4) CUSTOM - Especificar archivo personalizado"
echo ""

read -p "Seleccione opción [1-4] (default: 1): " TEMPLATE_CHOICE
TEMPLATE_CHOICE=${TEMPLATE_CHOICE:-1}

case "$TEMPLATE_CHOICE" in
    1)
        CONFIG="templates/cors-template-secure-restricted.json"
        echo "✅ Seleccionado: RESTRICTED"
        ;;
    2)
        CONFIG="templates/cors-template-defense-in-depth.json"
        echo "✅ Seleccionado: DEFENSE_IN_DEPTH"
        ;;
    3)
        CONFIG="templates/cors-template-uploads.json"
        echo "✅ Seleccionado: UPLOADS"
        ;;
    4)
        read -p "Ingrese ruta del archivo CORS personalizado: " CONFIG
        if [ ! -f "$CONFIG" ]; then
            echo "ERROR: Archivo no encontrado: $CONFIG"
            exit 1
        fi
        echo "✅ Seleccionado: CUSTOM ($CONFIG)"
        ;;
    *)
        echo "ERROR: Opción inválida"
        exit 1
        ;;
esac

echo ""
echo "Validando configuración CORS..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! bash "$SCRIPT_DIR/validate-cors-security.sh" --config "$CONFIG"; then
    echo ""
    echo "⚠️  ADVERTENCIA: Validación de seguridad falló"
    read -p "¿Desea continuar de todas formas? (s/n): " CONTINUE
    if [ "$CONTINUE" != "s" ]; then
        echo "Setup cancelado"
        exit 1
    fi
fi

echo ""
echo "========================================"
echo "Resumen de Configuración"
echo "========================================"
echo "PROJECT_ID: $PROJECT_ID"
echo "BUCKET_NAME: $BUCKET_NAME"
echo "CONFIG: $CONFIG"
echo ""

# Guardar en .env
{
    echo "PROJECT_ID=$PROJECT_ID"
    echo "BUCKET_NAME=$BUCKET_NAME"
    echo "CONFIG=$CONFIG"
    echo "# Configuración creada en: $(date)"
} > config.env

echo "✅ Configuración guardada en config.env"
echo ""

# Mostrar archivos modificados
echo "Contenido de config.env:"
cat config.env
