#lang pollen

◊(define-meta title "Mach's principle")
◊(define-meta keywords "ic")
◊(define-meta summary "Applying Ernst Mach's ideas to software engineering and life.")
◊(define-meta doc-publish-date "2023-07-01")
◊(define-meta doc-updated-date "2023-07-01")

◊section{
◊epigraph{
◊blockquote{
  ◊p{
    inertia originates in a kind of interaction between bodies
  }
  ◊footer{Albert Einstein}
}
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Ernst_Mach"]{Ernst Mach} was an Austrian physicist and philosopher.
  His name pops up every time you hear about supersonic jets flying at ◊a[#:href "https://en.wikipedia.org/wiki/Mach_number#Etymology"]{Mach two}.
  Mach's ideas also ◊a[#:href "https://en.wikipedia.org/wiki/Mach%27s_principle#Einstein's_use_of_the_principle"]{influenced} Einstein's relativity theory.
}

◊p{
  I first learned about Mach's ideas from a controversial book by Alexander Unzicker.
}
◊blockquote{
  ◊p{
    Mach had also argued that a body's inertial resistance to acceleration, and hence the concept of mass itself, should depend on the body's motion relative to the rest of the universe.
    Even remote galaxies would influence the speed at which an apple falls from the tree!
  }
  ◊footer{Alexander Unzicker, ◊a[#:href "https://www.amazon.com/Einsteins-Lost-Key-Overlooked-Century/dp/1519473435"]{Einstein's Lost Key: How We Overlooked the Best Idea of the 20th Century}, Chapter 1}
}

◊p{
  Once Mach's idea settled in my mind, I had an epiphany.
  It gave a form to my implicit intuitive knowledge about the world.
  I started seeing this principle in action everywhere I looked.
}
}

◊section{
◊section-title["in-physics"]{In physics}

◊epigraph{
  ◊blockquote{
    ◊p{
      There is a simple experiment that anyone can perform on a starry night, to clarify issues raised by Mach's principle.
      First stand still, and let your arms hang loose at your sides.
      Observe that the stars are more or less unmoving, and your arms hang more or less straight down.
      Then pirouette.
      The stars will seem to rotate around the zenith, and at the same time your arms will be drawn upward by centrifugal force.
      It would surely be a remarkable coincidence if the inertial frame, in which your arms hung freely,
      just happened to be the reference frame in which typical stars are at rest,
      unless there was some interaction between the stars and you that determined your inertial frame.

    }
    ◊footer{Steven Weinberg, ◊quoted{Gravitation and Cosmology}, ◊a[#:href "https://archive.org/details/gravitationcosmo00stev_0/page/16"]{p. 17}}
  }
}

◊p{
}
}

◊section{
◊section-title["in-life"]{In life}

◊p{
  Imagine you're twenty three, you're single and live in a rented apartment.
  A respectable company offers you a dream job on the other side of the globe.
  The compensation is so high you don't feel comfortable saying the number out loud.
  Will you take the offer?
}

◊p{
  You take some time to contemplate the offer.
  Moving far away sounds scary, exciting, and somewhat sad.
  You will miss your neighborhood, weekends with friends and parents.
  But the offer is too tempting to pass on.
}

◊p{
  Imagine now that you got the offer when you're forty, have three kids and a mortgage.
  The kids will have to abandon their plans, friends, and learn a foreign language.
  You'll have to leave the house you've built for your family and rent an apartment abroad.
  Is the offer still as attractive?
}

◊p{
  Relationships are the source of inertia in our lives.
  These include your loved ones, friends, community, church, and places you enjoy visiting.
  Relationships make our lives worth living, but they also resist drastic changes.
}
}

◊section{
◊section-title["in-software"]{In software}

◊epigraph{
  ◊blockquote{
    ◊p{
      Complexity is caused by two things: ◊em{dependencies} and ◊em{obscurity}.
    }
    ◊footer{John Ousterhout, ◊a[#:href "https://www.amazon.com/Philosophy-Software-Design-2nd/dp/173210221X"]{A Philosophy of Software Design, 2nd Edition}.}
  }
}

◊p{
  Changing software is hard.
}
}

◊section{
◊section-title["in-general"]{In general}

◊p{
  We are ready to formulate Mach's principle in its general form.
}

◊advice["general-form"]{
 Resistance to change is proportional to the cumulative strength of affected relations.
}
}
