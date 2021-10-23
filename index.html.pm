#lang pollen

◊(require racket/list
          racket/string
          pollen/pagetree)

◊(define-meta title "mmap(blog)")

◊(define all-posts (children 'posts.html (get-pagetree "index.ptree")))
◊(define last-post (last all-posts))
◊(define last-post-metas (get-metas last-post))

◊h1{◊(select-from-metas 'title last-post-metas)}
◊@{◊(get-doc last-post)}
