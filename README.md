# mmap(Blog)

This repository contains the complete source of my blog hosted at https://mmapped.blog/.

# Build instructions

You’ll need [Rust](https://rustup.rs/) and [Make](https://www.gnu.org/software/make/) to build the website.
Execute the following commands in the repository root:

```shell
make render DEST=site
```

The `site` directory will contain the entire website contents that you can host statically.
If any source has an error, the build reports all of them and writes nothing.

While writing, run

```shell
make serve
```

and open http://localhost:9090: every page is rendered from the sources on disk when you load it,
and if the site has errors, the page lists them all.
`make check` reports the same errors in the terminal.

To install the git hooks (a pre-commit hook that runs `make test`), run:

```shell
make hooks
```

Run `make help` for the other targets.

# License

<a rel="license" href="http://creativecommons.org/licenses/by/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by/4.0/88x31.png" /></a><br />This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by/4.0/">Creative Commons Attribution 4.0 International License</a>.
