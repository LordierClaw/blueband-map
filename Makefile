.DEFAULT_GOAL := help

.PHONY: help doctor bootstrap test test-swift test-rpk test-lab test-ios-metadata lint clean

help:
	@echo "BlueBand Map development targets"
	@echo "  make doctor       Check the Ubuntu host without changing it"
	@echo "  make bootstrap    Pull pinned container images"
	@echo "  make test         Run every Linux-capable test suite"
	@echo "  make test-swift   Test portable Swift packages"
	@echo "  make test-rpk     Test and build the Band 10 RPK"
	@echo "  make test-lab     Test the protocol laboratory"
	@echo "  make lint         Run local static checks"
	@echo "  make clean        Remove explicit generated project paths"

doctor:
	@bash tests/scripts/doctor.test.sh

bootstrap:
	docker compose pull swift node-rpk node-lab

test: test-swift test-rpk test-lab test-ios-metadata

test-swift:
	docker compose run --rm swift swift test

test-rpk:
	docker compose run --rm node-rpk bash -lc 'npm ci && npm test'

test-lab:
	docker compose run --rm node-lab bash -lc 'npm ci && npm test'

test-ios-metadata:
	bash tools/ios/test-project-metadata.sh

lint:
	bash -n scripts/*.sh tests/scripts/*.sh tools/ios/*.sh
	bash tests/scripts/verify-no-secrets.test.sh
	scripts/verify-no-secrets.sh
	git diff --check

clean:
	docker compose run --rm node-rpk npm run clean
	rm -rf -- packages/BlueBandKit/.build apps/ios/BlueBandMap.xcodeproj tools/protocol-lab/.coverage
