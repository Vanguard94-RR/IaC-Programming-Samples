SHELL := /bin/bash
.PHONY: lint test run

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck lib/*.sh bin/*.sh test/*.sh || true; \
	else \
		echo "shellcheck not found; skipping lint"; \
	fi

test: lint
	@echo "Running smoke test..."
	@./test/run-smoke.sh

create:
	@echo "Starting GKE Cluster Creation (interactive)"
	@./bin/create_gke_cluster.sh
