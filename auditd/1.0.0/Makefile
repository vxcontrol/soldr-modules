test:
	soldr-busted --exclude-tags=integration .

OS_LIST :=$(subst docker/Dockerfile.,,$(wildcard docker/Dockerfile.*))
test-inside-all: $(OS_LIST:%=test-inside-%)

test-inside-%: docker-build-%
	@echo Run testing inside: $*
	@docker run --rm \
		-e SOLDR_MODULES=/src \
		-v $(SOLDR_MODULES):/src:ro \
		-w /src/auditd/1.0.0 \
		test/$* /src/bin/soldr-busted .

docker-build-%: docker/Dockerfile.%
	docker build -q -t test/$* -f docker/Dockerfile.$* . >&-
