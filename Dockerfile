FROM golang:1.21.5-bookworm as builder

COPY . sources
RUN cd sources/blogware && go build && cd ..
RUN cd sources && blogware/blogware -output ../blog
RUN tar cf blog.tar blog && gzip blog.tar

FROM alpine:3.14.2
COPY --from=builder blog.tar.gz blog.tar.gz
