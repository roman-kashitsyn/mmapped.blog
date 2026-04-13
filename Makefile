PORT ?= 9090
DEST ?= _site
INPUT ?= .

OPAM_VERSION := 2.3.0
OPAM_DIR := opam
BLOGWARE_DIR := blogware

OPAM_OS_RAW := $(shell uname -s)
OPAM_ARCH_RAW := $(shell uname -m)

ifeq ($(OPAM_OS_RAW),Darwin)
  OPAM_OS := macos
else ifeq ($(OPAM_OS_RAW),Linux)
  OPAM_OS := linux
else
  $(error Unsupported operating system $(OPAM_OS_RAW))
endif

ifeq ($(OPAM_ARCH_RAW),x86_64)
  OPAM_ARCH := x86_64
else ifeq ($(OPAM_ARCH_RAW),arm64)
  OPAM_ARCH := arm64
else ifeq ($(OPAM_ARCH_RAW),aarch64)
  OPAM_ARCH := arm64
else
  $(error Unsupported architecture $(OPAM_ARCH_RAW))
endif

# Map architecture names to opam's naming convention
ifeq ($(OPAM_ARCH),arm64)
  OPAM_BIN_ARCH := arm64
else ifeq ($(OPAM_ARCH),x86_64)
  OPAM_BIN_ARCH := x86_64
endif

OPAM_ROOT := $(OPAM_DIR)/$(OPAM_VERSION)
OPAM_BIN := opam-$(OPAM_VERSION)-$(OPAM_BIN_ARCH)-$(OPAM_OS)
OPAM_URL := https://github.com/ocaml/opam/releases/download/$(OPAM_VERSION)/$(OPAM_BIN)
OPAM := $(OPAM_ROOT)/bin/opam
OPAM_STATE_ROOT := $(abspath $(OPAM_ROOT)/root)

# Use opam to locate tools (they're installed in the switch)
OPAMSWITCH := $(OPAM_ROOT)/local-switch
OPAM_SWITCH_ABS := $(abspath $(OPAMSWITCH))
OPAM_COMMON_ARGS := --root=$(OPAM_STATE_ROOT) --switch=$(OPAM_SWITCH_ABS)
DUNE := $(OPAM) exec $(OPAM_COMMON_ARGS) -- dune
BLOGWARE := $(BLOGWARE_DIR)/_build/default/bin/main.exe
BLOGWARE_BUILD_DIR := $(BLOGWARE_DIR)/_build

.PHONY: help
help:
	@echo "Supported targets"
	@echo "================="
	@echo "build        - build the blog engine"
	@echo "serve        - serve the blog content on the PORT"
	@echo "render       - render the website into the DEST directory"
	@echo "test         - run the test suite"
	@echo "test-verbose - run tests with verbose output"
	@echo "clean        - remove build artifacts"
	@echo "distclean    - remove build artifacts and installed toolchains"
	@echo "deps         - install dependencies"

$(OPAM_STATE_ROOT)/config: $(OPAM)
	@echo "Initializing opam..."
	$(OPAM) init --root=$(OPAM_STATE_ROOT) --disable-sandboxing --bare --no-setup -y

$(OPAMSWITCH)/_opam/.opam-switch/switch-config: $(OPAM_STATE_ROOT)/config
	@echo "Creating local switch at $(OPAMSWITCH)..."
	$(OPAM) switch create $(OPAM_SWITCH_ABS) ocaml-base-compiler.5.3.0 --yes --root=$(OPAM_STATE_ROOT)

# Install project dependencies
$(OPAM_ROOT)/.deps: $(OPAMSWITCH)/_opam/.opam-switch/switch-config $(BLOGWARE_DIR)/dune-project
	@echo "Installing dependencies..."
	$(OPAM) install $(OPAM_COMMON_ARGS) dune ocaml-lsp-server odoc --yes
	@touch $@

.PHONY: serve
serve: build
	$(OPAM) exec $(OPAM_COMMON_ARGS) -- $(BLOGWARE) -input $(INPUT) -serve $(PORT)

.PHONY: render
render: build
	$(OPAM) exec $(OPAM_COMMON_ARGS) -- $(BLOGWARE) -input $(INPUT) -output $(DEST)

.PHONY: test
test: $(OPAM_ROOT)/.deps
	$(DUNE) test --root=$(BLOGWARE_DIR)

.PHONY: test-verbose
test-verbose: $(OPAM_ROOT)/.deps
	$(DUNE) exec --root=$(BLOGWARE_DIR) ./test/test_main.exe -- -verbose

.PHONY: build
build: $(OPAM_ROOT)/.deps
	$(DUNE) build --root=$(BLOGWARE_DIR) ./bin/main.exe

.PHONY: deps
deps: $(OPAM_ROOT)/.deps

.PHONY: clean
clean:
	rm -rf $(BLOGWARE_BUILD_DIR) $(DEST)

.PHONY: distclean
distclean: clean
	rm -rf $(OPAM_DIR)

$(OPAM):
	@echo "Downloading opam $(OPAM_VERSION)..."
	mkdir -p $(OPAM_ROOT)/bin
	curl -fsSL $(OPAM_URL) -o $(OPAM)
	chmod +x $(OPAM)
