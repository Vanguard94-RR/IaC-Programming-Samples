
.PHONY: help scan scan-repo report clean install %

# Capturar argumentos adicionales
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(ARGS):;@:)

help:
	@echo "🔒 Secret Scanner - Uso Rápido"
	@echo ""
	@echo "📋 Targets:"
	@echo "  make scan <url>            Escanear archivo o repositorio"
	@echo "  make scan-repo <url>       Escanear repositorio completo"
	@echo "  make report <json> [html]  Generar reporte HTML"
	@echo "  make clean                 Limpiar archivos temporales"
	@echo "  make install               Instalar permisos"
	@echo ""
	@echo "✨ Ejemplos:"
	@echo "  make scan https://gitlab.com/grupo/repo/-/blob/branch/path/.env"
	@echo "  make scan-repo https://github.com/usuario/repo.git"
	@echo "  make report scan.json reporte.html"

scan:
	@if [ -z "$(ARGS)" ]; then \
		echo "❌ Error: Especifica una URL"; \
		echo "Uso: make scan <url>"; \
		echo "Ejemplo: make scan https://gitlab.com/grupo/repo/-/blob/branch/.env"; \
		exit 1; \
	fi
	@python3 bin/detect-secrets.py "$(ARGS)"

scan-repo:
	@if [ -z "$(ARGS)" ]; then \
		echo "❌ Error: Especifica una URL"; \
		echo "Uso: make scan-repo <url>"; \
		echo "Ejemplo: make scan-repo https://github.com/usuario/repo.git"; \
		exit 1; \
	fi
	@python3 bin/detect-secrets.py "$(ARGS)"

report:
	@if [ -z "$(ARGS)" ]; then \
		echo "❌ Error: Especifica JSON"; \
		echo "Uso: make report <json.json> [salida.html]"; \
		exit 1; \
	fi
	@python3 bin/generate-report.py $(ARGS)

clean:
	@rm -rf /tmp/secret_scan_*
	@echo "✅ Archivos temporales limpiados"

install:
	@chmod +x bin/*.py bin/*.sh
	@echo "✅ Scripts instalados"

%:
	@:
