GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

CONTAINER_RUNTIME ?= docker
COMPOSE_CMD ?= docker compose
BATS ?= bats

SMOKE_BATS := tests/bats/test_smoke.bats
CLI_BATS := tests/bats/test_laemp.bats
INTEGRATION_BATS := tests/bats/test_integration.bats
VERIFY_BATS := tests/bats/test_verify_moodle.bats

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)laemp$(NC)"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-24s$(NC) %s\n", $$1, $$2}'

.PHONY: lint
lint: ## Run shellcheck on shell entry points
	@shellcheck -x \
		laemp.sh \
		verify-moodle.sh \
		scripts/*.sh \
		platforms/docker/*.sh \
		platforms/lima/*.sh \
		platforms/slicervm/*.sh \
		tests/docker/*.sh \
		tests/slicer/*.sh

.PHONY: test
test: test-smoke-bats test-cli-bats test-verify-bats ## Run fast repo-local test checks

.PHONY: test-smoke-bats
test-smoke-bats: ## Run fast BATS smoke tests
	@$(BATS) $(SMOKE_BATS)

.PHONY: test-cli-bats
test-cli-bats: ## Run BATS CLI and dry-run parsing tests
	@$(BATS) $(CLI_BATS)

.PHONY: test-integration-bats
test-integration-bats: ## Run full-install container BATS integration tests
	@$(BATS) $(INTEGRATION_BATS)

.PHONY: test-verify-bats
test-verify-bats: ## Run BATS tests for verify-moodle.sh
	@$(BATS) $(VERIFY_BATS)

.PHONY: test-playwright
test-playwright: ## Run Playwright tests against a running target
	@npm test

.PHONY: playwright-install
playwright-install: ## Install Playwright browser dependencies
	@npm install
	@npx playwright install chromium

.PHONY: precommit
precommit: lint ## Run pre-commit hooks on all files
	@pre-commit run --all-files

.PHONY: precommit-install
precommit-install: ## Install pre-commit hooks
	@pre-commit install

.PHONY: security-setup
security-setup: ## Install local security tooling on macOS
	@./scripts/setup-security.sh

.PHONY: gitleaks
gitleaks: ## Run gitleaks secret scanner
	@gitleaks detect --verbose

.PHONY: gitleaks-protect
gitleaks-protect: ## Run gitleaks against staged files
	@gitleaks protect --staged --verbose

.PHONY: debian
debian: ## Ensure the Debian compose container is running
	@echo "$(YELLOW)Ensuring Debian container is running...$(NC)"
	@$(MAKE) -C platforms/docker compose-up
	@echo ""
	@echo "$(GREEN)Install model$(NC)"
	@echo "  moodle-test-debian runs laemp.sh automatically on boot via systemd"
	@echo ""
	@echo "$(GREEN)Useful commands$(NC)"
	@echo "  $(COMPOSE_CMD) exec moodle-test-debian systemctl status laemp-installer --no-pager"
	@echo "  $(COMPOSE_CMD) exec moodle-test-debian tail -f /var/log/laemp/install.log"
	@echo "  $(COMPOSE_CMD) exec moodle-test-debian cat /var/lib/laemp/moodle-admin-credentials.env"
	@echo "  curl -kI https://127.0.0.1"

.PHONY: debian-clean
debian-clean: ## Recreate the Debian compose container
	@$(MAKE) -C platforms/docker compose-clean

.PHONY: ubuntu
ubuntu: ## Explain the current Ubuntu container path
	@echo "$(YELLOW)compose.yml does not currently define a moodle-test-ubuntu service.$(NC)"
	@echo "  docker build -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 ."
	@echo "  CONTAINER_RUNTIME=docker $(BATS) $(INTEGRATION_BATS)"
	@exit 1

.PHONY: ubuntu-clean
ubuntu-clean: ## Explain the current Ubuntu clean-slate container path
	@echo "$(YELLOW)compose.yml does not currently define a moodle-test-ubuntu service.$(NC)"
	@echo "  docker build --no-cache -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 ."
	@echo "  CONTAINER_RUNTIME=docker $(BATS) $(INTEGRATION_BATS)"
	@exit 1

.PHONY: docker-baseline
docker-baseline: ## Run the Docker baseline (Debian stock, PHP 8.4, nginx, MariaDB, Moodle 5.2.1/stable502)
	@$(MAKE) -C platforms/docker baseline

.PHONY: docker-matrix
docker-matrix: ## Run the supported Docker matrix
	@$(MAKE) -C platforms/docker matrix

.PHONY: slicer
slicer: ## Run the proven Slicer baseline (fresh VM, PHP 8.4, nginx, MariaDB, Moodle 5.2.1/stable502)
	@$(MAKE) -C platforms/slicervm baseline

.PHONY: slicer-matrix
slicer-matrix: ## Run the supported Slicer matrix with Playwright smoke checks
	@$(MAKE) -C platforms/slicervm matrix

.PHONY: lima
lima: ## Run the proven Lima baseline (fresh VM, PHP 8.4, nginx, MariaDB, Moodle 5.2.1/stable502)
	@$(MAKE) -C platforms/lima baseline

.PHONY: lima-matrix
lima-matrix: ## Run the supported Lima matrix with Playwright smoke checks
	@$(MAKE) -C platforms/lima matrix

.PHONY: cleanup
cleanup: ## Remove compose test containers, networks, and volumes
	@./scripts/cleanup.sh
