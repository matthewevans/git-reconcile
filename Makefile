.PHONY: lint test install

lint:
	bash -n bin/git-reconcile
	bash -n test/run.sh

test:
	./test/run.sh

install:
	./install.sh
