.PHONY: install deploy help interactive interactive-bash interactive-python logs clean

help:
	@echo "Workflow Deployment - Google Cloud Workflows"
	@echo ""
	@echo "Uso:"
	@echo "  make deploy URL=<gitlab-url> NAME=<workflow-name> PROJECT=<gcp-project>"
	@echo "  make interactive          # Interfaz interactiva (Python)"
	@echo "  make interactive-python   # Interfaz interactiva (Python)"
	@echo "  make interactive-bash     # Interfaz interactiva (Bash)"
	@echo ""
	@echo "Opciones en modo CLI:"
	@echo "  LOCATION=<region>   Región GCP (auto-detecta si workflow existe)"
	@echo "  DRY_RUN=1           Simular sin desplegar"
	@echo "  SKIP_VALIDATION=1   Omitir validación"
	@echo ""
	@echo "Ejemplos:"
	@echo "  make deploy URL='https://gitlab.com/grupo/proyecto/-/blob/main/wf.yml' \\"
	@echo "              NAME=mi-workflow PROJECT=gcp-project-id"
	@echo ""
	@echo "  make interactive    # Modo interactivo (recomendado)"
	@echo ""
	@echo "Otros comandos:"
	@echo "  make install   Instalar dependencias"
	@echo "  make logs      Ver logs"
	@echo "  make clean     Limpiar logs"

install:
	@python3 -c "import yaml, requests; print('✓ Dependencias OK')" 2>/dev/null || \
	pip3 install pyyaml requests 2>/dev/null || \
	pip install pyyaml requests 2>/dev/null || \
	echo "⚠ Instala manualmente: pip install pyyaml requests"

interactive: interactive-python

interactive-python:
	@python3 workflow-deploy-interactive.py

interactive-bash:
	@bash workflow-deploy-interactive.sh

deploy:
ifndef URL
	$(error URL es requerido. Ejemplo: make deploy URL='https://gitlab.com/...' NAME=workflow PROJECT=gcp-proj)
endif
ifndef NAME
	$(error NAME es requerido)
endif
ifndef PROJECT
	$(error PROJECT es requerido)
endif
	@GITLAB_TOKEN=$$(cat ../../../../PersonalGitLabToken) python3 workflow-deploy.py \
		--url "$(URL)" \
		--name "$(NAME)" \
		--project "$(PROJECT)" \
		$(if $(LOCATION),--location "$(LOCATION)") \
		$(if $(DRY_RUN),--dry-run) \
		$(if $(SKIP_VALIDATION),--skip-validation)

logs:
	@tail -f workflow.log

clean:
	@rm -f workflow.log
	@echo "✓ Logs limpiados"

logs:
	@tail -50 workflow.log 2>/dev/null || echo "Sin logs"

clean:
	rm -f workflow.log

.DEFAULT_GOAL := help
