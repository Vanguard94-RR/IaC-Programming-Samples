.PHONY: help install setup verify cleanup list batch logs clean test interactive

SCRIPT = python3 workload-identity.py

help:
	@echo "Workload Identity Manager"
	@echo ""
	@echo "Commands:"
	@echo "  make install              Verify dependencies"
	@echo "  make interactive          Run interactive setup wizard"
	@echo "  make setup                Configure workload identity"
	@echo "  make verify               Verify workload identity setup"
	@echo "  make cleanup              Remove workload identity binding"
	@echo "  make list                 List service accounts"
	@echo "  make batch                Process multiple bindings from CSV"
	@echo "  make logs                 Show operation logs"
	@echo "  make clean                Remove logs"
	@echo "  make test                 Run with dry-run mode"
	@echo ""
	@echo "Required Variables:"
	@echo "  PROJECT                   GCP project ID"
	@echo "  GCP_SA                    GCP service account (name or email)"
	@echo "  KSA                       Kubernetes service account name"
	@echo "  NAMESPACE                 Kubernetes namespace"
	@echo ""
	@echo "Optional Variables:"
	@echo "  TARGET_NS                 Target namespace (for migration)"
	@echo "  DRY_RUN                   Set to 1 for dry-run mode"
	@echo "  CSV_FILE                  CSV file for batch processing"
	@echo ""
	@echo "Examples:"
	@echo "  make setup PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps"
	@echo "  make setup PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=default TARGET_NS=apps"
	@echo "  make verify PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps"
	@echo "  make batch CSV_FILE=bindings.csv"
	@echo "  make test PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps"

install:
	@echo "Checking dependencies..."
	@command -v kubectl >/dev/null 2>&1 || (echo "ERROR: kubectl not installed" && exit 1)
	@command -v gcloud >/dev/null 2>&1 || (echo "ERROR: gcloud not installed" && exit 1)
	@command -v python3 >/dev/null 2>&1 || (echo "ERROR: python3 not installed" && exit 1)
	@echo "✓ All dependencies installed"
	@chmod +x workload-identity.py workload-identity.sh scripts/*.sh scripts/*.py 2>/dev/null || true

interactive:
	@bash workload-identity.sh

setup:
ifndef PROJECT
	$(error PROJECT is required. Usage: make setup PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
ifndef GCP_SA
	$(error GCP_SA is required. Usage: make setup PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
ifndef KSA
	$(error KSA is required. Usage: make setup PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
ifndef NAMESPACE
	$(error NAMESPACE is required. Usage: make setup PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
	@$(SCRIPT) $(if $(filter 1,$(DRY_RUN)),--dry-run) setup \
		--project $(PROJECT) \
		--gcp-sa $(GCP_SA) \
		--ksa $(KSA) \
		--namespace $(NAMESPACE) \
		$(if $(TARGET_NS),--target-namespace $(TARGET_NS))

verify:
ifndef PROJECT
	$(error PROJECT is required. Usage: make verify PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
ifndef GCP_SA
	$(error GCP_SA is required)
endif
ifndef KSA
	$(error KSA is required)
endif
ifndef NAMESPACE
	$(error NAMESPACE is required)
endif
	@$(SCRIPT) $(if $(filter 1,$(DRY_RUN)),--dry-run) verify \
		--project $(PROJECT) \
		--gcp-sa $(GCP_SA) \
		--ksa $(KSA) \
		--namespace $(NAMESPACE)

cleanup:
ifndef PROJECT
	$(error PROJECT is required. Usage: make cleanup PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
ifndef GCP_SA
	$(error GCP_SA is required)
endif
ifndef KSA
	$(error KSA is required)
endif
ifndef NAMESPACE
	$(error NAMESPACE is required)
endif
	@$(SCRIPT) $(if $(filter 1,$(DRY_RUN)),--dry-run) cleanup \
		--project $(PROJECT) \
		--gcp-sa $(GCP_SA) \
		--ksa $(KSA) \
		--namespace $(NAMESPACE)

list:
ifndef PROJECT
	$(error PROJECT is required. Usage: make list PROJECT=<id> [NAMESPACE=<ns>])
endif
	@$(SCRIPT) list --project $(PROJECT) $(if $(NAMESPACE),--namespace $(NAMESPACE))

batch:
ifndef CSV_FILE
	$(error CSV_FILE is required. Usage: make batch CSV_FILE=<file> [ACTION=setup|verify|cleanup])
endif
	@$(SCRIPT) $(if $(filter 1,$(DRY_RUN)),--dry-run) batch \
		--file $(CSV_FILE) \
		$(if $(ACTION),--action $(ACTION))

test:
ifndef PROJECT
	$(error PROJECT is required for test. Usage: make test PROJECT=<id> GCP_SA=<sa> KSA=<name> NAMESPACE=<ns>)
endif
ifndef GCP_SA
	$(error GCP_SA is required for test)
endif
ifndef KSA
	$(error KSA is required for test)
endif
ifndef NAMESPACE
	$(error NAMESPACE is required for test)
endif
	@echo "Running in DRY-RUN mode..."
	@$(SCRIPT) --dry-run setup \
		--project $(PROJECT) \
		--gcp-sa $(GCP_SA) \
		--ksa $(KSA) \
		--namespace $(NAMESPACE) \
		$(if $(TARGET_NS),--target-namespace $(TARGET_NS))

logs:
	@echo "Recent logs:"
	@if [ -f logs/workload_identity.log ]; then \
		tail -100 logs/workload_identity.log; \
	else \
		echo "No logs found"; \
	fi

clean:
	@echo "Cleaning up..."
	@rm -rf logs/*.log __pycache__
	@echo "✓ Cleanup completed"

.DEFAULT_GOAL := help
