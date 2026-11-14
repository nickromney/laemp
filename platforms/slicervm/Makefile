.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "slicervm platform"
	@echo ""
	@echo "Targets:"
	@echo "  make baseline        # Install weekly Moodle 5.2 in a fresh VM (PHP 8.4, nginx, MariaDB) and run Playwright smoke checks"
	@echo "  make matrix          # Run all supported Slicer cases in fresh VMs with Playwright smoke checks"

.PHONY: baseline
baseline:
	@./run-test.sh

.PHONY: matrix
matrix:
	@./run-matrix.sh
