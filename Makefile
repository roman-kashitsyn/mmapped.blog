PORT ?= 9090
DEST ?= _site
INPUT ?= .

# The engine: crates/rftex-syntax (the parser), crates/rftex-doc (the document
# model) and crates/blogware (rendering, the site and the command line).
ENGINE_CRATES := -p rftex-syntax -p rftex-doc -p blogware
BLOGWARE := cargo run --quiet --release -p blogware --

# Tree-sitter grammar for .rftex. Its toolchain (node) is deliberately kept off
# the `test` target, and therefore off the pre-commit hook.
GRAMMAR_DIR := tree-sitter-rftex

.PHONY: help
help:
	@echo "Supported targets"
	@echo "================="
	@echo "build        - build the blog engine"
	@echo "check        - report every error in the sources of the site"
	@echo "serve        - serve the blog on http://localhost:PORT, re-rendering on every request"
	@echo "render       - render the website into the DEST directory"
	@echo "test         - run the test suite of the engine"
	@echo "snapshots    - update the snapshots the tests compare with"
	@echo "format       - format the Rust code"
	@echo "clean        - remove build artifacts"
	@echo "hooks        - install the git hooks from .githooks"
	@echo "grammar      - regenerate the tree-sitter grammar parser"
	@echo "grammar-test - run the tree-sitter grammar test suite"
	@echo "parse-tree   - print the tree-sitter parse tree for FILE"
	@echo "syntax-tree  - print the Rust parser's syntax tree for FILE"

.PHONY: build
build:
	cargo build --release -p blogware

# Syntax, structure, references and the bibliography, with every error at once.
.PHONY: check
check:
	$(BLOGWARE) check --input $(INPUT)

.PHONY: serve
serve:
	$(BLOGWARE) serve --input $(INPUT) --port $(PORT)

# Checks the site first, and writes nothing if it has errors.
.PHONY: render
render:
	$(BLOGWARE) build --input $(INPUT) --output $(DEST)

.PHONY: test
test:
	cargo test $(ENGINE_CRATES)

.PHONY: snapshots
snapshots:
	UPDATE_SNAPSHOTS=1 cargo test $(ENGINE_CRATES)

.PHONY: format
format:
	cargo fmt $(ENGINE_CRATES)

.PHONY: clean
clean:
	cargo clean
	rm -rf $(DEST)

.PHONY: hooks
hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks installed from .githooks"

# Regenerate src/parser.c from grammar.js. The generated sources are committed, so
# this only needs running after editing the grammar.
.PHONY: grammar
grammar:
	cd $(GRAMMAR_DIR) && npm install && npx tree-sitter generate

# Corpus fixtures, then the fidelity gate: every real .rftex file must parse with no
# ERROR node. `cargo test` repeats the gate through the Rust bindings and also checks
# that the shipped queries compile.
.PHONY: grammar-test
grammar-test:
	cd $(GRAMMAR_DIR) && npx tree-sitter test
	@cd $(GRAMMAR_DIR) && npx tree-sitter parse --quiet --stat \
		'../index.rftex' '../posts/*.rftex' '../notes/*.rftex'
	cargo test --manifest-path $(GRAMMAR_DIR)/Cargo.toml

# Print the parse tree for a single .rftex file as a pretty-printed CST.
.PHONY: parse-tree
parse-tree:
	cd $(GRAMMAR_DIR) && npx tree-sitter parse --cst '../$(FILE)'

.PHONY: syntax-tree
syntax-tree:
	cargo run --quiet -p rftex-syntax --bin rftex-dump -- cst '$(FILE)'
