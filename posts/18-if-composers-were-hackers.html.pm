#lang pollen

◊(define-meta title "If composers were hackers")
◊(define-meta keywords "programming,glasperlenspiel")
◊(define-meta summary "What programming language would J.S. Bach use?")
◊(define-meta doc-publish-date "2023-04-01")
◊(define-meta doc-updated-date "2023-04-01")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  Music is my first true love◊sidenote["zero-love"]{Computer games are my zeroeth true love.}.
  The first time I got my hands on an old untuned guitar, I didn't want to put it down.
  I worked on an illegal summer job to buy my first instrument and pay for a teacher, and since then, music has been a constant source of joy in my life.
  Picking a CS degree at a university over a musical college education was a hard choice for me.
}
◊p{
  I can't help but look at the world through my musical obsession.
  There are many deep similarities between music and computing but we won't explore them in this article.
  Instead, I will focus on a silly and subjective question: ◊quoted{If my favorite composers decided to write some code, which language would they pick?}.
}
}

◊section{
◊section-title["bach"]{Johan Sebastian Bach}
◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Johann_Sebastian_Bach"]{Johan Sebastian Bach} is the most talented and prolific musician in history.
}
◊p{
  Bach would love the ◊a[#:href "https://aplwiki.com/"]{APL} programming language:
}
◊ul[#:class "arrows"]{
  ◊li{
    Like a well-written APL program, Bach's music is ◊em{dense}.
    He achieves immense expressive power with a few well-chosen constructs.
  }
  ◊li{
    In his lifetime, Bach was famous not for his compositions, but for his improvisation skills.
    APL is an excellent fit for live coding because of its interactivity and terseness.
  }
  ◊li{
    Motifs and keys bear deep symbolic and emotional meaning in Bach's music.
    A twisted motif might mean a crucifixion and a sequence of twelve beats might depict a clock striking midnight.
    APL assigns ingeniously-chosen symbols to all its primitives.
  }
  ◊li{
    Bach's productivity was phenomenal.
    For example, he was cranking at least one cantata (about 20 minutes of music) per week for church services on Sundays for over three years, writing over three hundred cantatas.
    And it wasn't even his primary duty.
    Tell me about your tight deadlines.
    The only programmer who can come close to this level of productivity must be an over-caffeinated APL wizard.
  }
  ◊li{
    The ◊a[#:href "https://en.wikipedia.org/wiki/Contents_of_the_Voyager_Golden_Record"]{Voyager Golden Record} contains three compositions by Bach.
    If we wanted to prove to aliens that we know how to compute, APL would be the best choice for writing programs on golden surfaces.
  }
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-repr-bach"]{
    Representative Bach's music: ◊em{Wachet auf, ruft uns die Stimme}, a deeply moving and masterfully harmonized choral.
  }
  ◊img[#:src "/images/18-bach-snippet.png"]{}
}
◊figure{
  ◊marginnote["mn-apl-program"]{
    An APL function computing ◊math{2◊sup{n}} ◊a[#:href "https://en.wikipedia.org/wiki/Gray_code"]{Gray codes} for the given number ◊math{n}.
    This code comes from ◊a[#:href "https://www.jsoftware.com/papers/50/"]{A History of APL in 50 functions} by Roger K.W. Hui.
    ◊a[#:href "https://tryapl.org/?clear&q=%7B(0%E2%88%98%2C%20%E2%8D%AA%201%E2%88%98%2C%E2%88%98%E2%8A%96)%E2%8D%A3%E2%8D%B5%E2%8D%89%E2%8D%AA%E2%8D%AC%7D%C2%A8%202%203%204&run"]{Try it yourself!}
  }
  ◊center{
    ◊source-code["apl"]{{(0∘, ⍪ 1∘,∘⊖)⍣⍵⍉⍪⍬}}
  }
}

◊subsection-title["bach-apl-resources"]{Resources}
◊p{
  If you want to learn more about J.S. Bach:
}
◊ul[#:class "arrows"]{
  ◊li{Listen to the ◊a[#:href "https://www.thegreatcourses.com/courses/bach-and-the-high-baroque"]{Bach and the High Baroque} course by professor ◊a[#:href "https://robertgreenbergmusic.com/"]{Robert Greenberg}.}
  ◊li{
    Read ◊a[#:href "https://www.amazon.com/Johann-Sebastian-Bach-Musician-Paperback-ebook/dp/B002GKGBLE"]{Johan Sebastian Bach: The Learned Musician} by Christoph Wolff.
  }
}
◊p{
  If you want to learn more about APL:
}
◊ul[#:class "arrows"]{
  ◊li{
    Read ◊a[#:href "https://en.wikipedia.org/wiki/Kenneth_E._Iverson"]{Ken Iverson's} ACM Turing Award lecture ◊a[#:href "https://dl.acm.org/doi/10.1145/358896.358899"]{Notation as a Tool of Thought}.
    The ◊a[#:href "https://www.jsoftware.com/papers/"]{jsoftware website} hosts this and many other papers on APL.
  }
  ◊li{
    Read ◊a[#:href "http://www.dyalog.com/mastering-dyalog-apl.htm"]{Mastering Dyalog APL} book by Bernard Legrand and play with the ◊a[#:href "https://tutorial.dyalog.com/"]{Dyalog APL Tutorial}.
  }
  ◊li{
    Listen to the ◊a[#:href "https://arraycast.com/"]{ArrayCast} and ◊a[#:href "https://apl.show/"]{APL.Show} podcasts.
  }
  ◊li{
    Watch the ◊a[#:href "https://youtu.be/DsZdfnlh_d0"]{Depth-first search in APL} video for inspiration.
  }
  ◊li{
    Consider getting a physical copy of ◊a[#:href "https://www.amazon.com/APL-Interactive-Approach-Leonard-Gilman/dp/0471093041"]{APL: An Interactive Approach} book by Leonard Gilman and Allen J. Rose.
    The content is pretty dated, but this book is one of the most engaging books on programming I've ever read.
  }
}
}

◊section{
◊section-title["mozart"]{Wolfgang Amadeus Mozart}
◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Wolfgang_Amadeus_Mozart"]{Mozart}'s musical genius was so bright and incomprehensible that mysteries and myths still surround his life.
}
◊p{
  Mozart would prefer the ◊a[#:href "https://www.scheme.org/"]{Scheme} programming language.
}
◊ul[#:class "arrows"]{
  ◊li{
    Mozart's music reflects the values of ◊a[#:href "https://en.wikipedia.org/wiki/Age_of_Enlightenment"]{the age of enlightenment} and appeals to everyone.
    It's clean and beautifully constructed.
    Scheme is so simple that only a few pages are needed to introduce most of the language.
    Before the recent switch to Python, MIT professors used Scheme for ◊a[#:href "https://www.youtube.com/watch?v=-J_xL4IGhJA&list=PLE18841CABEA24090"]{introductory Computer Science classes}.
  }
  ◊li{
    Mozart wrote music in all genres of his time (though he loved theater and opera the most).
    Scheme is a programmable programming language; it is flexible enough to be helpful in any domain.
    See ◊a[#:href "https://racket-lang.org/"]{Racket} and "The Little X" books in the ◊a[#:href "#mozart-scheme-resources"]{Resources} section.
  }
}
◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-repr-bach"]{
    Representative Mozart's music: ◊a[#:href "https://www.youtube.com/watch?v=0rnJu1rlm90"]{Piano Sonata 5 in G-major}, featuring a joyful melody and with a simple but elegant arrangement.
  }
  ◊img[#:src "/images/18-mozart-snippet.png"]
}
◊figure{
  ◊marginnote["mn-scheme"]{
    Symbolic differentiation in Scheme (◊a[#:href "https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/6515/sicp.zip/full-text/book/book-Z-H-16.html#%_sec_2.3.2"]{example 2.3.2} in ◊a[#:href "https://en.wikipedia.org/wiki/Structure_and_Interpretation_of_Computer_Programs"]{SICP}).
  }
  ◊source-code["scheme"]{
(define (deriv exp var)
  (cond ((number? exp) 0)
        ((variable? exp)
         (if (same-variable? exp var) 1 0))
        ((sum? exp)
         (make-sum (deriv (addend exp) var)
                   (deriv (augend exp) var)))
        ((product? exp)
         (make-sum
           (make-product (multiplier exp)
                         (deriv (multiplicand exp) var))
           (make-product (deriv (multiplier exp) var)
                         (multiplicand exp))))
        (else
         (error "unknown expression type -- DERIV" exp))))
  }
}

◊subsection-title["mozart-scheme-resources"]{Resources}
  ◊p{
    If you want to learn more about Mozart:
  }
  ◊ul[#:class "arrows"]{
    ◊li{
      Listen to the ◊a[#:href "https://www.thegreatcourses.com/courses/great-masters-mozart-his-life-and-music"]{Great Masters: Mozart◊mdash{}His Life and Music} course by professor ◊a[#:href "https://robertgreenbergmusic.com/"]{Robert Greenberg}.
    }
    ◊li{
      Read ◊a[#:href "https://www.amazon.com/Mozart-Life-Maynard-Solomon/dp/0060883448"]{Mozart: A Life} by Maynard Solomon.
    }
  }
  ◊p{
    If you want to learn more about Scheme:
  }
  ◊ul[#:class "arrows"]{
    ◊li{
      Read ◊a[#:href "https://mitpress.mit.edu/9780262510875/structure-and-interpretation-of-computer-programs/"]{The Structure and Interpretation of Computer Programs} by Harold Abelson and Gerald Jay Sussman.
      It's worth reading even if you don't care about Scheme.
    }
    ◊li{
      Read ◊a[#:href "https://www.amazon.com/Little-Schemer-Daniel-P-Friedman/dp/0262560992/"]{The Little Schemer} and related books: ◊a[#:href "https://www.amazon.com/Reasoned-Schemer-MIT-Press/dp/0262535513/"]{The Reasoned Schemer}, ◊a[#:href "https://www.amazon.com/Little-Typer-MIT-Press/dp/0262536439/"]{The Little Typer}, ◊a[#:href "https://www.amazon.com/Little-Prover-MIT-Press/dp/0262527952/"]{The Little Prover}, and ◊a[#:href "https://www.amazon.com/Little-Learner-Straight-Line-Learning/dp/026254637X/"]{The Little Learner}.
    }
  }
}

◊section{
◊section-title["beethoven"]{Ludwig van Beethoven}
◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Ludwig_van_Beethoven"]{Beethoven} is the most influential composer in history.
  He single-handedly changed the direction of western music and the role of an artist in society.
}
◊p{
  One of the few languages worthy of Beethoven would be ◊a[#:href "https://www.haskell.org/"]{Haskell}:
}
◊ul[#:class "arrows"]{
  ◊li{
    Beethoven often constructed his music from the interaction and development of small motifs and rhythms, many of which initially seem trivial.
    The art of writing good Haskell code is composing programs from small functions, many of which do not do much when considered in isolation (◊code-ref["https://hackage.haskell.org/package/base-4.18.0.0/docs/Prelude.html#v:id"]{id} and ◊code-ref["https://hackage.haskell.org/package/base-4.18.0.0/docs/Data-Function.html#v:fix"]{fix}, for example).
  }
  ◊li{
    Beethoven was constantly evolving his style, pushing the boundary of musical art.
    He reinvented himself three times during his career, turning his suffering into fuel for a breakthrough.
    Similarly, Haskell evolves rapidly; the Haskell community is always looking for new ways to write and think about software.
  }
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-repr-beethoven"]{
    Representative Beethoven's music: ◊a[#:href "https://www.youtube.com/watch?v=SrcOcKYQX3c&t=7s"]{Sonata op. 13 in C minor}, also known as the Pathétique Sonata.
    Note the operatic dramatism, the masterful use of piano's sonority, and Beethoven's way of building music landscapes from tiny memorable motifs and rhythms.
  }
  ◊img[#:src "/images/18-beethoven-snippet.png"]{}
}

◊figure[#:class ""]{
  ◊marginnote["mn-haskell-example"]{
    An idiomatic implementation of the ◊a[#:href "https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm"]{Knuth-Morris-Pratt} algorithm in Haskell.
    The code comes from the ◊a[#:href "https://www.twanvl.nl/blog/haskell/Knuth-Morris-Pratt-in-Haskell"]{Knuth-Morris-Pratt in Haskell} article by Twan van Laarhoven.
  }
  ◊source-code["haskell"]{
data KMP a = KMP { done :: Bool, next :: (a -> KMP a) }

makeTable :: Eq a => [a] -> KMP a
makeTable xs = table
   where table = makeTable' xs (const table)

makeTable' []     failure = KMP True failure
makeTable' (x:xs) failure = KMP False test
   where  test  c = if c == x then success else failure c
          success = makeTable' xs (next (failure x))

isSublistOf :: Eq a => [a] -> [a] -> Bool
isSublistOf as bs = match (makeTable as) bs
   where  match table []     = done table
          match table (b:bs) = done table || match (next table b) bs
  }
}

◊subsection-title["beethoven-haskell-resources"]{Resources}
◊p{
  If you want to learn more about Beethoven:
}
◊ul[#:class "arrows"]{
    ◊li{
      Listen to the ◊a[#:href "https://www.thegreatcourses.com/courses/great-masters-beethoven-his-life-and-music"]{Great Masters: Beethoven◊mdash{}His Life and Music} course by professor ◊a[#:href "https://robertgreenbergmusic.com/"]{Robert Greenberg}.
    }
  ◊li{
    Read ◊a[#:href "https://www.amazon.com/Beethoven-Revised-Maynard-Solomon/dp/0825672686"]{Beethoven} by Maynard Solomon.
  }
}
◊p{
  If you want to learn more about Haskell:
}
◊ul[#:class "arrows"]{
  ◊li{
    Read ◊a[#:href "http://www.learnyouahaskell.com/"]{Learn You a Haskell for Great Good!} by Miran Lipovača.
    It's an engaging and illustrated introduction to Haskell.
  }
  ◊li{
    Read ◊a[#:href "https://www.euterpea.com/haskell-school-of-music/"]{The Haskell School of Music} by Paul Hudak and Donya Quick.
    The authors show the best sides of Haskell when they apply it to building a library for music generation.
  }
  ◊li{
    Check out the ◊a[#:href "https://www.haskell.org/documentation/"]{Haskell Documentation} page for more great pointers.
  }
}

}

◊section{
◊section-title["scriabin"]{Alexander Nikolayevich Scriabin}
◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Alexander_Scriabin"]{Scriabin} is a relatively obscure (at least outside of Russia) Russian composer.
  I find his music deeply expressive, emotional, and metaphysical.
  Also, he had the most stylish mustache ever.
}

◊p{
  Scriabin would love ◊a[#:href "https://scala-lang.org/"]{Scala}:
}
◊ul[#:class "arrows"]{
  ◊li{
    Scriabin dreamed of fusing arts into a synthetic art form he called ◊a[#:href "https://en.wikipedia.org/wiki/Mysterium_(Scriabin)"]{Mysterium}.
    Similarly, Scala aims to be extensible enough to embrace all programming styles and paradigms (functional, object-oriented, actor-based, etc.).
  }
  ◊li{
    Scriabin's music feels profound and unfathomable, like the night sky.
    Looking at Scala code makes me feel the same awe: I admire its structure and elegance, but its inherent complexity makes my head spin.
  }
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-repr-scriabin"]{
    Representative Scriabin's music: ◊a[#:href "https://www.youtube.com/watch?v=Uy8MTTrh-Z8&t=709s"]{Prelude in C#-minor from op. 11}, one of my favorite short piano pieces.
  }
  ◊img[#:src "/images/18-scriabin-snippet.png"]{}
}
◊figure{
  ◊marginnote["mn-scala-snippet"]{
    The Scala way of saying that optional values are just an instance of a monoid in the category of endofunctors.
    This snippet comes from the ◊code-ref["https://github.com/scalaz/scalaz#type-class-instance-definition"]{scalaz} library documentation.
  }
  ◊source-code["scala"]{
implicit val option: Traverse[Option] with MonadPlus[Option] =
  new Traverse[Option] with MonadPlus[Option] {
    def point[A](a: => A) = Some(a)
    def bind[A, B](fa: Option[A])(f: A => Option[B]): Option[B] = fa flatMap f
    override def map[A, B](fa: Option[A])(f: A => B): Option[B] = fa map f
    def traverseImpl[F[_], A, B](fa: Option[A])(f: A => F[B])(implicit F: Applicative[F]) =
      fa map (a => F.map(f(a))(Some(_): Option[B])) getOrElse F.point(None)
    def empty[A]: Option[A] = None
    def plus[A](a: Option[A], b: => Option[A]) = a orElse b
    def foldR[A, B](fa: Option[A], z: B)(f: (A) => (=> B) => B): B = fa match {
      case Some(a) => f(a)(z)
      case None => z
    }
}
  }
}

◊subsection-title["scriabin-cl-resources"]{Resources}
◊p{
  If you want to learn more about Scriabin:
}
◊ul[#:class "arrows"]{
  ◊li{
    Read ◊a[#:href "https://www.amazon.com/Alexander-Scriabin-Companion-History-Performance/dp/1442232617/"]{The Alexander Scriabin Companion: History, Performance, and Lore} by Lincoln Ballard and Matthew Bengtson.
  }
  ◊li{
    Read ◊a[#:href "https://www.amazon.com/Scriabin-Biography-Second-Revised-Dover/dp/0486288978/"]{Scriabin, a Biography} by Faubion Bowers.
  }
}
◊p{
  If you want to learn more about Scala:
}
◊ul[#:class "arrows"]{
  ◊li{Read ◊a[#:href "https://www.amazon.com/Programming-Scala-Fifth-Odersky-dp-0997148004/dp/0997148004/"]{Programming in Scala} by Martin Odersky et al., and ◊a[#:href "https://www.amazon.com/gp/product/1617290653/"]{Functional Programming in Scala} by Rúnar Bjarnason and Paul Chiusano.}
}
}

◊section{
◊section-title["closing"]{Closing words}
◊p{
  There are many more great composers and excellent programming languages.
  Matching these is an exercise for the reader.
}
◊p{
  I encourage you to think more often about things and people you like and match them with others.
  For example, ◊a[#:href "https://kpknudson.com/my-favorite-theorem/"]{My Favorite Theorem} podcast hosts ask their guests to match their favorite theorems with items and activities in their lives, such as pizza and rock climbing.
}
◊p{
  Enjoy your ◊a[#:href "https://www.youtube.com/watch?v=2G6dd7ikrXs"]{favorite things}!
}
}
