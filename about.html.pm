#lang pollen

◊(define-meta title "About")

◊section{
◊section-title["about-author"]{About the author}

◊div[#:class "container" #:itemscope "" #:itemtype "https://schema.org/Person"]{
  ◊img[#:class "portrait" #:src "/images/portrait.jpg" #:alt "author's portrait" #:itemprop "image"]{}
  ◊p{Hi there!}

  ◊p{
  My name is ◊span[#:itemprop "name"]{Roman Kashitsyn}.
  I'm a ◊span[#:itemprop "jobTitle"]{software engineer} at ◊a[#:href "https://dfinity.org"]{◊smallcaps{dfinity}}, where I have been working on orthogonal persistence, state snapshotting, state certification, state sync protocol, message routing, and much more.
  I have also co-authored a few relatively popular ◊a[#:href "https://medium.com/dfinity/software-canisters-an-evolution-of-smart-contracts-internet-computer-f1f92f1bfffb"]{canisters}: registry, ledger, internet identity backend, and certified assets canister.
  }
  ◊p{
    Before ◊span[#:class "smallcaps"]{dfinity}, I worked on large-scale distributed systems at ◊a[#:href "https://shopping.google.com/"]{Google.Shopping} and ◊a[#:href "https://yandex.ru/maps"]{Yandex.Maps}.
  }
}
}

◊section{
◊section-title["about-site"]{About this website}

◊p{
  This website is my personal blog.
  It doesn't necessary reflect the views of my employer.
  ◊br{}
  If you want to report an issue with this website or have constructive feedback, ◊a[#:href "https://github.com/roman-kashitsyn/mmapped.blog/issues/new"]{open an issue on GitHub}.
}
}

◊section{
◊section-title["mmap"]{What does "mmap" mean?}
◊p{
  "Mmap" stands for ◊a[#:href "https://en.wikipedia.org/wiki/Mmap"]{memory-mapped file I/O}.
  This ancient technology is a beam of light in the murk of the modern technological world darkened by unnecessary complexity and layers of abstractions.
  I like ◊a[#:href "https://www.man7.org/linux/man-pages/man2/mmap.2.html"]{mmap} so much that I called my blog after it.
}
}
