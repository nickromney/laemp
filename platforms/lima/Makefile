.DEFAULT_GOAL := help

LIMA_INSTANCE_PREFIX ?= laemp-moodle

.PHONY: help
help:
	@echo "lima platform"
	@echo ""
	@echo "Targets:"
	@echo "  make baseline        # Install weekly Moodle 5.2 in a fresh VM (PHP 8.4, nginx, MariaDB) and run Playwright smoke checks"
	@echo "  make matrix          # Run all supported Lima cases in fresh VMs with Playwright smoke checks"
	@echo "  make status          # List Lima instances whose names start with LIMA_INSTANCE_PREFIX (default: laemp-moodle)"
	@echo "  make reset           # Force-delete the instance named LIMA_INSTANCE_PREFIX and those starting with that prefix plus a hyphen"

.PHONY: baseline
baseline:
	@./run-test.sh

.PHONY: matrix
matrix:
	@./run-matrix.sh

.PHONY: status
status:
	@limactl list | awk 'NR==1 || $$1 ~ /^$(LIMA_INSTANCE_PREFIX)/'

.PHONY: reset
reset:
	@instances="$$(limactl list -q | grep -E '^$(LIMA_INSTANCE_PREFIX)(-|$$)' || true)"; \
	if [ -z "$$instances" ]; then \
		echo "No laemp-managed Lima instances found."; \
	else \
		echo "$$instances" | while read -r instance; do \
			[ -n "$$instance" ] || continue; \
			limactl delete -f -y "$$instance"; \
		done; \
	fi
