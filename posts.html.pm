#lang pollen

◊(require pollen/pagetree)

◊(define-meta title "All Posts")

◊ul[#:class "posts"]{
  ◊(for/splice [(e (children 'posts.html (get-pagetree "index.ptree")))]
      (let ([metas (get-metas e)])
          ◊li[#:itemscope "" #:itemtype "https://schema.org/CreativeWork"]{
            ◊meta[#:itemprop "keywords" #:content ◊(select-from-metas 'keywords metas)]{}
            ◊h2{◊a[#:href (symbol->string ◊|e|)]{◊span[#:itemprop "headline"]{◊(select-from-metas 'title metas)}}}
            ◊em[#:class "publish-date"]{Published: ◊span[#:itemprop "datePublished"]{◊(select-from-metas 'doc-publish-date metas)}}
            ◊div[#:itemprop "abstract"]{◊(select-from-metas 'summary metas)}
          }))
}

