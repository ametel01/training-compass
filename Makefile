SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap verify verify-performance verify-evidence verify-final-release test-ui run-simulator fixtures verify-migrations device-smoke verify-release evidence acceptance install-iphone personal-team-refresh install-personal-team-refresh-reminder

help:
	@echo "Training Compass Gate 0 commands"
	@echo "  make bootstrap"
	@echo "  make verify"
	@echo "  make verify-performance"
	@echo "  make verify-evidence"
	@echo "  make verify-final-release"
	@echo "  make acceptance"
	@echo "  make test-ui"
	@echo "  make run-simulator [SIMULATOR_NAME=\"iPhone 17 Pro\"]"
	@echo "  make fixtures"
	@echo "  make verify-migrations"
	@echo "  make device-smoke MILESTONE=gate-0|health-foundation|unified-events|training-insights|recovery-evidence|personal-team-refresh|healthkit-write-back"
	@echo "  make device-smoke MILESTONE=health-foundation"
	@echo "  make device-smoke MILESTONE=unified-events"
	@echo "  make device-smoke MILESTONE=training-insights"
	@echo "  make device-smoke MILESTONE=recovery-evidence"
	@echo "  make verify-release MILESTONE=gate-0|health-foundation|unified-events|training-insights|recovery-evidence|personal-team-refresh|healthkit-write-back"
	@echo "  make evidence"
	@echo "  make install-iphone"
	@echo "  make personal-team-refresh"
	@echo "  make install-personal-team-refresh-reminder"

bootstrap:
	@./scripts/bootstrap.sh

verify:
	@./scripts/verify.sh

verify-performance:
	@python3 ./scripts/check-verification-envelope.py fixtures/verification-envelope.json
	@python3 ./scripts/check-performance-protocol.py fixtures/performance-protocol.json

verify-evidence:
	@python3 ./scripts/check-evidence-index.py

verify-final-release:
	@./scripts/verify-final-release.sh

acceptance:
	@python3 ./scripts/check-acceptance.py

test-ui:
	@./scripts/test-ui.sh

run-simulator:
	@./scripts/run-simulator.sh "$(SIMULATOR_NAME)"

fixtures:
	@./scripts/generate-fixtures.sh

verify-migrations:
	@./scripts/verify-migrations.sh

device-smoke:
	@./scripts/device-smoke.sh "$(MILESTONE)"

verify-release:
	@./scripts/verify-release.sh "$(MILESTONE)"

evidence:
	@./scripts/evidence.sh

install-iphone:
	@TEAM_ID="$(TEAM_ID)" EXPORT_PATH="$(EXPORT_PATH)" ./scripts/install-connected-iphone.sh

personal-team-refresh:
	@./scripts/refresh-personal-team.sh

install-personal-team-refresh-reminder:
	@./scripts/install-personal-team-refresh-reminder.sh
