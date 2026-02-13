#!/bin/bash

set -e

echo "Configurando proyecto CORS..."

# Leer PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    read -p "Ingrese PROJECT_ID: " PROJECT_ID
fi

# Leer BUCKET_NAME
if [ -z "$BUCKET_NAME" ]; then
    read -p "Ingrese BUCKET_NAME: " BUCKET_NAME
fi

# Leer CONFIG (opcional)
CONFIG="${CONFIG:-cors-template-open.json}"

# Guardar en .env
{
    echo "PROJECT_ID=$PROJECT_ID"
    echo "BUCKET_NAME=$BUCKET_NAME"
    echo "CONFIG=$CONFIG"
} > .env

echo "✓ Configuración guardada en .env"
echo ""
cat .env
