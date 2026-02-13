SHELL := /bin/bash
.PHONY: lint test run

lint:
	# Run shellcheck on project scripts (if available)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck lib/*.sh bin/*.sh test/*.sh || true; \
	else \
		echo "shellcheck not found; skipping lint"; \
	fi

test: lint
	@echo "Running smoke test..."
	@./test/run-smoke.sh

run:
	@echo "Run entrypoint (interactive)"
	@./bin/update_ingress.v2.sh
