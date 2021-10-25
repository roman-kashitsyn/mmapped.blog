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
