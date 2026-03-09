.DEFAULT_GOAL := help

LIMA_INSTANCE_PREFIX ?= laemp-moodle

.PHONY: help
help:
	@echo "lima platform"
	@echo ""
	@echo "Targets:"
	@echo "  make baseline        # proven Lima baseline"
	@echo "  make matrix          # supported Lima matrix"
	@echo "  make status          # show laemp-managed Lima instances"
	@echo "  make reset           # delete laemp-managed Lima instances"

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
