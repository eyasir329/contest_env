# contest-env developer tasks
SHELL_FILES := bin/cmanager lib/*.sh install.sh uninstall.sh tests/run.sh examples/rollout.sh

.PHONY: all lint test install uninstall

all: lint test

lint:            ## static analysis (shellcheck)
	shellcheck -x $(SHELL_FILES)

test:            ## unit tests (root enables the nft/squid checks)
	./tests/run.sh

install:         ## install on this machine
	sudo ./install.sh

uninstall:       ## remove from this machine (keeps config + snapshots)
	sudo ./uninstall.sh
