GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

CONTAINER_RUNTIME ?= docker
COMPOSE_CMD ?= docker compose
BATS ?= bats

SMOKE_BATS := tests/bats/test_smoke.bats tests/bats/test_docker_ports.bats tests/bats/test_tls_preflight.bats
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
test: test-security test-smoke-bats test-cli-bats test-verify-bats ## Run fast repo-local test checks

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

.PHONY: hooks
hooks: ## Install lefthook-managed Git hooks
	@if ! command -v lefthook >/dev/null 2>&1; then \
		echo "lefthook not found in PATH." >&2; \
		exit 1; \
	fi
	@lefthook install
	@echo "Installed lefthook hooks from lefthook.yml"
	@echo "Skip one git command with: LEFTHOOK=0 git <command> or --no-verify"

.PHONY: security-setup
security-setup: ## Install local security tooling on macOS
	@./scripts/setup-security.sh

.PHONY: gitleaks
gitleaks: ## Run gitleaks secret scanner
	@gitleaks detect --verbose

.PHONY: gitleaks-protect
gitleaks-protect: ## Run gitleaks against staged files
	@gitleaks protect --staged --verbose

TRIVY_IMAGES ?= laemp-debian:13 laemp-ubuntu:24.04 laemp-prereqs-debian laemp-prereqs-ubuntu
TRIVY_SEVERITY ?= HIGH,CRITICAL
# Pinned by digest, never a tag: Trivy's release pipeline was compromised in March 2026
# (GHSA-69fq-xp46-6x23; 0.69.4-0.69.6 and `latest` were backdoored). 0.74.0 was the newest
# release past a 7-day cooldown on 2026-10-06; Docker Hub and GHCR serve the same digest and
# cosign verifies it was signed by Trivy's release workflow. Bump with scripts/trivy-candidate.sh.
TRIVY_IMAGE ?= aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969
TRIVY_SIGNER ?= ^https://github.com/aquasecurity/trivy/\.github/workflows/.+@refs/tags/v0\.74\.0$$

.PHONY: trivy-verify
trivy-verify: ## Verify the pinned Trivy image was signed by Trivy's release workflow
	@command -v cosign >/dev/null || { echo "cosign is required to verify the Trivy image (brew install cosign)."; exit 1; }
	@cosign verify "$(TRIVY_IMAGE)" \
		--certificate-identity-regexp '$(TRIVY_SIGNER)' \
		--certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null
	@echo "$(GREEN)Verified $(TRIVY_IMAGE)$(NC)"

.PHONY: trivy-scan
trivy-scan: trivy-verify ## Scan locally built laemp test images with the pinned, verified Trivy (fails on fixable HIGH/CRITICAL)
	@scan_dir="$$(mktemp -d)"; trap 'rm -rf "$$scan_dir"' EXIT; scanned=0; \
	for image in $(TRIVY_IMAGES); do \
		if ! $(CONTAINER_RUNTIME) image inspect "$$image" >/dev/null 2>&1; then \
			echo "$(YELLOW)Skipping $$image (not built locally)$(NC)"; \
			continue; \
		fi; \
		echo "$(YELLOW)Scanning $$image...$(NC)"; \
		$(CONTAINER_RUNTIME) save -o "$$scan_dir/image.tar" "$$image" || exit 1; \
		$(CONTAINER_RUNTIME) run --rm \
			-v "$$scan_dir:/scans:ro" \
			-v "$(HOME)/.cache/trivy:/root/.cache/trivy" \
			"$(TRIVY_IMAGE)" image --input /scans/image.tar \
			--severity $(TRIVY_SEVERITY) --ignore-unfixed --skip-version-check --exit-code 1 --no-progress || exit 1; \
		rm -f "$$scan_dir/image.tar"; \
		scanned=$$((scanned + 1)); \
	done; \
	if [ "$$scanned" -eq 0 ]; then echo "No laemp images found; build them with make docker-baseline first."; exit 1; fi; \
	echo "$(GREEN)Scanned $$scanned image(s): no $(TRIVY_SEVERITY) vulnerabilities$(NC)"

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
	@echo "  Use the HTTPS URL printed by compose-up, including the host port when it is not 443."

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
docker-baseline: ## Run the Docker baseline (Debian stock, PHP 8.4, nginx, MariaDB, Moodle 5.2.4/stable502)
	@$(MAKE) -C platforms/docker baseline

.PHONY: docker-matrix
docker-matrix: ## Run the supported Docker matrix
	@$(MAKE) -C platforms/docker matrix

.PHONY: slicer
slicer: ## Run the proven Slicer baseline (fresh VM, PHP 8.4, nginx, MariaDB, Moodle 5.2.4/stable502)
	@$(MAKE) -C platforms/slicervm baseline

.PHONY: slicer-matrix
slicer-matrix: ## Run the supported Slicer matrix with Playwright smoke checks
	@$(MAKE) -C platforms/slicervm matrix

.PHONY: lima
lima: ## Run the proven Lima baseline (fresh VM, PHP 8.4, nginx, MariaDB, Moodle 5.2.4/stable502)
	@$(MAKE) -C platforms/lima baseline

.PHONY: lima-matrix
lima-matrix: ## Run the supported Lima matrix with Playwright smoke checks
	@$(MAKE) -C platforms/lima matrix

.PHONY: cleanup
cleanup: ## Remove compose test containers, networks, and volumes
	@./scripts/cleanup.sh

.PHONY: test-security
test-security: ## Test installer credential privacy with synthetic fixtures
	@python3 -m unittest discover -s tests/security -p 'test_installer_*.py' -v
