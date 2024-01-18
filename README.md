[![Netlify Status](https://api.netlify.com/api/v1/badges/0bdb7e4b-61b1-4538-8727-39e2512fe945/deploy-status)](https://app.netlify.com/sites/infallible-khorana-f0cacc/deploys)

# mmap(Blog)

This repository contains the full source of my personal blog hosted at https://mmapped.blog/.

# Build instructions

You’ll need [Go](https://go.dev/) and [Make](https://www.gnu.org/software/make/) installed to build the website.
Execute the following commands in the root repository:

```bash
make render DEST=site
```

The `site` directory will contain the full website contents that you can host statically.

# License

<a rel="license" href="http://creativecommons.org/licenses/by/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by/4.0/88x31.png" /></a><br />This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by/4.0/">Creative Commons Attribution 4.0 International License</a>.
