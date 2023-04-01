#lang racket/base

(require pollen/core
         pollen/pagetree
         racket/list
         racket/string
         xml)

(define author-name  "Roman Kashitsyn")
(define feed-title   "MMapped blog")
(define feed-site    "https://mmapped.blog/")

(define (date->rfc3339 date)
  (string-append date "T00:00:00Z"))

(define all-posts (children 'posts.html (get-pagetree "index.ptree")))

(define max-updated
 (foldl
  (lambda (l r) (if (string<? l r) r l))
  ""
  (map (lambda (e) (select-from-metas 'doc-updated-date (get-metas e))) all-posts)))

(define items
  (for/list
    [(e all-posts)]
    (let ([metas (get-metas e)]
          [url (string-append* (list feed-site (symbol->string e)))])
      `(entry
         (id ,url)
         (author (name ,author-name))
         (title ,(select-from-metas 'title metas))
         (link [[href ,url]])
         (summary ,(select-from-metas 'summary metas))
         (published ,(date->rfc3339 (select-from-metas 'doc-publish-date metas)))
         (updated ,(date->rfc3339 (select-from-metas 'doc-updated-date metas)))
         ,@(for/list
           [(kw (string-split (select-from-metas 'keywords metas) ","))]
           `(category [[term ,(string-trim kw)]]))
         ))))

(define feed 
 `(feed [[xml:lang "en-us"] [xmlns "http://www.w3.org/2005/Atom"]]
   (title ,feed-title)
   (link [[rel "self"] [href ,(string-append feed-site "feed.xml")]])
   (generator [[uri "http://pollenpub.com/"]] "Pollen")
   (id ,feed-site)
   (updated ,(date->rfc3339 max-updated))
   (author (name ,author-name))
   ,@items))

(define metas (hash))
(define doc (string-append
             "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
             (xexpr->string feed)))

(provide doc metas)
