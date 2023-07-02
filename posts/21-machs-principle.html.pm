#lang pollen

◊(define-meta title "Mach's principle")
◊(define-meta keywords "ic")
◊(define-meta summary "Why is it so hard to change things?")
◊(define-meta doc-publish-date "2023-07-02")
◊(define-meta doc-updated-date "2023-07-02")

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
  If you have ever tried to move a closet, you know how much sweat you must shed before the damn thing ends up where you want it to be.
  Physicists call this mysterious property of objects ◊em{inertia}◊sidenote["sn-inertia"]{
    More formally, inertia is the tendency of a body to stay at rest or continue moving in a straight line unless some force acts on the body.
  }.
}

◊p{
  Believe it or not, physicists have no idea where inertia comes from.
  Sure, there is the ◊a[#:href "https://en.wikipedia.org/wiki/Newton's_laws_of_motion"]{first Newton's law} ◊em{postulating} inertia, but its source remains obscure.
}

◊p{
  Newton believed in absolute time and space.
  In his worldview, inertia is the resistance of bodies to forces accelerating them relative to the eternal cosmic frame of reference.
}

◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/Ernst_Mach"]{Ernst Mach}, an Austrian physicist and philosopher, disagreed with Newton's position.
  In his mind, all the interactions in nature, including the laws of motion and inertia, should be ◊em{relative}.
}

◊p{
  The difference between Newton's and Mach's views is subtle.
  According to Newton, if all objects in the universe simultaneously started spinning around some axis, we would immediately observe inertia as ◊a[#:href "https://en.wikipedia.org/wiki/Centrifugal_force"]{centrifugal force}.
  In Mach's view, we wouldn't notice the rotation because the relative positions of bodies wouldn't change.
}

◊p{
  In Mach's universe, space is meaningless without matter.
  If only one body is flying in an empty universe, inertia disappears because no other objects are around to measure movement.
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
  I started seeing the principle's consequences everywhere: in human relationships, project management, team dynamics, and software development.
}
}

◊section{
◊section-title["relations-as-inertia"]{Relations as inertia}

◊epigraph{
◊blockquote{
  ◊p{
    ◊ellipsis{}once you get up steam, you are carried helplessly along.
  }
  ◊footer{Attributed to Aleksandr Solzhenitsyn}
}
}

◊p{
  Imagine you're twenty-three, single and live in a rented apartment.
  A respectable company offers you a dream job on the other side of the globe.
  The compensation is so high you don't feel comfortable saying the number out loud.
  Will you take the offer?
}

◊p{
  You take some time to contemplate the offer.
  The prospect of moving far away makes you feel scared, excited, and somewhat sad.
  You will miss your neighborhood and weekends with friends and parents.
  But the offer is too tempting to pass on.
}

◊p{
  But what if you got the offer when you're forty, have three kids and a mortgage?
  The kids will have to abandon their plans, leave their friends behind, and learn a foreign language.
  The change is unlikely to affect them positively◊sidenote["sn-inside-out"]{
    In Pixar's ◊a[#:href "https://www.imdb.com/title/tt2096673/"]{Inside Out}, teenage Riley starts losing her integrity after her parents move to San Francisco.
  }.
  You'll have to lose contact with your parents, in-laws, and the few good friends you and your partner still have.
  Furthermore, you'll have to leave your family's house and rent an apartment abroad.
  Is the offer still as attractive as it would be two decades ago?
}

◊p{
  Or you may find yourself caught up in a dysfunctional relationship.
  You feel lonely and depressed, yet you can't find the strength to quit.
  You still get ◊em{some} scraps of affection from your partner, a shared household is somewhat convenient, and you don't want to decide what to do with Charlie, your ◊a[#:href "https://en.wikipedia.org/wiki/Labrador_Retriever"]{Labrador}.
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
  Ask a programmer to add an innocently looking feature and watch them throw up their hands.
  They might even tell you it would be easier to write a new program than to change the existing one.
}

◊p{
  Programmers often call a hard-to-change program ◊quoted{◊a[#:href "https://en.wikipedia.org/wiki/Spaghetti_code"]{spaghetti code}}, ◊quoted{◊a[#:href "http://laputan.org/mud/"]{Big Ball of Mud}}, or ◊quoted{tangled mess}.
  Notice anything unusual about these names?
  They all indicate intricate and unexpected relations among the program components.
}

◊p{
  Programmer's folklore teaches us that ◊a[#:href "https://peps.python.org/pep-0020/"]{explicit is better than implicit}, ◊a[#:href "https://en.wikipedia.org/wiki/Coupling_%28computer_programming%29"]{the coupling should be low}, ◊a[#:href "http://wiki.c2.com/?GlobalVariablesAreBad"]{global variables are bad}, and ◊a[#:href "https://programmingisterrible.com/post/139222674273/write-code-that-is-easy-to-delete-not-easy-to"]{code should be easy to delete}.
  In other words, software component's inertia and complexity come not only from component's absolute size, but also from the number and nature of its relations to other components.
}

◊p{
  That's what Mach's principle predicts us if we apply it to software engineering: the more connections a piece of software has, the harder we must work to change it.
}

◊p{
  Consider a lonely program nobody uses.
  It has no ◊quoted{inertia}, no matter how much code it contains.
  Such a program is analogous to a sole body in an empty Machian universe.
}

◊p{
  Similarly, we can often remove unused functions without affecting the program's meaning◊sidenote["sn-c-undefined"]{
  Unless we ◊a[#:href "https://www.youtube.com/watch?v=1S1fISh-pag"]{write in C} and trigger ◊a[#:href "https://en.cppreference.com/w/cpp/language/ub"]{undefined behavior}, of course.
  See ◊quoted{Debugging Optimized Code May Not Make Any Sense} in ◊a[#:href "http://blog.llvm.org/2011/05/what-every-c-programmer-should-know_14.html"]{What Every C Programmer Should Know About Undefined Behavior #2/3}.
  }.
  However, the more callers a function has, the harder it is to change ◊a[#:href "https://www.hyrumslaw.com/"]{anything} about it.
}

◊p{
  Interestingly, we can see ◊a[#:href "https://en.wikipedia.org/wiki/Regression_testing"]{regression testing} as a way to increase software's inertia.
  The ultimate goal of such tests is to make ◊em{destructive} changes harder to make.
  Unfortunately, tests often turn into ◊a[#:href "https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html"]{change detectors}, making ◊em{any} change unnecessarily complicated.
}

◊p{
  The ◊a[#:href "https://github.com/github/renaming"]{default Git branch renaming} is one of my favorite examples of inertia in software.
  The idea behind the change is trivial; it would take Linus about a minute to change the default branch name from ◊code{master} to ◊code{main} back in 2005.
  Fifteen years later, the sheer amount of existing software and data referring to the old branch name makes a complete migration practically infeasible.
}

}

◊section{
◊section-title["conclusion"]{Conclusion}

◊p{
  We are ready to formulate Mach's principle in its general form after seeing how it applies to physics, software, and life.
}

◊advice["mach-general-principle"]{
Resistance to change is proportional to the strength of affected relations.
}

◊p{
  We can draw a few practical implications from this principle.
}

◊p{
  Firstly, we must ◊em{account for hidden relations when we estimate project costs}.
  The approach most people employ is to base estimates solely on the change to be done.
  It seems reasonable and rational, but ◊a[#:href "https://en.wikipedia.org/wiki/Planning_fallacy"]{it doesn't work}.
  Any change worth doing is trapped in a web of dependencies hidden from an unsuspecting observer; even minor changes might require herculean efforts.
  The best predictor of project completion time is the time it took to complete similar projects in the past.
}

◊p{
  Secondly, we can ◊em{achieve goals faster by reducing dependencies}.
  Minimizing the number of teams involved in a project can drastically reduce the ◊a[#:href "https://www.investopedia.com/terms/l/leadtime.asp"]{lead time}.
  Fred Brooks ◊a[#:href "https://en.wikipedia.org/wiki/The_Mythical_Man-Month"]{observed} similar dynamics while managing a large team at IBM:
  Adding more people to a project running late tends to increase its inertia, further delaying the delivery.
}

◊p{
  Lastly, we must ◊em{address bad decisions before they get tangled in dependencies}.
  We want to fix our mistakes quickly before others rely on them.
  The tighter the feedback look, the cheaper our mistakes become.
  Tinkering, experimentation, and ◊a[#:href "https://agilemanifesto.org/"]{incremental delivery} almost always trump theorizing and planning.
}

◊p{
  Was Mach right in the physics domain?
  We don't know.
  Mach never formulated a theory that would allow us to test his ideas experimentally◊sidenote["sn-mach-legacy"]{
    Other physicists tried turning Mach's ideas into tangible theories.
    The relativity of motion became the cornerstone of Einstein's ◊a[#:href "https://en.wikipedia.org/wiki/Special_relativity"]{special theory of relativity}.
    ◊a[#:href "https://en.wikipedia.org/wiki/Dennis_W._Sciama"]{D. W. Sciama}'s book ◊a[#:href "https://archive.org/details/unityofuniverse00scia/page/98/mode/2up"]{The Unity of Universe} provides an excellent overview of Mach's principle (see pages 98◊ndash{}105).
  ◊a[#:href "https://en.wikipedia.org/wiki/Robert_H._Dicke"]{R. H. Dicke} and ◊a[#:href "https://en.wikipedia.org/wiki/Carl_H._Brans"]{C. H. Brans} developed a ◊a[#:href "https://en.wikipedia.org/wiki/Brans%E2%80%93Dicke_theory"]{gravitational theory} featuring Machian inertia.
  }.
  Despite all the progress in theoretical physics, inertia seems just as puzzling to modern physicists as it was to Newton.
  There is no consensus on whether Mach's principle is the right piece in this puzzle, but its connection to everyday experience makes it compelling nevertheless.
}
}

