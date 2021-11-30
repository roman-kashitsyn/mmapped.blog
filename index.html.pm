#lang pollen

◊(require racket/list
          racket/string
          pollen/pagetree)

◊(define-meta title "mmap(blog)")

◊(define page-tree (get-pagetree "index.ptree"))
◊(define all-posts (children 'posts.html page-tree))
◊(define last-post (first all-posts))
◊(define last-post-metas (get-metas last-post))
◊(define prev-page (next last-post page-tree))

◊h1{◊a[#:href ◊(symbol->string last-post)]{◊(select-from-metas 'title last-post-metas)}}
◊@{◊(get-doc last-post)}

◊when/splice[(and prev-page (member prev-page all-posts))]{
  ◊div[#:id "next-prev-nav"]{
    ◊div[#:id "older"]{◊a[#:href (symbol->string prev-page)]{◊(select-from-metas 'title prev-page)→ }}
  }
}
