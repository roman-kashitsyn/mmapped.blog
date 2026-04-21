PORT ?= 9090
DEST ?= _site
INPUT ?= .
BENCH_ITERATIONS ?= 10

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
BLOGWARE := _build/default/$(BLOGWARE_DIR)/bin/main.exe
BLOGWARE_BENCH := _build/default/$(BLOGWARE_DIR)/bin/bench.exe
BLOGWARE_BUILD_DIR := _build
ARTICLE_SOURCES := about.tex $(wildcard posts/*.tex)

.PHONY: help
help:
	@echo "Supported targets"
	@echo "================="
	@echo "build        - build the blog engine"
	@echo "serve        - serve the blog content on the PORT"
	@echo "render       - render the website into the DEST directory"
	@echo "test         - run the test suite"
	@echo "test-verbose - run tests with verbose output"
	@echo "utop         - launch utop with blogware libraries loaded"
	@echo "format       - format all OCaml code"
	@echo "bench-all    - benchmark all articles ($(BENCH_ITERATIONS) iterations each)"
	@echo "snapshots    - update website rendering snapshots"
	@echo "clean        - remove build artifacts"
	@echo "distclean    - remove build artifacts and installed toolchains"
	@echo "deps         - install the minimal build dependencies"
	@echo "dev-deps     - install optional documentation tooling"
	@echo "dir-locals   - generate .dir-locals.el for Emacs"

$(OPAM_STATE_ROOT)/config: $(OPAM)
	@echo "Initializing opam..."
	$(OPAM) init --root=$(OPAM_STATE_ROOT) --disable-sandboxing --bare --no-setup -y

$(OPAMSWITCH)/_opam/.opam-switch/switch-config: $(OPAM_STATE_ROOT)/config
	@echo "Creating local switch at $(OPAMSWITCH)..."
	$(OPAM) switch create $(OPAM_SWITCH_ABS) ocaml-base-compiler.5.3.0 --yes --root=$(OPAM_STATE_ROOT)

# Install the minimum toolchain required to build and test the site.
$(OPAM_ROOT)/.deps: $(OPAMSWITCH)/_opam/.opam-switch/switch-config dune-project
	@echo "Installing build dependencies..."
	$(OPAM) install $(OPAM_COMMON_ARGS) dune --yes
	@touch $@

# Optional documentation tooling. Not required for CI or deployment.
$(OPAM_ROOT)/.dev-deps: $(OPAM_ROOT)/.deps
	@echo "Installing development dependencies..."
	$(OPAM) install $(OPAM_COMMON_ARGS) merlin utop ocamlformat ocp-indent --yes
	@touch $@

.PHONY: serve
serve: build
	$(OPAM) exec $(OPAM_COMMON_ARGS) -- $(BLOGWARE) -input $(INPUT) -serve $(PORT)

.PHONY: render
render: build
	$(OPAM) exec $(OPAM_COMMON_ARGS) -- $(BLOGWARE) -input $(INPUT) -output $(DEST)

.PHONY: test
test: $(OPAM_ROOT)/.deps
	$(DUNE) test

.PHONY: test-verbose
test-verbose: $(OPAM_ROOT)/.deps
	$(DUNE) exec ./blogware/test/test_main.exe -- -verbose

.PHONY: utop
utop: $(OPAM_ROOT)/.dev-deps
	$(DUNE) utop $(BLOGWARE_DIR)/lib

.PHONY: format
format: $(OPAM_ROOT)/.dev-deps
	$(DUNE) fmt

.PHONY: snapshots
snapshots: $(OPAM_ROOT)/.deps
	UPDATE_SNAPSHOTS=1 $(DUNE) exec ./blogware/test/snapshot_test.exe

.PHONY: build
build: $(OPAM_ROOT)/.deps
	$(DUNE) build ./blogware/bin/main.exe

.PHONY: bench-all
bench-all: $(OPAM_ROOT)/.deps
	$(DUNE) exec ./blogware/bin/bench.exe -- $(BENCH_ITERATIONS) $(ARTICLE_SOURCES)

.PHONY: deps
deps: $(OPAM_ROOT)/.deps

.PHONY: dev-deps
dev-deps: $(OPAM_ROOT)/.dev-deps

SWITCH_BIN := $(OPAM_SWITCH_ABS)/_opam/bin

.PHONY: dir-locals
dir-locals: $(OPAM_ROOT)/.dev-deps
	@echo "Generating .dir-locals.el..."
	@echo '((nil' > .dir-locals.el
	@echo '  (opam-switch . "$(SWITCH_BIN)")' >> .dir-locals.el
	@echo '  (dune-command . "$(SWITCH_BIN)/dune")' >> .dir-locals.el
	@echo '  (ocamlformat-command . "$(SWITCH_BIN)/ocamlformat")' >> .dir-locals.el
	@echo '  (ocp-indent-path . "$(SWITCH_BIN)/ocp-indent")' >> .dir-locals.el
	@echo '  (utop-command . "$(abspath $(OPAM)) exec $(OPAM_COMMON_ARGS) -- dune utop . -- -emacs")))' >> .dir-locals.el

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
