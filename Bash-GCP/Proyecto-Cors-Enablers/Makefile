.PHONY: help install setup enable verify disable validate list clean logs

help:
	@echo "GNP CORS Enablers - Secure Configuration Tool"
	@echo ""
	@echo "Comandos:"
	@echo "  make install       Instalar dependencias"
	@echo "  make setup         Configurar proyecto (asistente interactivo)"
	@echo "  make enable        Habilitar CORS en bucket con validación"
	@echo "  make verify        Verificar configuración CORS actual"
	@echo "  make validate      Validar seguridad de archivo CORS"
	@echo "  make disable       Deshabilitar CORS"
	@echo "  make list          Listar buckets en proyecto"
	@echo "  make logs          Ver logs de ejecución"
	@echo "  make clean         Limpiar logs"
	@echo ""
	@echo "Variables de entorno:"
	@echo "  PROJECT_ID         ID del proyecto GCP"
	@echo "  BUCKET_NAME        Nombre del bucket"
	@echo "  CONFIG             Archivo de configuración CORS"
	@echo ""
	@echo "Plantillas disponibles:"
	@echo "  cors-template-secure-restricted.json      (RECOMENDADO)"
	@echo "  cors-template-defense-in-depth.json       (Máxima seguridad)"
	@echo "  cors-template-uploads.json                (Para uploads)"
	@echo "  cors-template-restricted.json             (Legado)"
	@echo "  cors-template-open.json                   (⚠️  NO USAR)"

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
	@if [ ! -f .env ]; then \
		echo "ERROR: Archivo .env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./.env; \
	echo "Habilitando CORS en gs://$$BUCKET_NAME..."; \
	if [ ! -f "$$CONFIG" ]; then \
		echo "ERROR: Archivo de configuración no encontrado: $$CONFIG"; \
		exit 1; \
	fi; \
	bash scripts/enable-cors.sh --project $$PROJECT_ID --bucket $$BUCKET_NAME --config $$CONFIG

validate:
	@if [ -z "$(CONFIG_FILE)" ]; then \
		echo "Error: Especifique archivo. Uso: make validate CONFIG_FILE=cors-template-xxx.json"; \
		exit 1; \
	fi
	@echo "Validando: $(CONFIG_FILE)"
	@bash scripts/validate-cors-security.sh --config $(CONFIG_FILE) --strict

verify:
	@if [ ! -f .env ]; then \
		echo "ERROR: Archivo .env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./.env; \
	echo "Verificando configuración CORS en gs://$$BUCKET_NAME..."; \
	gcloud config set project $$PROJECT_ID 2>/dev/null; \
	gsutil cors get gs://$$BUCKET_NAME 2>&1 | tee -a cors-verify.log

disable:
	@if [ ! -f .env ]; then \
		echo "ERROR: Archivo .env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./.env; \
	echo "Deshabilitando CORS en gs://$$BUCKET_NAME..."; \
	echo '[]' | gsutil cors set - gs://$$BUCKET_NAME 2>&1 | tee -a cors-disable.log; \
	echo "✓ CORS deshabilitado exitosamente"

list:
	@if [ ! -f .env ]; then \
		echo "ERROR: Archivo .env no encontrado. Ejecute 'make setup' primero"; \
		exit 1; \
	fi
	@. ./.env; \
	echo "Listando buckets en proyecto $$PROJECT_ID..."; \
	gcloud config set project $$PROJECT_ID 2>/dev/null; \
	gcloud storage buckets list --format="table(name,location,storage_class)" 2>&1 | tee -a cors-list.log

logs:
	@echo "Logs de CORS Enablers:"
	@echo ""
	@if [ -f cors-enable.log ]; then echo "=== ENABLE ===" && tail -10 cors-enable.log && echo ""; fi
	@if [ -f cors-verify.log ]; then echo "=== VERIFY ===" && tail -10 cors-verify.log && echo ""; fi
	@if [ -f cors-disable.log ]; then echo "=== DISABLE ===" && tail -10 cors-disable.log && echo ""; fi
	@if [ -f cors-list.log ]; then echo "=== LIST ===" && tail -10 cors-list.log && echo ""; fi
	@if [ -d logs ]; then echo "Archivo de logs completos disponibles en: logs/"; fi
	@echo "Para ver logs completos: cat cors-*.log"

clean:
	@echo "Limpiando logs..."
	@rm -f cors-*.log .env
	@echo "✓ Limpieza completada"

.DEFAULT_GOAL := help
