#lang pollen

◊(define-meta title "Functor: the ultimate analogy")
◊(define-meta keywords "programming,glasperlenspiel")
◊(define-meta summary "Functor as a formal mathematical version of the concept of analogy.")
◊(define-meta doc-publish-date "2022-05-25")
◊(define-meta doc-updated-date "2022-05-25")

◊epigraph{
◊blockquote{
◊p{ 
  The Game was closely allied with music, and usually proceeded according to musical or mathematical rules.
  One theme, two themes, or three themes were stated, elaborated, varied, and underwent a development quite similar to that of the theme in a Bach fugue or a concerto movement.
  A Game, for example, might start from a given astronomical configuration, or from the actual theme of a Bach fugue, or from a sentence out of Leibniz or the Upanishads, and from this theme, depending on the intentions and talents of the player, it could either further explore and elaborate the initial motif or else enrich its expressiveness by allusions to kindred concepts.
  Beginners learned how to establish parallels, by means of the Game's symbols, between a piece of classical music and the formula for some law of nature.
}
◊footer{Hermann Hesse, ◊em{"The Glass Bead Game"}}
}
}

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  ◊a[#:href "https://en.wikipedia.org/wiki/The_Glass_Bead_Game"]{The Glass Bead Game} is a fictional game from the book by Hermann Hesse with the same title.
  The book does not describe the rules of the Game; all we know is that the purpose of the Game is to reveal parallels between simingly unrelated things: musical pieces, mathematical formulas, and pieces of art.
}
◊p{
  When I read Hesse's book for the first time as an university student, it shattered my world.
  I understood what I want to do with my life: I wanted to study beautiful things and find deep connections between them.
}
◊p{
  Another encounter that left a deep mark on me was my discovery of the category theory.
  As many others beginner Haskell programmers trying to grasp ◊a[#:href "https://wiki.haskell.org/Monad"]{monads}, I turned to the mathematical abstraction that evoked them in hope of enlightment.
  The enlightment came eventually, and with it a realization that the category theory is a living embodiment of the Game.
  It is a framework for seeing things at the most abstract level, where parallels between things is both the fuel and the fire.
}
◊p{
  This article is a meta-game.
  Our subject is the parallel between the Game and the category theory.
  We shall see that the category theory gives us symbols and rules to play the Game.
  Furthermore, I hope to convince you that one of the basic concepts of the theory, the ◊em{functor}, lies at the heart of our everyday life.
}
}

◊section{
◊section-title["analogies"]{Analogies and parallels}
◊epigraph{
◊blockquote{
  ◊p{Indeed, the central thesis of our book — a simple yet nonstandard idea — is that the spotting of analogies pervades every moment of our thought, thus constituting thought’s core.}
  ◊footer{Douglas R. Hofstadter, Emmanuel Sander ◊em{"Surfaces and Essences: Analogy as the Fuel and Fire of Thinking"}}
}
}
◊p{
  Our mind is a powerful pattern-matching machine.
}
}

◊section{
◊section-title["ct-101"]{Category theory 101}
◊epigraph{
◊blockquote{
  ◊p{
    General category theory (i.e., the theory of arrow-theoretic results) is generally known as abstract nonsense (the terminology is due to Steenrod).
  }
  ◊footer{Serge Lang, ◊em{"Algebra"}, 2nd edition, p. 175}
}
}

◊p{
  We need to learn basics of the category theory to fully appreciate the meta-game.
}

◊subsection-title["categories"]{Categories}
◊p{
  Category is a mathematical structure that consists of objects and arrows (or ◊em{morphisms}) between them.
  By convention, we denote objects with capital letters, such as ◊math{A} or ◊math{B}, and arrows with lowercase letters, such as ◊math{f}.
  We also spell out names of the objects at which arrows start and end, for example, ◊math{f : A → B}.
  Both objects and arrows are opaque, the theory does not assign any meaning to them.
}
◊ul[#:class "arrows"]{
  ◊li{
    Each object has an arrow that starts and ends at this object.
    We call this arrow an ◊em{identity morphism} (denoted ◊math{id◊sub{A} : A → A}).
  }
  ◊li{
    For every pair of arrows ◊math{f : A → B} and ◊math{g : B → C} (◊math{f} ends at the same object where ◊math{g} starts), the category also contains a composite arrow ◊math{g ∘ f : A → C} (pronounced as ◊em{◊math{g} after ◊math{f}}).
  }
  ◊li{
    For every three arrows ◊math{f : A → B}, ◊math{g : B → C}, and ◊math{h : C → D}, compositions ◊math{(h ∘ g) ∘ f} and ◊math{h ∘ (g ∘ f)} are equal (they do the same thing, for some definition of "do").
  }
}

◊p{
  You might find it helpful to view categories as a special kind of ◊a[#:href "https://en.wikipedia.org/wiki/Graph_(discrete_mathematics)#Directed_graph"]{directed graphs}.
  Objects are ◊a[#:href "https://en.wikipedia.org/wiki/Vertex_(graph_theory)"]{vertices} of the graph, and arrows are edges.
  The category axioms require each vertex to have a self-loop and graph to be equal to its ◊a[#:href "https://en.wikipedia.org/wiki/Transitive_closure"]{transitive closure}.
}

◊subsection-title["category-examples"]{Examples of categories}

◊p{
  The only way to understand a mathematical concept is to look at many examples.
}

◊p{
  The simplest structure that we can call a category is an empty one.
  It has no objects and no arrows, all category axioms are ◊a[#:href "https://en.wikipedia.org/wiki/Vacuous_truth"]{vacuously true}.
  We this call rather boring structure ◊em{zero category}.
}

◊p{
  Another rather dull structure is the ◊em{one category}.
  It has one object denoted ◊math{∗} and one identity arrow ◊math{id◊sub{∗} : ∗ → ∗}.
}

◊p{
  We can make things a bit more interesting by adding more objects and arrows.
  One of my favourite discrete functions is ◊a[#:href "https://en.wikipedia.org/wiki/Exclusive_or"]{◊code{xor}}, also known as addition modulo two.
  ◊code{xor} is a binary function that takes two booleans and returns true if and only if the inputs differ.
  Let us model ◊code{xor} as a category.
}
◊p{
  One approach is to make ◊code{true} ( ◊math{T} ) and ◊code{false} ( ◊math{F} ) into objects and represent ◊code{xor} transofrmations as arrows.
  However, there is one obstacle: the ◊code{xor} function needs two arguments, but arrows can operate only on one object.
  We overcome the obstacle by splitting our ◊code{xor} function into two functions that act like ◊code{xor} with a fixed argument:
  ◊math{xor◊sub{T}(x) = xor(T, x)}, ◊math{xor◊sub{F}(x) = xor(F, x)}.
  Our ◊code{xor}-induced category will have two objects and four arrows.
}

◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-xor-two-objects"]{
  A category that models ◊code{xor} function behavior using two objects.
  Technically, all arrows should have different names, but we will break that rule to simplify the notation.
}
◊p[#:class "svg"]{◊(embed-svg "images/07-xor-two-objects.svg")}
}

◊p{
  Another approach is less obvious but more idiomatic.
  We can have one object, the set of booleans ◊math{{T, F}}.
  Our arrows, ◊math{xor◊sub{T}} and ◊math{xor◊sub{F}}, will now operate on the entire set◊sidenote["sn-f-entire-set"]{
    We can "lift" functions to operate on entire sets by calling them on all elements of the codomain and gathering the results into a set.
  }.
  This category will have two ◊em{different} identity arrows.
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-xor-two-objects"]{
  A category that models ◊code{xor} function behavior using one object.
}
◊p[#:class "svg"]{◊(embed-svg "images/07-xor-one-object.svg")}
}

◊subsection-title["functors"]{Functors}

◊p{
  Let us apply category thinking to categories themselves.
  Clearly, categories should be objects, but what are the arrows between those objects?
  We call these arrows ◊a[#:href "https://en.wikipedia.org/wiki/Functor"]{functors}.
}
◊p{
  Functors are structure-preserving mapping between categories.
  They map objects to objects and arrows to arrows such that:
}
◊ul[#:class "arrows"]{
  ◊li{Identity arrows map to identity arrows: ◊math{F(id◊sub{X}) = id◊sub{F(X)}}.}
  ◊li{Arrow compositions map to arrow compositions: ◊math{F(f ∘ g) = F(f) ∘ F(g)}.}
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-xor-functor"]{
  A functor between two categories that the ◊code{xor} function induces.
}
◊p[#:class "svg"]{◊(embed-svg "images/07-xor-functor.svg")}
}

}

◊section{
◊section-title["diagrams"]{Diagram: the ultimate mind map}
}
