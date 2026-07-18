.PHONY: test doctor dry-run panels-dry-run install-user install-all

test:
	./tests/smoke.sh

doctor:
	./scripts/doctor.sh

dry-run:
	./install.sh --dry-run --all

panels-dry-run:
	./scripts/apply-panels.sh --dry-run

install-user:
	./install.sh --user --apply

install-all:
	./install.sh --all
