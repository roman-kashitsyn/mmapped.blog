#lang racket

(require pollen/core
         pollen/setup
         pollen/tag
         xml
         txexpr)

(provide source-code
         embed-svg
         epigraph
         section-title
         subsection-title
         sidenote
         marginnote
         advice
         anchor
         circled
         circled-ref
         ol-circled)

(define (embed-svg path)
  (string->xexpr (file->string (build-path (current-project-root) path))))

(define (source-code attr . elems)
  (txexpr* 'div '((class "source-container"))
          (txexpr 'pre `((class ,(string-append "source " attr)))
                  (list (txexpr 'code '() elems)))))

(define (section-title anchor name)
  (txexpr* 'h2 `((id ,anchor))
           (txexpr* 'a `((href ,(string-append "#" anchor))) name)))

(define (subsection-title anchor name)
  (txexpr* 'h3 `((id ,anchor))
           (txexpr* 'a `((href ,(string-append "#" anchor))) name)))

(define (epigraph . elems)
  (txexpr 'div `((class "epigraph")) elems))

(define (sidenote id . elems)
  (@ (txexpr 'label `((class "margin-toggle sidenote-number") (for ,id)))
     (txexpr 'input `((type "checkbox") (id ,id) (class , "margin-toggle")))
     (txexpr 'span '((class "sidenote")) elems)))

(define (marginnote id . elems)
  (@ (txexpr* 'label `((class "margin-toggle") (for ,id)) (string (integer->char 8853)))
     (txexpr 'input `((type "checkbox") (id ,id) (class , "margin-toggle")))
     (txexpr 'span '((class "marginnote")) elems)))

(define (anchor name)
  (txexpr* 'a `((class "anchor") (href ,(string-append "#" name))) #x261B))

(define (advice bookmark . elems)
  (txexpr* 'div `((class "advice") (id ,bookmark))
           (txexpr 'p '() (cons (anchor bookmark) elems))))

(define (circled-ref n)
  (txexpr* 'span '((class "circled-ref")) (circled n)))

(define (circled n)
  (string (integer->char (+ #x2460 (- n 1)))))

(define (make-li-enumerator n)
  (lambda (elem)
    (match elem
           [(txexpr tag attrs elems)
            (if (eq? tag 'li)
              (begin0
                (attr-set elem 'data-num-glyph (circled n))
                (set! n (+ n 1)))
              elem)]
           [e e])))

(define (ol-circled . elems)
  (txexpr 'ol '((class "circled")) (map (make-li-enumerator 1) elems)))
