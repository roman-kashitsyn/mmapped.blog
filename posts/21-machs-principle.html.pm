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
  In his world view, inertia is the resistance of bodies to forces relative to the eternal cosmic frame of reference.
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Ernst_Mach"]{Ernst Mach}, an Austrian physicist and philosopher, disagreed with Newton's position.
  In his mind, all the interactions in nature, including the laws of motion and inertia, ought to be ◊em{relative}.
}

◊p{
  The difference between Newton's and Mach's views is subtle.
  According to Newton, if all objects in the universe simultaneously started spinning around some axis, we would immediately observe inertia in the form of ◊a[#:href "https://en.wikipedia.org/wiki/Centrifugal_force"]{centrifugal force}.
  In Mach's view, we wouldn't notice the rotation because the relative positions of bodies wouldn't change.
}

◊p{
  In Mach's universe, the space is meaningless without matter.
  If there is only one body flying in an empty universe, inertia disappears because there are no other objects to measure any movement.
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
  Or maybe you find yourself caught up in a dysfunctional relationship.
  You feel lonely and depressed, yet you can't find strength to quit.
  You still get ◊em{some} scraps of affection from your partner, shared household is somewhat convenient, and you don't want to decide what to do with Charlie, your ◊a[#:href "https://en.wikipedia.org/wiki/Labrador_Retriever"]{Labrador}.
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
  Ask a programmer to add an innocently looking feature and watch them throwing up hands and replying that it's would be easier to write a new program than to change the existing one.
}

◊p{
  Programmers often call a hard-to-change program ◊quoted{◊a[#:href "https://en.wikipedia.org/wiki/Spaghetti_code"]{spaghetti code}}, ◊quoted{◊a[#:href "http://laputan.org/mud/"]{Big Ball of Mud}}, or simply ◊quoted{tangled mess}.
  Notice anything unusual about these names?
  They all indicate intricate and unexpected relations among the program components.
  That's precisely what Mach's principle predicts us if we apply it to the realm of software engineering: the more connections a piece of software has, the harder we must work to change it.
}

◊p{
  Consider a lonely program nobody uses.
  It doesn't have any ◊quoted{inertia}, no matter how much code it contains.
  Such a program is a direct analog of a sole body in an empty Machian universe.
}

◊figure{
◊marginnote["mn-remove-lonely-fn"]{
  Unused code has low inertia because removing it doesn't change the program meaning.
}
◊source-code["diff"]{
- void LonelyFunctionNobodyCalls() {
-   // ◊ellipsis{}
- }

  int main() {
    // ◊ellipsis{}
  }
}
}

◊p{
  Similarly, we can often remove unused functions without affecting the program's meaning◊sidenote["sn-c-undefined"]{
  Unless you write in C and trigger undefined behavior, of course.
  See ◊quoted{Debugging Optimized Code May Not Make Any Sense} in ◊a[#:href "http://blog.llvm.org/2011/05/what-every-c-programmer-should-know_14.html"]{What Every C Programmer Should Know About Undefined Behavior #2/3}.
  }.
}

◊p{
  There are two major sources of complex connections in modern software: external packages and obscure assumptions.
}

◊subsection-title["external-packages"]{Treat external packages as close relationships}

◊p{
  External packages are necessary evil.
  Nowadays, it's pretty much impossible to build a useful program without relying on at least a few external components.
  Yet, some dependencies are more evil than others.
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Software_framework"]{Frameworks} are among the worst offenders.
  They provide an application skeleton, allowing developers to fill in the blanks, usually in a form of ◊a[#:href "https://en.wikipedia.org/wiki/Callback_(computer_programming)"]{callbacks}.
  This design creates many obscure connections between the framework and the application code.
}

◊p{
  I treat all external dependencies as close relationships: their bugs, security holes, and performance issues become mine pretty soon.
}

◊p{
  I won't trust a stranger to pick up my kids from school.
  And I wouldn't check my customer's credit card numbers with a random package from ◊a[#:href "https://npmjs.com/"]{npm}.
  I'll at least read its source code, check its release schedule and activity.
}


}

◊section{
◊section-title["machs-disciples"]{Mach's legacy}

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
  However, other physicists tried turning Mach's ideas into tangible theories.
}

◊p{
  Albert Einstein deeply admired Mach.
  The relativity of motion became the cornerstone of the ◊a[#:href "https://en.wikipedia.org/wiki/Special_relativity"]{special theory of relativity}.
  Unfortunately, Einstein didn't find a convincing way to incorporate Mach's version of inertia into the ◊a[#:href "https://en.wikipedia.org/wiki/General_relativity"]{general theory of relativity}.
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Dennis_W._Sciama"]{Dennis Sciama}, ◊a[#:href "https://en.wikipedia.org/wiki/Stephen_Hawking"]{Stephen Hawking}'s PhD supervisor, proposed a model of gravity incorporating Mach's principle◊sidenote["sn-sciama"]{
    D. W. Sciama, ◊a[#:href "https://academic.oup.com/mnras/article/113/1/34/2602000"]{On the Origin of Inertia}.
  }.
  Sciama's book ◊a[#:href "https://archive.org/details/unityofuniverse00scia/page/98/mode/2up"]{The Unity of Universe} provides the historical background and arguments for and against the principle (see pages 98◊ndash{}105).
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Robert_H._Dicke"]{Robert Dicke} and and ◊a[#:href "https://en.wikipedia.org/wiki/Carl_H._Brans"]{Carl Brans} developed an alternative gravitational theory◊sidenote["sn-brans-dicke"]{C. Brans and R. H. Dicke, ◊a[#:href "https://systems-eth.webs.com/Mach's%20Principle%20and%20a%20Relativistic%20Theory%20of%20Gravitation%20(PhysRev.124.925).pdf"]{Mach's Principle and Relativistic Theory of Gravitation}.} featuring Mach's view of inertia.
  In their theory, the global mass distribution in the universe determines the local gravity strength.
  Currently, there is no evidence that this theory is more accurate than Einstain's general relativity.
}

◊p{
  Overall, inertia seems to be just as puzzling to modern phisicists as it was to Newton.
  There seems to be no strong evidence supporting theories based on Mach's ideas.
  There is no concensus whether Mach's principle is the right piece in this puzzle.
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
