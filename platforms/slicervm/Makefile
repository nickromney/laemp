.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "slicervm platform"
	@echo ""
	@echo "Targets:"
	@echo "  make baseline        # proven Slicer baseline"
	@echo "  make matrix          # supported Slicer matrix"

.PHONY: baseline
baseline:
	@./run-test.sh

.PHONY: matrix
matrix:
	@./run-matrix.sh
