.PHONY: help install setup enable verify disable list

help:
	@echo "GNP CORS Enablers - Secure Configuration Tool"
	@echo ""
	@echo "Comandos:"
	@echo "  make install       Instalar dependencias"
	@echo "  make setup         Configurar proyecto (asistente interactivo)"
	@echo "  make enable        Habilitar CORS en bucket con validación"
	@echo "  make verify        Verificar configuración CORS actual"
	@echo "  make disable       Deshabilitar CORS"
	@echo "  make list          Listar buckets en proyecto"
	@echo ""
	@echo "Variables de entorno:"
	@echo "  PROJECT_ID         ID del proyecto GCP"
	@echo "  BUCKET_NAME        Nombre del bucket"
	@echo "  CONFIG             Archivo de configuración CORS"
	@echo ""
	@echo "Plantillas disponibles (en directorio templates/):"
	@echo "  templates/cors-template-secure-restricted.json      (RECOMENDADO)"
	@echo "  templates/cors-template-defense-in-depth.json       (Máxima seguridad)"
	@echo "  templates/cors-template-uploads.json                (Para uploads)"
	@echo "  templates/cors-template-restricted.json             (Legado)"
	@echo "  templates/cors-template-open.json                   (⚠️  NO USAR)"

install:
	@echo "Verificando dependencias..."
	@command -v gcloud >/dev/null 2>&1 || (echo "ERROR: gcloud CLI no está instalado" && exit 1)
	@command -v gsutil >/dev/null 2>&1 || (echo "ERROR: gsutil no está disponible" && exit 1)
	@command -v jq >/dev/null 2>&1 || (echo "ERROR: jq no está instalado" && exit 1)
	@echo "✓ Todas las dependencias están instaladas"
	@chmod +x scripts/*.sh

setup:
	@bash scripts/setup.sh

enable:
	@if [ ! -f config.env ]; then \
		echo "ERROR: Archivo config.env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./config.env; \
	echo "Habilitando CORS en gs://$$BUCKET_NAME..."; \
	if [ ! -f "$$CONFIG" ]; then \
		echo "ERROR: Archivo de configuración no encontrado: $$CONFIG"; \
		exit 1; \
	fi; \
	bash scripts/enable-cors.sh --project $$PROJECT_ID --bucket $$BUCKET_NAME --config $$CONFIG

verify:
	@if [ ! -f config.env ]; then \
		echo "ERROR: Archivo config.env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./config.env; \
	echo "Verificando configuración CORS en gs://$$BUCKET_NAME..."; \
	gcloud config set project $$PROJECT_ID 2>/dev/null; \
	gsutil cors get gs://$$BUCKET_NAME 2>&1 | tee -a cors-verify.log

disable:
	@if [ ! -f config.env ]; then \
		echo "ERROR: Archivo config.env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./config.env; \
	echo "Deshabilitando CORS en gs://$$BUCKET_NAME..."; \
	echo '[]' | gsutil cors set - gs://$$BUCKET_NAME 2>&1 | tee -a cors-disable.log; \
	echo "✓ CORS deshabilitado exitosamente"

list:
	@if [ ! -f config.env ]; then \
		echo "ERROR: Archivo config.env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./config.env; \
	echo "Listando buckets en proyecto $$PROJECT_ID..."; \
	gcloud config set project $$PROJECT_ID 2>/dev/null; \
	gcloud storage buckets list --format="table(name,location,storage_class)" 2>&1 | tee -a cors-list.log

.DEFAULT_GOAL := help
