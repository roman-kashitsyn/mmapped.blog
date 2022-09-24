[![Netlify Status](https://api.netlify.com/api/v1/badges/0bdb7e4b-61b1-4538-8727-39e2512fe945/deploy-status)](https://app.netlify.com/sites/infallible-khorana-f0cacc/deploys)

# mmap(Blog)

This repository contains the full source of my personal blog hosted at https://mmapped.blog/.
The website is built with [Pollen](https://pollenpub.com/).

# Build instructions

The simplest way to build the website is to use docker.
Execute the following commands in the root repository.

```bash
docker build -t mmapped-blog .
docker run --rm mmapped-blog cat blog.tar.gz > blog.tar.gz
```

The resulting archive contains the full website contents that can be hosted statically.

# License

<a rel="license" href="http://creativecommons.org/licenses/by/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by/4.0/88x31.png" /></a><br />This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by/4.0/">Creative Commons Attribution 4.0 International License</a>.
