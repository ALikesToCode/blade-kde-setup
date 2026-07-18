.PHONY: test doctor dry-run install-user install-all

test:
	./tests/smoke.sh

doctor:
	./scripts/doctor.sh

dry-run:
	./install.sh --dry-run --all

install-user:
	./install.sh --user --apply

install-all:
	./install.sh --all
