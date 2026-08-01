PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
SCRIPT  := distro-drift

.PHONY: all install uninstall lint test check version help

all: help

help:
	@echo "make install    install to $(BINDIR)/$(SCRIPT)  (needs sudo)"
	@echo "make uninstall  remove it"
	@echo "make lint       run shellcheck"
	@echo "make test       run bats tests"
	@echo "make check      lint + test"
	@echo "make version    print the version in the script"

install:
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(SCRIPT) $(DESTDIR)$(BINDIR)/$(SCRIPT)
	@echo "Installed: $(DESTDIR)$(BINDIR)/$(SCRIPT)"
	@echo "Optional companions: sudo apt install debsums cruft-ng apt-forktracer"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(SCRIPT)
	@echo "Removed. Snapshots in /var/lib/distro-drift are left in place."

lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck not installed: sudo apt install shellcheck"; exit 1; }
	shellcheck -x $(SCRIPT)
	@echo "lint OK"

test:
	@command -v bats >/dev/null || { echo "bats not installed: sudo apt install bats"; exit 1; }
	bats tests/

check: lint test

version:
	@grep -m1 '^VERSION=' $(SCRIPT) | cut -d'"' -f2
