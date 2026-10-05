.PHONY: test doctor dry-run panels-dry-run install-user install-hardened install-all capture restore-dry-run

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

install-hardened:
	./install.sh --hardened

install-all:
	./install.sh --all

capture:
	./scripts/capture-machine.sh

restore-dry-run:
	./scripts/restore-machine.sh --dry-run
