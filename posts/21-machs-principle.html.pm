#lang pollen

◊(define-meta title "Mach's principle")
◊(define-meta keywords "ic")
◊(define-meta summary "Why is it so hard to change things?")
◊(define-meta doc-publish-date "2023-07-01")
◊(define-meta doc-updated-date "2023-07-01")

◊section{
◊section-title["inertia-mystery"]{The mystery of inertia}
◊epigraph{
◊blockquote{
  ◊p{
    ◊ellipsis{}inertia originates in a kind of interaction between bodies◊ellipsis{}
  }
  ◊footer{Albert Einstein, letter to Ernst Mach, Zurich, 25 June 1913}
}
}

◊p{
  If you ever tried to move a closet, you know how much sweat you must shed before the damn thing ends up where you want it to be.
  Physicists call this mysterious property of objects ◊em{inertia}◊sidenote["sn-inertia"]{
    More formally, inertia is the tendency a body to stay at rest or continue moving in a straight line unless some force acts on the body.
  }.
}

◊p{
  Believe it or not, physicists have no idea where inertia comes from.
  Sure, there is the ◊a[#:href "https://en.wikipedia.org/wiki/Newton's_laws_of_motion"]{first Newton's law} ◊em{postulating} inertia, but its source remains obscure.
}

◊p{
  Newton believed in absolute time and space.
  In his world view, inertia is the resistance of bodies to forces relative to the cosmic frame of reference.
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Ernst_Mach"]{Ernst Mach}, an Austrian physicist and philosopher, disagreed with Newton's position.
  In his mind, all the interactions in nature, including the laws of motion and inertia, ought to be ◊em{relative}.
}

◊p{
  The difference between Newton's and Mach's views is subtle.
  According to Newton, if all objects in the universe simultaneously started spinning around some axis, we would immediately observe inertia in the form of ◊a[#:href "https://en.wikipedia.org/wiki/Centrifugal_force"]{centrifugal force}.
  In Mach's view, we wouldn't notice the rotation because the relative positions of bodies wouldn't change.
  In Mach's universe, the space is meaningless without matter.
}

◊p{
  I first learned about Mach and his ideas from a controversial book by Alexander Unzicker:
}
◊blockquote{
  ◊p{
    Mach had also argued that a body's inertial resistance to acceleration, and hence the concept of mass itself, should depend on the body's motion relative to the rest of the universe.
    Even remote galaxies would influence the speed at which an apple falls from the tree!
  }
  ◊footer{Alexander Unzicker, ◊a[#:href "https://www.amazon.com/Einsteins-Lost-Key-Overlooked-Century/dp/1519473435"]{Einstein's Lost Key: How We Overlooked the Best Idea of the 20th Century}, Chapter 1}
}

◊p{
  Once that idea settled in my mind, I had an epiphany.
  It gave a form to my implicit intuitive knowledge about the world.
  I started seeing the principle's consequences everywhere I looked.
}
}

◊section{
◊section-title["machs-disciples"]{Mach's disciples}

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
  Mach never formulated a theory that would allow us to test his ideas experimentally.
}

◊p{
  Albert Einstein deeply admired Mach, incorporating the relativity of motion into the special relativity theory.
  Mach's ideas were a major inspiration for Albert Einstein's relativity theories.
  Unfortunately, Einstein didn't find a way to incorporate Mach's vision into the general relativity theory.
}

◊p{
  Other physicists tried to turn Mach's into tangible theories.
  ◊a[#:href "https://en.wikipedia.org/wiki/Dennis_W._Sciama"]{Dennis Sciama}, ◊a[#:href "https://en.wikipedia.org/wiki/Stephen_Hawking"]{Stephen Hawking}'s PhD supervisor, proposed a model of gravity incorporating Mach's principle◊sidenote["sn-sciama"]{
    D. W. Sciama, ◊a[#:href "https://academic.oup.com/mnras/article/113/1/34/2602000"]{On the Origin of Inertia}.
  }.
  ◊a[#:href "https://en.wikipedia.org/wiki/Robert_H._Dicke"]{Robert Dicke} and and ◊a[#:href "https://en.wikipedia.org/wiki/Carl_H._Brans"]{Carl Brans} developed an alternative gravitational theory◊sidenote["sn-brans-dicke"]{C. Brans and R. H. Dicke, ◊a[#:href "https://journals.aps.org/pr/abstract/10.1103/PhysRev.124.925"]{Mach's Principle and Relativistic Theory of Gravitation}.} featuring Mach's view of inertia.
  There seems to be no strong evidence supporting these theories.
}

◊p{
  Overall, inertia seems to be just as puzzling to modern phisicists as it was to Newton.
  There is no concensus whether Mach's principle is the right piece in this puzzle.
}
}

◊section{
◊section-title["relations-as-inertia"]{Relations as inertia}

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
  But what if you got the offer when you're forty, have three kids and a mortgage?
  The kids will have to abandon their plans, friends, and learn a foreign language.
  The change is unlikely to affect them positively◊sidenote["sn-inside-out"]{
    In Pixar's ◊a[#:href "https://www.imdb.com/title/tt2096673/"]{Inside Out}, teenage Riley starts losing her integrity after her parents move to San Francisco.
  }.
  You'll have to lose contacts with your parents, in-laws, and the few good friends you and your partner still have.
  Furthermore, you'll have to leave your family house and rent an apartment abroad.
  Is the offer still as attractive?
}

◊p{
}

◊p{
  Relationships are the source of inertia in our lives.
  These include your loved ones, friends, community, church, and places you enjoy visiting.
  Relationships make our lives worth living, but they also resist drastic changes.
}
}

◊section{
◊section-title["inertia-in-software"]{Inertia in software}

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
◊section-title["conclusion"]{Conclusion}

◊p{
  We are ready to formulate Mach's principle in its general form.
}

◊advice["general-formula"]{
 Resistance to change is proportional to the strength of affected relations.
}
}
