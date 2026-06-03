.PHONY: help install setup backend deploy clean validate

# Default target
help:
	@echo "Ingress Deployer — GNP Kubernetes Ingress Management"
	@echo ""
	@echo "QUICK START:"
	@echo "  make install    Install/verify all dependencies (terraform, gcloud, kubectl, yq)"
	@echo "  make backend    Initialize GCS Terraform state backend"
	@echo "  make deploy     Deploy ingress resources (runs plan then apply)"
	@echo ""
	@echo "ADVANCED:"
	@echo "  make setup      Run setup.sh directly (same as install)"
	@echo "  make validate   Check all dependencies and configurations"
	@echo "  make clean      Remove terraform plans and cache files"
	@echo ""

# Install dependencies
install: setup

setup:
	@bash scripts/setup.sh

# Initialize GCS backend (requires PROJECT_ID env var)
backend:
	@if [ -z "$$PROJECT_ID" ]; then \
		echo "ERROR: PROJECT_ID not set. Usage: PROJECT_ID=<id> make backend"; \
		exit 1; \
	fi
	@bash scripts/init-backend.sh "$$PROJECT_ID"

# Deploy ingress resources
deploy:
	@bash scripts/deploy.sh

# Validate setup without making changes
validate:
	@echo "Validating setup..."
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found" && exit 1)
	@command -v gcloud >/dev/null 2>&1 || (echo "ERROR: gcloud not found" && exit 1)
	@command -v kubectl >/dev/null 2>&1 || (echo "ERROR: kubectl not found" && exit 1)
	@command -v yq >/dev/null 2>&1 || (echo "ERROR: yq not found" && exit 1)
	@echo "✓ All dependencies present"
	@echo "✓ Run 'make help' for next steps"

# Clean temporary files
clean:
	@find . -name "*.tfplan" -delete
	@find . -name ".terraform.lock.hcl" -delete
	@find . -name "*.log" -o -name "*~" | xargs rm -f 2>/dev/null || true
	@echo "Clean completed"
