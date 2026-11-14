.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MAKEFILE_DIR)../..)
COMPOSE_CMD ?= docker compose

.PHONY: help
help:
	@echo "docker platform"
	@echo ""
	@echo "Targets:"
	@echo "  make baseline        # Install and verify pinned Moodle 5.2.4 on stock Debian (PHP 8.4, nginx, MariaDB)"
	@echo "  make matrix          # Install and verify each supported Docker configuration"
	@echo "  make compose-up      # Start Debian Moodle and PostgreSQL in Compose, then check HTTPS and certificate expiry"
	@echo "  make compose-clean   # Stop the Compose project and recreate Debian Moodle and PostgreSQL using existing volumes"

.PHONY: baseline
baseline:
	@./run-baseline.sh

.PHONY: matrix
matrix:
	@./run-matrix.sh

.PHONY: compose-up
compose-up:
	@./compose-up.sh

.PHONY: compose-clean
compose-clean:
	@cd "$(REPO_ROOT)" && $(COMPOSE_CMD) down 2>/dev/null || true
	@cd "$(REPO_ROOT)" && $(COMPOSE_CMD) up -d postgres-db moodle-test-debian
