#lang pollen

◊(define-meta title "The numeric tower fiasco")
◊(define-meta keywords "oop")
◊(define-meta summary "Inheritance is scam.")
◊(define-meta doc-publish-date "2023-11-20")
◊(define-meta doc-updated-date "2023-11-20")

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
  This article describes one example that stuck with me from the start of my programming career: modeling the hierarchy of number types.
}
}

◊section{
◊section-title["the-numeric-tower"]{The numeric tower}

◊p{
  I like math, so one of the first structure I tried to model with classes was the most precisely specified and well-studied hierarchy in human history: the ◊a[#:href "https://en.wikipedia.org/wiki/Numerical_tower"]{numerical tower}.
}

◊p{
  Mathematicians invented◊sidenote["sn-motivation"]{
    The main motivation for introducing integers was to create a numeric space where equations of the form ◊math{a + x = c}, where ◊math{a} and ◊math{c} are naturals, always have a solution.
    Rationals play the same role for equations  of the form ◊math{a × x = c}.
  } quite a few types of numbers; usually each new type is the most natural extention of the previous one:
}
◊ul[#:class "arrows"]{
◊li{
  Naturals (◊math{ℕ}) are the numbers we use for counting: ◊math{0, 1, 2, ◊ellipsis{}}.
}
  ◊; TODO: Dedekind's remark on whole numbers
◊li{
  Integers (◊math{ℤ}) extend naturals to include negative whole numbers: ◊math{0, 1, -1, 2, -2, ◊ellipsis{}}.
}
◊li{
  Rational numbers (◊math{ℚ}) add common fractions where the numerator and denumerator are whole numbers: ◊math{1}, ◊math{½}, ◊math{-½}, ◊math{⅓}, ◊math{-⅓}, ◊ellipsis{}.
}
}

◊figure[#:class "grayscale-diagram medium-size"]{
  ◊marginnote["mn-numeric-tower"]{
    A few floors of the ◊a[#:href "https://en.wikipedia.org/wiki/Number"]{numeric} tower represented as a ◊a[#:href "https://en.wikipedia.org/wiki/Venn_diagram"]{Venn diagram}.
  }
  ◊(embed-svg "images/23-numeric-tower.svg")
}

◊p{
  The tower goes up and includes real numbers, complex numbers, quaternions, etc.
}

◊subsection-title["oop-design"]{The OOP design}
◊p{
  Let's limit the tower to only two number types to keep the example simple: ◊code{Naturals} and ◊code{Integers}.
  Most people (me included) will instinctively reach for the class structure where ◊code{Natural} is the base class, and ◊code{Integer} extends that base.
}

◊figure{
◊marginnote["mn-nat-base-hierarchy"]{
  Pseudocode of a class hierarchy in which the ◊code{Natural} class is the base and the ◊code{Integer} class extends it.
}
◊source-code["pseudo-code"]{
class Natural
  value : UInt

  def make(value : UInt) : Natural = ◊ellipsis{}
  def +(other : Natural) : Natural = Natural.make(self.value + other.value)
end

class Integer <: Natural
  negative? : Bool

  def make(value : Natural, negative? : Bool) : Integer = ◊ellipsis{}
  def magnitude() : Natural = self.value
  def +(other : Integer) : Integer = ◊ellipsis{}
end
}
}

◊p{
  I'm sure you immediately spotted a problem with this design: we inversed the hierarchy, breaking the ◊quoted{is a} relationship!
  We claim that all integers are also naturals, but that's false.
  The design violates the ◊a[#:href "https://en.wikipedia.org/wiki/Liskov_substitution_principle"]{Liskov substitution principle}: passing an ◊code{Integer} to a function that expects a ◊code{Natural} can produce incorrect results:
}

◊source-code["pseudo-code"]{
> Natural.make(5) + Integer.make(10, true) // 5 + -10
15 // ouch
}

◊p{
  Enlightened by this failure, we reverse the inheritance hierarchy.
  ◊code{Integer} becomes our base class, and ◊code{Natural} extends it.
}

◊figure{
◊marginnote["mn-integer-base"]{
  Pseudocode of a class hierarchy in which the ◊code{Integer} class is the base and the ◊code{Natural} class extends it.
}
◊source-code["pseudo-code"]{
class Integer
  value : UInt
  negative? : Bool

  def make(value : Natural, negative? : Bool) = ◊ellipsis{}
  def magnitude() : Natural = self.value
  def +(other : Integer) : Integer = ◊ellipsis{}
end

class Natural <: Integer
  def make(value : UInt) : Natural = super.make(value, false)
  def +(other : Natural) : Natural = ◊ellipsis{}
end
}
}

◊p{
  Once the initial excitement dissipates, we face a new issue.
  The simplest case, the ◊code{Natural} numbers, must have the same representation as the more complex type, ◊code{Integers}.
  The problem becomes more apparent if we add more types to the tower, such as ◊code{Rational}.
  Instead of starting with the simplest case and building from it, we started with the most complicated one and made everything else a special case.
  That's why the original incorrect design was so compelling: we moved from simpler to more complex types, not the other way around!
}

◊p{
  Another design option is to give up on concrete type hierarchies and clamp all number types under a single interface.
}

◊figure{
◊marginnote["mn-number-interface"]{
Pseudocode of a type hierarchy where all numeric types implement the same interface.
}
◊source-code["pseudo-code"]{
interface Number
  def +(n : Natural) : Number
  def -(n : Natural) : Number
  // ◊ellipsis{}
  def +(i : Integer) : Number
  def -(i : Integer) : Number
  // ◊ellipsis{}
end

class Natural <: Number
  // a lot of boring code ◊ellipsis{}
end

class Integer <: Number
  // a lot of boring code ◊ellipsis{}
end
}
}

◊p{
  This approach is the most versatile, but it has many drawbacks:
}
◊ul[#:class "arrows"]{
◊li{
  The programmer must write a lot of boilerplate code.
}
◊li{
  All types in the hierarchy need to know about one another.
  Adding a new type requires modifying all other types.
}
◊li{
  Adding a new operation on numbers requires modifying all the classes.
}
}

◊p{
  It's time to abandon our blunt OOP tools and start from the first principles.
}

◊subsection-title["the-functional-approach"]{The functional approach}

◊p{
  The object-oriented approach obsesses around encoding ◊quoted{is a} relations among types as a rigid hierarchy and trying to make it behave coherently.
}
◊p{
  We'll use the approach mathematicians employ: we start with the simplest structure and gradually build more complex structures out of basic ones.
  This approach is equivalent to using composition instead of inheritance in the OOP world.
}

◊figure{
◊marginnote["mn-functional-nums"]{
  Modeling the ◊code{Natural} and ◊code{Integer} numeric types in Haskell.
}
◊source-code["haskell"]{
-- Each natural is either zero or a successor of a smaller number.
data Natural = Zero | Succ Natural -- ◊circled-ref[1]

-- There are two disjoint classes of integers:
-- ◊math{n} and ◊math{-1 - n} for all natural values of ◊math{n}.
data Integer = NonNegative Natural | MinusOneMinus Natural -- ◊circled-ref[2]

-- We model the `is a' relation as a pure total function
-- mapping naturals to integers.
int_of_nat :: Natural -> Integer -- ◊circled-ref[3]
int_of_nat = NonNegative

-- We can model the reverse relation as a partial function
-- mapping integers to naturals.
nat_of_int :: Integer -> Maybe Natural
nat_of_int (NonNegative n) = Just n
nat_of_int (MinusOneMinus _) = Nothing

plus_nat :: Natural -> Natural -> Natural
plus_nat n Zero = n
plus_nat n (Succ m) = Succ (plus_nat n m)

plus_int :: Integer -> Integer -> Integer
plus_int = ◊ellipsis{}

minus_int :: Integer -> Integer -> Integer
minus_int = ◊ellipsis{}
}
}

◊ol-circled{
  ◊li{
    According to ◊a[#:href "https://en.wikipedia.org/wiki/Peano_axioms"]{Peano}, a natural number is either a zero or a successor of a smaller natural number.
    This definition is equivalent to the ◊a[#:href "https://en.wikipedia.org/wiki/Unary_numeral_system"]{unary numeral system}, which is inefficient for computation, but convenient for demonstration.
  }
  ◊li{
    An integer number is either a non-negative natural number ◊math{n} or a negative number ◊math{-1 - n}, where ◊math{n} is a natural number.
    Note that with this definition, each integer has a unique representation.
  }
  ◊li{
    We encode the ◊quoted{is a} relation between numeric types as a pure total function.
    OOP languages usually generate these conversion functions automatically and apply them implicitly.
  }
}

◊p{
  Note how modular this implementation is.
  Naturals can live in a separate module and don't need to know about the existence of integers.
  We can easily change the implementation of naturals (e.g., use the more efficient ◊a[#:href "https://en.wikipedia.org/wiki/Binary_number"]{binary representation}) or add more numerit types (e.g., ◊code{Rational}s) without breaking other code.
}

◊p{
  However, the design has a flaw: we lost the ability to operate on numbers of different types.
  We can add a universal ◊code{Number} type to reclaim this property.
}

◊figure{
◊marginnote["mn-universal-number"]{
  Modeling the numeric tower in Haskell with a sum type.
}
◊source-code["haskell"]{
-- The sum type encoding all number types.
data Number = Nat Natural | Int Integer

-- Adds arbitrary numbers.
plus :: Number -> Number -> Number
plus = ◊ellipsis{}

-- Subtracts arbitrary numbers.
minus :: Number -> Number -> Number
minus = ◊ellipsis{}
}
}

◊p{
  This design might seem like a re-iteration of the ◊code{Number} interface story from the OO world, but it's not:
}
◊ul[#:class "arrows"]{
◊li{
  We have many opportunities to reduce the boilerplate code to the bare minimum.
  We will discuss these opportunities shortly.
}
◊li{
  The module implementing ◊code{Naturals} don't need to know about ◊code{Integers} or ◊code{Numbers}.
}
◊li{
  We don't need to modify existing code when we add new functions operating on numbers.
}
}

◊p{
  To address the boilerplate issue, we'll introduce the numeric type ◊em{promotion} operation.
  When we add two numbers of different type, we convert the simpler type to the more complex one using the previously discussed type converion functions.
  We then apply the binary operator dealing with numbers of the same promoted type.
  Finally, we simplify (◊quoted{demote}) the result to the simplest type that can hold the value.
}

◊p{
  I find this concept intuitive because it's how I deal with numbers myself.
  When I add ◊math{1} to ◊math{½}, I ◊quoted{promote} the unit to the rational number ◊math{2/2} and then execute the addition on rationals to get ◊math{3/2}.
  And when I add ◊math{5} to ◊math{-3}, I temporarily treat ◊math{5} as an integer, execute the integer addition to get ◊math{2}, and then treat the result as a natural number.
}

◊figure{
◊marginnote["mn-universal-number"]{
  Reducing the boilerplate with type promotion.
}
◊source-code["haskell"]{
data Number = Nat Natural | Int Integer

-- Promotes the argumets to the largest common type.
promote :: (Number, Number) -> (Number, Number)
promote (Nat n, Int m) = (Int (int_of_nat n), Int m) 
promote (Int n, Nat m) = (Int n, Int (int_of_nat m))
promote x = x

-- Reduces the number to its most canonical form.
simplify :: Number -> Number
simplify (Int (NonNegative n)) = Nat n
simplify x = x

type BinaryOp = Number -> Number -> Number

-- Implements a total binary operation given a kernel defined
-- only on numbers of the same type.
impl_binary_op :: BinaryOp -> BinaryOp
impl_binary_op kernel x y = let (x', y') = promote (x, y)
                            in simplify (kernel x' y')

-- Adds arbitrary numbers.
plus :: Number -> Number -> Number
plus x y = impl_binary_op helper x y
  where helper (Nat n) (Nat m) = Nat (plus_nat n m)
        helper (Int n) (Int m) = Int (plus_int n m)
        helper _ _ = undefined

-- Subtracts arbitrary numbers.
minus :: Number -> Number -> Number
minus x y = impl_binary_op helper x y
  where helper (Nat n) (Nat m) = Int (minus_int (int_of_nat n) (int_of_nat m))
        helper (Int n) (Int m) = Int (minus_int n m)
        helper _ _ = undefined
}
}

◊p{
  The ◊code{impl_binary_op} function captures the promote/execute/simplify pattern.
  Concrete binary operators (◊code{plus}, ◊code{minus}, etc.) need to deal only with numbers of the same type.
}

}

◊section{
◊section-title["conclusion"]{Conclusion}
◊p{
  We started with a ◊a[#:href "#the-numeric-tower"]{precisely defined hierarchy} of mathematical objects and couldn't find an acceptable way to model them as a class hierarchy.
  We then pivoted and went with the constructive math path, organizing our code around ◊quoted{value spaces} instead of concept hierarchies.
}
}

