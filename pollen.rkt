#lang racket

(require pollen/core
         txexpr)

(provide source-code
         section
         subsection
         advice
         anchor
         circled
         circled-ref
         ol-circled)

(define (source-code attr . elems)
  (txexpr* 'div '((class "source-countainer"))
          (txexpr 'pre `((class ,(string-append "source " attr)))
                  (list (txexpr 'code '() elems)))))

(define (section anchor name)
  (txexpr* 'h2 '()
           (txexpr* 'a `((href ,(string-append "#" anchor))) name)))

(define (subsection anchor name)
  (txexpr* 'h3 '()
           (txexpr* 'a `((href ,(string-append "#" anchor))) name)))

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
