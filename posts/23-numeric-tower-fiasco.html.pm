#lang pollen

◊(define-meta title "The numeric tower fiasco")
◊(define-meta keywords "oop")
◊(define-meta summary "Inheritance is scam.")
◊(define-meta doc-publish-date "2023-09-02")
◊(define-meta doc-updated-date "2023-09-02")

◊epigraph{
  ◊blockquote{
    ◊p{
      I find OOP technically unsound◊ellipsis{} I find OOP philosophically unsound◊ellipsis{} I find OOP methodologically wrong.
    }
    ◊footer{From ◊a[#:href "http://stlport.org/resources/StepanovUSA.html"]{An Interview with A. Stepanov}}
  }
}

◊section{
◊section-title["introduction"]{Introduction}

◊p{
  Object-oriented programming◊sidenote["sn-oop"]{
    ◊quoted{Object-oriented} is a vague term that means different things to different people.
    This article focuses on the class-based flavor that the most popular programming languages (Java, Python, C++, C#) implement.
  } is still the dominant paradigm in the software industry.
   
  The typical advice on modeling the problem domain is to fit your entities into hierarchies where specific types inherit common attributes and behaviors from ◊quoted{base} classes.
}

◊p{
  That idea looked intuitive and attractive to me when I first encountered it.
  I spent countless hours learning about the ◊quoted{good} object-oriented design and trying to apply these ideas in practice.
}

◊p{
  The practice showed that real engineering problems rarely fit into rigid class hierarchies.
  This article descrabes one example that stuck with me from the start of my programming career.
}
}

◊section{
◊section-title["the-numeric-tower"]{The numeric tower}

◊p{
  I like math, so one of the first structures I tried to model with classes was the most precisely specified and well-studied hierarchy in human history: the ◊a[#:href "https://en.wikipedia.org/wiki/Numerical_tower"]{numerical tower}.
}

◊p{
  Mathematicians invented quite a few types of integers, each type is an extention of the previous one.
  The simplest case is the natural numbers: ◊math{0, 1, 2, ◊ellipsis{}}.
  Integers extend naturals so that equations ◊math{a + x = c} (where ◊math{a} and ◊math{c} are naturals) always have a solution: ◊math{0, 1, -1, 2, -2, ◊ellipsis{}}.
  Then come rational numbers to provide solutions for all equations ◊math{a * x = c} (where ◊math{a} and ◊math{c} are naturals): 1/2, 1/3, ◊ellipsis{}.
}

◊figure[#:class "grayscale-diagram medium-size"]{
  ◊marginnote["mn-numeric-tower"]{
    A few floors of the ◊a[#:href "https://en.wikipedia.org/wiki/Number"]{numeric} tower represented as a ◊a[#:href "https://en.wikipedia.org/wiki/Venn_diagram"]{Venn diagram}.
  }
  ◊(embed-svg "images/23-numeric-tower.svg")
}

◊subsection-title["oop-design"]{The OOP design}
◊p{
  Let's limit the tower to only two number types to keep the example simple: ◊code{Naturals} and ◊code{Integers}.
  Most people (me included) will instinctively reach for the class structure where ◊code{Natural} is the base class, and ◊code{Integer} extends that base.
}

◊source-code["pseudo-code"]{
class Natural
  value : UInt

  def make(UInt) : Natural
  def add(other : Natural) : Natural = Natural.make(self.value + other.value)
end

class Integer <: Natural
  negative? : Bool

  def make(value : Natural, negative? : Bool) : Integer = ◊ellipsis{}
  def magnitude() : Natural = self.value
  def add(other : Integer) : Integer = ◊ellipsis{}
end
}

◊p{
  I'm sure you immediately spotted the main problem with this design: we inversed the hierarchy, breaking the ◊quoted{is a} relationship!
  We claim that all integers are also naturals, but that's false.
  The design violates the ◊a[#:href "https://en.wikipedia.org/wiki/Liskov_substitution_principle"]{Liskov substitution principle}: passing an ◊code{Integer} to a function that expects a ◊code{Natural} can produce incorrect results:
}

◊source-code["pseudo-code"]{
> Natural.make(5).add(Integer.make(10, true)) // 5 + -10
15 // ouch
}

◊p{
  Enlightened by this failure, we reverse the inheritance hierarchy.
  ◊code{Integer} becomes our base class, and ◊code{Natural} extends it.
}

◊source-code["pseudo-code"]{
class Integer
  value : UInt
  negative? : Bool
  def make(value : Natural, negative? : Bool)
  def magnitude() : Natural
  def add(other : Integer) : Integer
end

class Natural <: Integer
  def make(value : UInt) : Natural = super.make(value, false)
  def add(other : Natural) : Natural
end
}

◊p{
  Once the initial excitement dissipates, we face a new issue.
  The simplest case, the ◊code{Natural} numbers, must have the same representation as the more complex type, ◊code{Integers}.
  The problem becomes more apparent if we add more types to the tower, such as ◊code{Rational}.
  Instead of starting with the simplest case and building from it, we started with the most complicated one and made everything else a special case.
  That's why the original incorrect design was so compelling: we moved from simpler to more complex types, not the other way around!
}

◊p{
  The last option is to give up on concrete type hierarchies and clamp all number types under a single interface.
}

◊source-code["pseudo-code"]{
interface Number
  def addNat(n : Natural) : Number
  def subNat(n : Natural) : Number
  // ◊ellipsis{}
  def addInt(i : Integer) : Number
  def subInt(i : Integer) : Number
  // ◊ellipsis{}
end

class Natural <: Number
  // a lot of boring code ◊ellipsis{}
end

class Integer <: Number
  // a lot of boring code ◊ellipsis{}
end
}

◊p{
  Yuk! It's time to abandon our blunt OOP tools and start from the first principles.
}

◊subsection-title["the-functional-encoding"]{The functional encoding}
◊p{
  Instead of encoding "is a" relations among types as a hierarchy, we can encode relations between numerics in pure functions (I use Haskell notation here).
}

◊source-code["haskell"]{
-- Each natural is either zero or a successor of a smaller number.
data Natural = Zero | Succ Natural

-- There are two disjoint classes of integers:
-- "n" and "-1 - n" for all natural values of n.
data Integer = NonNegative Natural | MinusOneMinus Natural

int_of_nat :: Natural -> Integer
int_of_nat = NonNegative

nat_of_int :: Integer -> Maybe Natural
nat_of_int (NonNegative n) = Just n
nat_of_int (MinusOneMinus _) = Nothing
}

◊p{
  The design has a minor issue: we lost our ability to do arithmetics on numbers of different types.
  We can add a universal ◊code{Number} type to reclaim this property:
}

◊source-code["haskell"]{
data Number = Nat Natural | Int Integer

-- Transforms the number to the most canonical form.
simplify :: Number -> Number
simplify (Int (NonNegative n)) = Nat n
simplify x = x

-- Adds arbitrary numbers.
plus :: Number -> Number -> Number
plus (Nat n) (Nat m) = plus_nat n m
plus (Nat n) (Int i) = ◊ellipsis{}
// ◊ellipsis{}
}

◊p{
  This design might seem like a re-iteration of the ◊code{Number} interface story from the OO world, but it's not:
  Here, naturals and integers don't need to know anything about the Number type, and we have many opportunities to reduce the boilerplate code to the bare minimum.
}
}

◊section{
◊section-title["conclusion"]{Conclusion}
◊p{
  We started with a precisely defined hierarchy of mathematical objects and couldn't find an acceptable way to model them as a class hierarchy.
  We then pivoted and went with the constructive math path, organizing value spaces instead of concept hierarchies.
  The constructive math path directly corresponds to my mental model of numbers.
  That's also close to how mathematicians define numerics.
}
}

