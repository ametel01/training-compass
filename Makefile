SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap verify test-ui fixtures verify-migrations device-smoke verify-release evidence

help:
	@echo "Training Compass Gate 0 commands"
	@echo "  make bootstrap"
	@echo "  make verify"
	@echo "  make test-ui"
	@echo "  make fixtures"
	@echo "  make verify-migrations"
	@echo "  make device-smoke MILESTONE=gate-0"
	@echo "  make verify-release"
	@echo "  make evidence"

bootstrap:
	@./scripts/bootstrap.sh

verify:
	@./scripts/verify.sh

test-ui:
	@./scripts/test-ui.sh

fixtures:
	@./scripts/generate-fixtures.sh

verify-migrations:
	@./scripts/verify-migrations.sh

device-smoke:
	@./scripts/device-smoke.sh "$(MILESTONE)"

verify-release:
	@./scripts/verify-release.sh

evidence:
	@./scripts/evidence.sh
