test-no-root:
	$(SOLDR_MODULES)/bin/busted --exclude-tags=root .

test: test-inside-debian-10

OS_LIST := $(subst docker/Dockerfile.,,$(wildcard docker/Dockerfile.*))
test-inside-all: $(OS_LIST:%=test-inside-%)

test-inside-%: docker/Dockerfile.%
	@echo === $* ===
	@docker build --rm -t test/$* -f docker/Dockerfile.$* . >&-
	@docker run --rm \
		-e SOLDR_MODULES=/src \
		-v $(SOLDR_MODULES):/src:ro -w /src/auditd/1.0.0 \
		test/$* /src/bin/busted .
