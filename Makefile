.PHONY: build install install-dev test lint hooks

build:
	./build.sh

install:
	./install.sh

install-dev:
	./install-dev.sh

test:
	./test.sh

lint:
	./lint.sh

hooks:
	git config core.hooksPath .githooks
