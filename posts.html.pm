#lang pollen

◊(require pollen/pagetree)

◊(define-meta title "All Posts")

◊ul[#:class "posts"]{
  ◊(for/splice [(e (children 'posts.html (get-pagetree "index.ptree")))]
      (let ([metas (get-metas e)])
          ◊li{
            ◊h2{◊a[#:href (symbol->string ◊|e|)]{◊(select-from-metas 'title metas)}}
          }))
}

