PORT ?= 9090
DEST ?= site

GO_VERSION := 1.25.3
GO_DIR := go

GO_OS_RAW := $(shell uname -s)
GO_ARCH_RAW := $(shell uname -m)

ifeq ($(GO_OS_RAW),Darwin)
  GO_OS := darwin
else ifeq ($(GO_OS_RAW),Linux)
  GO_OS := linux
else
  $(error Unsupported operating system $(GO_OS_RAW))
endif

ifeq ($(GO_ARCH_RAW),x86_64)
  GO_ARCH := amd64
else ifeq ($(GO_ARCH_RAW),arm64)
  GO_ARCH := arm64
else ifeq ($(GO_ARCH_RAW),aarch64)
  GO_ARCH := arm64
else
  $(error Unsupported architecture $(GO_ARCH_RAW))
endif

GO_ROOT := $(GO_DIR)/$(GO_VERSION)
GO_TARBALL := go$(GO_VERSION).$(GO_OS)-$(GO_ARCH).tar.gz
GO_URL := https://go.dev/dl/$(GO_TARBALL)
GO := $(GO_ROOT)/bin/go
GOFMT := $(GO_ROOT)/bin/gofmt
BLOGWARE := ./blogware/blogware

.PHONY: help
help:
	@echo "Supported targets"
	@echo "================="
	@echo "build  - build the blog engine"
	@echo "serve  - serve the blog content on the PORT"
	@echo "render - render the website into the DEST directory"
	@echo "clean  - remove build artifacts and installed toolchains"
	@echo "deps   - install dependencies"

.PHONY: serve
serve: build
	$(BLOGWARE) -serve localhost:$(PORT)

.PHONY: render
render: build
	$(BLOGWARE) -output $(DEST)

.PHONY: test
test: $(GO)
	cd blogware && ../$(GO) test ./...

.PHONY: lint
lint: $(GO)
	cd blogware && ../$(GOFMT) -l . && ../$(GO) vet ./...

.PHONY: build
build: $(GO)
	$(GO) build -C blogware

.PHONY: deps
deps: $(GO)

.PHONY: clean
clean:
	rm -rf $(GO_DIR) $(DEST) $(BLOGWARE)

$(GO):
	mkdir -p $(GO_ROOT)
	curl -fsSL $(GO_URL) -o $(GO_DIR)/$(GO_TARBALL)
	tar --directory $(GO_ROOT) --strip-components 1 -xzf $(GO_DIR)/$(GO_TARBALL)
	rm -f $(GO_DIR)/$(GO_TARBALL)

