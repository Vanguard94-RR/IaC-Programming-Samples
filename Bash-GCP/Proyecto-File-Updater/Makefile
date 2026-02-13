.PHONY: help install setup promote promote-dry logs clean

help:
	@echo "GNP File Promotion"
	@echo ""
	@echo "Comandos:"
	@echo "  make install       Instalar (configurar usuario)"
	@echo "  make setup         Configurar URLs y ticket"
	@echo "  make promote       Ejecutar promoción"
	@echo "  make promote-dry   Simular sin cambios"
	@echo "  make logs          Ver logs"
	@echo "  make clean         Limpiar logs"

install:
	python3 -m pip install requests 2>/dev/null || echo "pip not available, assuming requests already installed"
	python3 setup-user-install.py

setup:
	python3 setup-config.py

promote:
	GITLAB_TOKEN=$$(cat ../PersonalGitLabToken) python3 promote-files.py --config promotion-config.json

promote-dry:
	GITLAB_TOKEN=$$(cat ../PersonalGitLabToken) python3 promote-files.py --config promotion-config.json --dry-run

logs:
	@tail -20 promotion.log 2>/dev/null || echo "No logs"

clean:
	rm -f promotion.log promotion-report.json

.DEFAULT_GOAL := help
