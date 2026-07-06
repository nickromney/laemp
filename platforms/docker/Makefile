.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MAKEFILE_DIR)../..)
COMPOSE_CMD ?= docker compose

.PHONY: help
help:
	@echo "docker platform"
	@echo ""
	@echo "Targets:"
	@echo "  make baseline        # proven Debian/nginx/MariaDB/Moodle 5.2.1/stable502 runner"
	@echo "  make matrix          # supported Docker matrix"
	@echo "  make compose-up      # fast Debian + PostgreSQL compose path"
	@echo "  make compose-clean   # recreate the fast compose path"

.PHONY: baseline
baseline:
	@./run-baseline.sh

.PHONY: matrix
matrix:
	@./run-matrix.sh

.PHONY: compose-up
compose-up:
	@cd "$(REPO_ROOT)" && $(COMPOSE_CMD) up -d postgres-db moodle-test-debian

.PHONY: compose-clean
compose-clean:
	@cd "$(REPO_ROOT)" && $(COMPOSE_CMD) down 2>/dev/null || true
	@cd "$(REPO_ROOT)" && $(COMPOSE_CMD) up -d postgres-db moodle-test-debian
