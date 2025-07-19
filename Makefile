PORT ?= 9090
DEST ?= site

.PHONY: help
help:
	@echo "Supported targets"
	@echo "================="
	@echo "build  - build the blog engine"
	@echo "serve  - serve the blog content on the PORT"
	@echo "render - render the website into the DEST directory"

.PHONY: serve
serve: build
	./blogware/blogware -serve localhost:$(PORT)

.PHONY: render
render: build
	./blogware/blogware -output $(DEST)

.PHONY: test
test:
	cd blogware && go test ./... && cd ..

.PHONY: lint
lint:
	cd blogware && gofmt -l . && go vet && cd ..

.PHONY: build
build:
	cd blogware && go build && cd ..
