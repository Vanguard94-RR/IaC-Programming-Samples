SHELL       := /bin/bash
SHELL_FILES := $(shell find bin lib test -name '*.sh' 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help lint test cluster rollback

help:
	@printf "Usage: make <target>\n\n"
	@printf "  lint   Run shellcheck on all scripts\n"
	@printf "  test   Run lint + offline smoke test\n"
	@printf "  cluster   Launch interactive cluster creation\n"
	@printf "  rollback   Rollback GKE cluster\n"

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "$(SHELL_FILES)" | tr ' ' '\n' | xargs -P4 shellcheck; \
	else \
		echo "shellcheck not found — skipping lint"; \
	fi

test: lint
	@./test/run-smoke.sh

cluster:
	@./bin/create_gke_cluster.sh

rollback:
	@./bin/rollback_gke_cluster.sh
