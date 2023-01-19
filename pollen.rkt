#lang racket

(require pollen/core
         pollen/setup
         pollen/tag
         xml
         txexpr)

(provide root
	 source-code
         embed-svg
         epigraph
         section-title
         subsection-title
         sidenote
         marginnote
         math
         advice
         anchor
         circled
         circled-ref
	 code-ref
         ol-circled
         ul-arrows
         td-num
         num-cell
         quoted
         smallcaps
         numsp
         ellipsis
         mid-ellipsis
         middot
         mdash
         ndash
         ballot-x
         check
         toc)

(define (root . elements)
  (txexpr 'div '() elements))

(define (embed-svg path)
  (let [(xml (string->xexpr (file->string (build-path (current-project-root) path))))]
    ;; draw.io embeds its encoding of the diagram in the "contents" attribute.
    ;; There is no need to include this encoding into the HTML file.
    (txexpr* 'p '((class "svg")) (attr-set xml 'content ""))))

(define (source-code attr . elems)
  (txexpr* 'div '((class "source-container"))
          (txexpr 'pre `((class ,(string-append "source " attr)))
                  (list (txexpr 'code '() elems)))))

(define (local-link anchor)
  (string-append "#" anchor))

(define (section-title anchor name)
  (txexpr* 'h2 `((id ,anchor))
           (txexpr* 'a `((href ,(local-link anchor))) name)))

(define (subsection-title anchor name)
  (txexpr* 'h3 `((id ,anchor))
           (txexpr* 'a `((href ,(local-link anchor))) name)))

(define (epigraph . elems)
  (txexpr 'div '((class "epigraph")) elems))

(define (sidenote id . elems)
  (@ (txexpr 'label `((class "margin-toggle sidenote-number") (for ,id)))
     (txexpr 'input `((type "checkbox") (id ,id) (class "margin-toggle")))
     (txexpr 'span '((class "sidenote")) elems)))

(define (marginnote id . elems)
  (@ (txexpr* 'label `((class "margin-toggle") (for ,id)) (string (integer->char 8853)))
     (txexpr 'input `((type "checkbox") (id ,id) (class , "margin-toggle")))
     (txexpr 'span '((class "marginnote")) elems)))

(define (anchor name)
  (txexpr* 'a `((class "anchor") (href ,(local-link name))) #x261B))

(define (advice bookmark . elems)
  (txexpr* 'div `((class "advice") (id ,bookmark))
           (txexpr 'p '() (cons (anchor bookmark) elems))))

(define (circled-ref n)
  (txexpr* 'span '((class "circled-ref")) (circled n)))

(define (circled n)
  (string (integer->char (+ #x2460 (- n 1)))))

(define (code-ref ref . elems)
  (txexpr* 'a `((href ,ref) (class "code-ref")) (txexpr 'code '() elems)))

(define (math . elems)
  (txexpr 'span '((class "math")) elems))

(define (tok-collect-h2 elem section-elems)
  (match elem
    [(txexpr tag attrs elems)
     #:when (and (eq? tag 'h2) (assoc 'id attrs))
     (list (txexpr
            'li '((class "toc toc-level-1"))
            (append elems (list (txexpr 'ul '((class "toc toc-level-2")) (append-map tok-collect-h3 section-elems))))))]
    [_ null]
    ))

(define (tok-collect-h3 elem)
  (match elem
    [(txexpr tag attrs elems)
     #:when (and (eq? tag 'h3) (assoc 'id attrs))
     (list (txexpr 'li '((class "toc level-2")) elems))]
    [_ null]))

(define (tok-collect-sections elem)
  (match elem
    [(txexpr tag attrs elems)
     #:when (eq? tag 'section) (append-map (lambda (elem) (tok-collect-h2 elem elems)) elems)
     ]
    [(txexpr _ _ elems) (append-map tok-collect-sections elems)]
    [_ null]))

(define (toc doc)
  (txexpr 'ul '((class "toc toc-level-1")) (append-map tok-collect-sections (get-elements doc))))

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

(define (ul-arrows . elems)
  (txexpr 'ul '((class "arrows")) elems))

(define (td-num . elems)
  (txexpr 'td '((class "num-col")) elems))

(define (num-cell . elems)
  (td-num (apply math elems)))

(define (quoted . elems)
  (txexpr 'span '() (append (cons (string->symbol "ldquo") elems) (list (string->symbol "rdquo")))))

(define (smallcaps . elems)
  (txexpr 'span '((class "smallcaps")) elems))

(define (numsp) (string->symbol "numsp"))
(define (ellipsis) (string->symbol "hellip"))
(define (mid-ellipsis) (string (integer->char #x22EF)))
(define (middot) (string->symbol "middot"))
(define (mdash) (string->symbol "mdash"))
(define (ndash) (string->symbol "ndash"))
(define (ballot-x) (string (integer->char #x2718)))
(define (check) (string (integer->char #x2714)))
