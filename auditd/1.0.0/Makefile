test:
	soldr-busted --exclude-tags=integration .

test-docker: DOCKER_IMAGE := debian:10
test-docker:
	@docker run --rm \
		-v $(SOLDR_MODULES):/src:ro \
		-e SOLDR_MODULES=/src \
		-w /src/auditd/1.0.0 \
		$(DOCKER_IMAGE) /src/bin/soldr-busted .

test-docker-all:
	make -s test-docker DOCKER_IMAGE=debian:10
	make -s test-docker DOCKER_IMAGE=debian:11

.PHONY: test test-docker test-docker-all
