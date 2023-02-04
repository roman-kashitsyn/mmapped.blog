#lang pollen

◊(define-meta title "When Rust hurts")
◊(define-meta keywords "rust")
◊(define-meta summary "Why I am not enjoying programming in Rust.")
◊(define-meta doc-publish-date "2023-02-10")
◊(define-meta doc-updated-date "2023-02-10")

◊epigraph{
  ◊blockquote{
    ◊p{Functional programming deals with values; imperative programming deals with objects.}
    ◊footer{Alexander Stepanov, ◊quoted{Elements of Programming}, p. 5}
  }
}


◊section{
◊section-title["intro"]{Introduction}
◊p{
  ◊a[#:href "https://www.rust-lang.org/"]{Rust} is in a sweet spot in the language design space.
  It allows us to build efficient and memory-safe programs with succinct, portable, and sometimes even pretty code.
}
◊p{
  However, it is not all roses and sunshine.
  Memory management details often stay in your way and make the code uglier or more repetative than it could be in a ◊quoted{higher-level} programming language, such as ◊a[#:href "https://www.haskell.org/"]{Haskell} or ◊a[#:href "https://ocaml.org"]{OCaml}.
  In almost all the cases, these issues are not defects of the compiler but direct consequences of the design choices the Rust team made.
}
◊p{
  This article goes into detail on how frustrating Rust can be if you approach it with a functional programming mindset and why Rust has no choice but frustrate you.
}
}


◊section{
◊section-title["objects-values-references"]{Objects, values, and references}
◊epigraph{
  ◊blockquote{
    ◊p{
      Values and objects play complementary roles.
      Values are unchanging and independent of any particular implementation in the computer.
      Objects are changeable and have computer-specific implementations.
    }
    ◊footer{Alexander Stepanov, ◊quoted{Elements of Programming}, p. 5}
  }
}

◊p{
  It is helpful to understand the difference between objects, values, and references before we dive deeper into Rust.
}
◊p{
  In the context of this article, ◊em{values} are entities with a distinct identity such as numbers and strings.
  An ◊em{object} is a representation of a value in the computer memory.
  A ◊em{reference} is the address of an object that we can use to access the object or its parts.
}
◊p{
  System programming languages, such as C++ and Rust, force the programmer to deal with the distinction between objects and references.
  This distinction allows us to write blanzingly fast code, but it comes with a high price: it is a never-ending source of bugs.
  It is almost always a bug to modify the contents of an object if some other part of the program references that object.
  There are multiple ways to address this issue:
}
◊ul[#:class "arrows"]{
  ◊li{
    Ignore the problem and trust the programmer.
    Most traditional system programming languages, such as C++, took this path.
  }
  ◊li{
    Make all objects immutable.
    This option is the basis for pure functional programming techniques in Haskell and ◊a[#:href "https://clojure.org/"]{Clojure}.
  }
  ◊li{
    Adopt a ◊a[#:href "https://en.wikipedia.org/wiki/Substructural_type_system"]{type system} preventing modification of referenced objects.
    Languages such as ◊a[#:href "https://www.cs.bu.edu/~hwxi/atslangweb/"]{ATS} and Rust embarked on this journey.
  }
  ◊li{
    Ban references altogether.
    The ◊a[#:href "https://www.val-lang.dev/"]{Val} language explores this style of programming.
  }
}
◊p{
  The distinction between objects and references is also a source of accidental complexity and choice explosion.
  A language with immutable objects and automatic memory management allows us to stay ignorant of this distinction and treat everything as a value (at least in pure code).
  A unified storage model frees up programmer's mental resources and enables the programmer to write more expressive and elegant code.
  What we gain in convenience, however, we lose in efficiency: pure functional programs often require more memory, can become unresponsive, and are harder to optimize (your mileage may vary).
}
}


◊section{
◊section-title["abstraction-is-painful"]{When abstraction is painful}
◊p{
  Manual memory management and the ownership-aware type system interfere with our ability to break down the code into smaller pieces.
}

◊subsection-title["common-expression-elimination"]{Common expression elimination}
◊p{
  Extracting common expression into a variable can pose unexpected challenges.
  Let us start with the following snippet of code.
}
◊source-code["rust"]{
f(compute_x());
g(compute_x());
}
◊p{
  Look, ◊code{compute_x()} appears twice!
  Our first instinct is to assign a name to the expression and use it twice:
}
◊source-code["good"]{
let ◊b{x} = compute_x();
f(◊b{x});
g(◊b{x});
}
◊p{
  However, our first naive version way will not compile if the type of x does not implement the ◊code{Copy} trait.
  We must write the following expression instead:
}
◊source-code["good"]{
let x = compute_x();
f(x◊b{.clone()});
g(x);
}
◊p{
  We can see the extra verbosity in a positive light if we care about extra memory allocations because copying memory became explicit.
  But it can be quite annoying in practice, nevertheless, especially when you go and add ◊code{h(x)} two months later.
}

◊source-code["bad"]{
let x = compute_x();
f(x.clone());
g(x);

// fifty lines of code...

h(x); // ← won’t compile, you need scroll up and update g(x).
}


◊subsection-title["monomorphism-restriction"]{Monomorphism restriction}
◊p{
  In Rust, ◊code{let x = y;} does not always mean that ◊code{x} is the same thing as ◊code{y}.
  One example when this natural property breaks is when ◊code{y} is an overloaded function.
}
◊p{
  For example, let us define a short name for an overloaded function.
}
◊source-code["bad"]{
// Do we have to type "MyType::from" every time?
// How about introducing an alias?
let x = MyType::from(b"bytes");
let y = MyType::from("string");

// Nope, Rust won't let us.
let f = MyType::from;
let x = f(b"bytes");
let y = f("string");
//      - ^^^^^^^^ expected slice `[u8]`, found `str`
//      |
//      arguments to this function are incorrect
}
◊p{
  The snippet does not compile because the compiler will bind ◊code{f} to a particular instance of ◊code{MyType::from}, not to a polymorphic function.
  We have to make ◊code{f} polymorphic explicitly.
}

◊source-code["good"]{
// Compiles fine, but is longer than the original.
fn f<T: Into<MyType>>(t: T) -> MyType { t.into() }

let x = f(b"bytes");
let y = f("string");
}

◊p{
  Haskell programmers might find this problem familiar: it looks suspiciously similar to the dreaded ◊a[#:href "https://wiki.haskell.org/Monomorphism_restriction"]{monomorphism restriction}!
  Unfortunately, ◊code{rustc} does not have the ◊code-ref["https://typeclasses.com/ghc/no-monomorphism-restriction"]{NoMonomorphismRestriction} pragma.
}

◊subsection-title["functional-abstraction"]{Functional abstraction}
◊p{
Factoring code into a function might be harder than you expect because the compiler might not be able to reason about aliasing accross function boundaries.
Let's say we have the following code.
}
◊source-code["rust"]{
impl State {
  fn tick(&mut self) {
    self.state = match self.state {
      Ping(s) => { self.x += 1; Pong(s) }
      Pong(s) => { self.x += 1; Ping(s) }
    }
  }
}
}
◊p{
  The ◊code{self.x += 1} statement appears multiple times.
  Why not extract it into into a method◊ellipsis{}
}
◊source-code["bad"]{
impl State {
  fn tick(&mut self) {
    self.state = match self.state {
      Ping(s) => { self.inc(); Pong(s) } // ← compile error
      Pong(s) => { self.inc(); Ping(s) } // ← compile error
    }
  }

  fn inc(&mut self) {
    self.x += 1;
  }
}
}
◊p{
  Rust will bark at us because the method attempts to re-borrow ◊code{self} exclusively while the surrounding context still holds a mutable reference to ◊code{self.state}.
}
◊p{
  Rust 2021 edition implemented ◊a[#:href "https://doc.rust-lang.org/edition-guide/rust-2021/disjoint-capture-in-closures.html"]{disjoint capture} to address a similar issue with closures.
  Before Rust 2021, code that looked like ◊code{x.f.m(|| x.y)} might not compile but manually inlining ◊code{m} and the closure would resolve the error.
  For example, imagine we have a struct that owns a map and a default value for map entries.
}
◊source-code["bad"]{
struct S { map: HashMap<i64, String>, def: String }

impl S {
  fn ensure_has_entry(&mut self, key: i64) {
    // Doesn't compile with Rust 2018:
    self.map.entry(key).or_insert_with(|| self.def.clone());
// |         ------            -------------- ^^ ---- second borrow occurs...
// |         |                 |              |
// |         |                 |              immutable borrow occurs here
// |         |                 mutable borrow later used by call
// |         mutable borrow occurs here
  }
}
}

◊p{
  However, if we inline the definition of ◊code{or_insert_with} and the lambda function, the compiler can finally see that the borrowing rules are not broken.
}

◊source-code["good"]{
struct S { map: HashMap<i64, String>, def: String }

impl S {
  fn ensure_has_entry(&mut self, key: i64) {
    use std::collections::hash_map::Entry::*;
    ◊em{// This version is more verbose, but it works with Rust 2018.}
    match self.map.entry(key) {
      Occupied(mut e) => e.get_mut(),
      Vacant(mut e) => e.insert(self.def.clone()),
    };
  }
}
}

◊p{
  When someone asks you ◊quoted{what tricks Rust closures can do that named functions cannot?}, you will know the answer: they can capture only the fields they use.
}

◊subsection-title["newtype-abstrction"]{Newtype abstraction}

◊p{
  The ◊a[#:href "https://doc.rust-lang.org/rust-by-example/generics/new_types.html"]{new type idiom}◊sidenote["sn-strong-typedef"]{
    Folks in the C++ land call this idiom ◊a[#:href "https://www.boost.org/doc/libs/1_42_0/boost/strong_typedef.hpp"]{strong typedef}.
  } in Rust allows the programmer to give a new identity to an existing type.
  The idiom's name comes from the Haskell's ◊code-ref["https://wiki.haskell.org/Newtype"]{newtype} keyword.
}
◊p{
  One of the common uses of this idiom is to work around the ◊a[#:href "#no-orphan-instances"]{orphan rules} and define trait implementation for the aliased type.
  For example, the following code defines an new type that displays byte vectors in hex.
}

◊source-code["rust"]{
struct Hex(Vec<u8>);

impl std::fmt::Display for Hex {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    self.0.iter().try_for_each(|b| write!(f, "{:02x}", b))
  }
}

println!("{}", Hex((0..32).collect()));
◊em{// => 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f}
}

◊p{
  The new type idiom is efficient: the representation of the ◊code{Hex} type in machine's memory is identical to those of ◊code{Vec<u8>}.
  However, the compiler does not treat our new type as a strong alias for ◊code{Vec<u8>}, despite the identical representation.
  For example, we cannot safely transform ◊code{Vec<Hex>} to ◊code{Vec<Vec<u8>>} and back without reallocating the outer vector.
  We also cannot safely coerce ◊code{&Vec<u8>} to ◊code{&Hex} without copying the bytes.
}

◊source-code["rust"]{
fn complex_function(bytes: &Vec<u8>) {
  // ◊ellipsis{} a lot of code ◊ellipsis{}

  println!("{}", &Hex(bytes));        // That does not work.
  println!("{}", Hex(bytes.clone())); // That works but is slow.

  // ◊ellipsis{} a lot of code ◊ellipsis{}
}
}

◊p{
  Overall, the new type idiom is a leaky abstraction because it is a convention, not a first-class language feature.
  If you wonder how Haskell solved this problem, I highly recommend watching the ◊a[#:href "https://www.youtube.com/watch?v=iLZdN-R1JGk"]{Safe, Zero-Cost Coercions in Haskell} talk by Simon Peyton Jones.
}

◊subsection-title["views-and-bundles"]{Views and bundles}
◊p{
  Each time the programmer describes a struct field or passes an argument to a function, she must decide whether the field/argument should be ◊a[#:href "#objects-values-references"]{an object or a reference}.
  Or maybe the best option is to ◊a[#:href "https://doc.rust-lang.org/std/borrow/enum.Cow.html"]{decide at runtime}?
  That is a lot of decision making!
  Unfortunately, sometimes there is no single optimal choice.
  On such occasions, we grit our teeth and define several versions of the same type with slightly different field types.
}

◊p{
  Most functions in Rust take arguments by reference and return results as a self-contained object◊sidenote["sn-view-exceptions"]{
    There are plenty of exceptions, of course.
    Sometimes we pass arguments by value if making a copy is cheap or if the function can efficiently reuse its input to produce the result.
    Some functions return references into one of their arguments.
  }.
  This pattern is so common that it might be helpful to define new terms for it.
  I call input types with lifetime arguments ◊em{views} because they are optimal for inspecting data.
  I call regular output types ◊em{bundles} because they are self-contained.
}

◊p{
  The following snippet comes from the (sunset) ◊a[#:href "https://github.com/bytecodealliance/lucet"]{Lucet} WebAssembly runtime.
}
◊source-code["rust"]{
◊em{/// A WebAssembly global along with its export specification.}
◊em{/// The lifetime parameter exists to support zero-copy deserialization}
◊em{/// for the `&str` fields at the leaves of the structure.}
◊em{/// For a variant with owned types at the leaves, see `OwnedGlobalSpec`.}
pub struct ◊code-ref["https://github.com/bytecodealliance/lucet/blob/51fb1ed414fe44f842db437d94abb6eb439d7c92/lucet-module/src/globals.rs#L8"]{GlobalSpec}<'a> {
    global: Global<'a>,
    export_names: Vec<&'a str>,
}

◊ellipsis{}

◊em{/// A variant of `GlobalSpec` with owned strings throughout.}
◊em{/// This type is useful when directly building up a value to be serialized.}
pub struct ◊code-ref["https://github.com/bytecodealliance/lucet/blob/51fb1ed414fe44f842db437d94abb6eb439d7c92/lucet-module/src/globals.rs#L112"]{OwnedGlobalSpec} {
    global: OwnedGlobal,
    export_names: Vec<String>,
}
}
◊p{
  The authors duplicated the ◊code{GlobalSpec} data structure to support two use cases:
}
◊ul[#:class "arrows"]{
  ◊li{
    ◊code{GlobalSpec<'a>} is a ◊em{view} object that the code authors parse from a byte buffer.
    Individual fields of this view point back to the relevant regions of the buffer.
    This representation is helpful for functions that need to inspect values of type ◊code{GlobalSpec} without modifying them.
  }
  ◊li{
    ◊code{OwnedGlobalSpec} is a ◊em{bundle}: it does not contain references to other data structures.
    This representation is helpful for functions that construct values of type ◊code{GlobalSpec} and pass them around or put into a container.
  }
}

}


◊section{
◊section-title["composition-is-painful"]{When composition is painful}
◊p{
  Combining a working program from smaller pieces can be frustrating in Rust.
}

◊subsection-title["object-composition"]{Object composition}
◊p{
  When programmers have two distinct values, they often want to combine them into a single struct.
  Sounds easy, right? Not in Rust.
}
◊p{
  Assume we have an object ◊code{Db} that has a method giving you another object, ◊code{Snapshot<'a>}.
  The lifetime of the snapshot depends on the lifetime of the database.
}
◊source-code["bad"]{
struct Db { /* ◊ellipsis{} */ }

struct Snapshot<'a> { /* ◊ellipsis{} */ }

impl Db { fn snapshot<'a>(&'a self) -> Snapshot<'a>; }

// There is no way to define the following struct:

struct DbSnapshot {
  db: Box<Db>,
  snapshot: Snapshot<'a>,
}
}

◊p{
  Rust folks call this arragement ◊quoted{sibling pointers}.
  The Rust language forbids sibling pointers because they undermine the Rust's safety model.
}
◊p{
  As we discussed in the ◊a[#:href "#objects-values-references"]{Objects, values, and references} section, modifying a referenced object is usually a bug.
  In our case, the ◊code{snapshot} object might depend on the physical location of the ◊code{db} object.
  If we move the ◊code{DbSnapshot} as a whole, the physical location of the ◊code{db} field will change, corrupting references in the ◊code{snapshot} object.
}

◊subsection-title["pattern-matching-boxes"]{Pattern matching cannot see through boxes}
◊p{
  In Rust, we cannot pattern-match on boxed types such as ◊code{Box}, ◊code{Arc}, ◊code{String}, and ◊code{Vec}.
  This restriction is always a deal-breaker because we cannot avoid boxing when we define recursive data types.
}

◊p{
  For example, let us try to match a vector of strings.
}

◊source-code["bad"]{
let x = vec!["a".to_string(), "b".to_string()];
match x {
//    - help: consider slicing here: `x[..]`
    ["a", "b"] => println!("OK"),
//  ^^^^^^^^^^ pattern cannot match with input type `Vec<String>`
    _ => (),
}
}

◊p{
  First, we can't match a vector, only on a slice.
  Luckily, the compiler suggests us an easy fix: we need to replace ◊code{x} with ◊code{x[..]} in the ◊code{match} expression.
  Let us give it a try.
}

◊source-code["bad"]{
let x = vec!["a".to_string(), "b".to_string()];
match x[..] {
//    ----- this expression has type `[String]`
    ["a", "b"] => println!("OK"),
//   ^^^ expected struct `String`, found `&str`
    _ => (),
}
}

◊p{
  As you can see, removing one layer of boxes is not enough to make the compiler happy.
  We also need to unbox the strings inside of the vector, which is not possible without allocating a new vector:
}

◊source-code["good"]{
let x = vec!["a".to_string(), "b".to_string()];
// We have to allocate new storage.
let x_for_match: Vec<_> = x.iter().map(|s| s.as_str()).collect();
match &x_for_match[..] {
    ["a", "b"] => println!("OK"), // this compiles
    _ => (),
}
}
◊p{
  Forget about ◊a[#:href "https://www.cs.tufts.edu/comp/150FP/archive/chris-okasaki/redblack99.pdf"]{balancing Red-Black trees} in five lines of code in Rust.
}

◊subsection-title["no-orphan-instances"]{No orphan instances}
◊p{
  Rust uses ◊a[#:href "https://doc.rust-lang.org/reference/items/implementations.html?highlight=orphan#orphan-rules"]{orphan rules} to decide whether a type can implement a trait.
  For non-generic types, these rules forbid implementating a trait for the type outside of packages defining the trait or the type.
  In other words, either the package defining the trait must depend on the package defining the type or vice versa.
}
◊p{
  This rule makes it easy for the compiler to guarantee ◊em{coherence}, which is a smart way to say that all parts of you program see the same implementation of the trait for a particular type.
  In exchange, this rule makes your life unnecessarily complicated.
  Orphan rules significantly complicate integrating traits and types coming from an unrelated libraries.
}
◊p{
  One example that pops up often is data encoding.
  Imagine that we want to encode our data as ◊a[#:href "https://developers.google.com/protocol-buffers"]{Protobuf}.
  We define our message types in a bunch of ◊code{.proto} files and let the ◊a[#:href "https://github.com/tokio-rs/prost"]{Prost} library generate the corresponding Rust definitions.
  These definitions have a lot of ◊code{Options}, so we do not want to use these definitions directly in our program.
  Instead, we use the powerful Rust's typesystem to define types encoding invariants and define explicit conversions between loosely typed externally visible protobuf types and internal rich types◊sidenote["sn-protobuf-contamination"]{
    If you find this step non-intuitive, you might find the ◊a[#:href "https://reasonablypolymorphic.com/blog/protos-are-wrong/index.html#protobuffers-contaminate-codebases"]{Protobuffers Contaminate Codebases} section of Sandy Maguire's ◊a[#:href "https://reasonablypolymorphic.com/blog/protos-are-wrong/index.html"]{Protobuffers Are Wrong} article interesting.
  }.
  The relation between rich types and their encodings is begging to be a trait.
}
◊source-code["rust"]{
// In the `my-protobuf` package
pub trait ◊b{AsProto} {
  ◊em{/// The protobuf struct corresponding to this type.}
  type Pb;
  ◊em{/// The protobuf decoding error.}
  type Error;

  fn to_proto(self) -> Self::Pb;

  fn from_proto(Self::Pb) -> Result<Self, Self::Error>;
}
}


◊p{
  Do not get me wrong: orphan rules are a great default; Haskell folks also frown upon ◊a[#:href "https://wiki.haskell.org/Orphan_instance"]{orphan instances}.
  It is the inability to escape these rules that makes me sad.
  In large codebases, decomposing large packages into smaller pieces and maintaining shallow dependencies graphs are the only path to acceptable compilation speed.
}
}


◊section{
◊section-title["fearless-concurrency-lie"]{Fearless concurrency is a lie}
◊p{
  The Rust team coined the term ◊a[#:href "https://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html"]{Fearless Concurrency} to indicate that Rust helps you avoid common pitfalls associated with parallel and concurrent programming.
}

◊subsection-title["deadlocks"]{Deadlocks}

◊subsection-title["filesystem-shared-resource"]{Filesystem is a shared resource}

◊subsection-title["implicit-arguments"]{Implicit arguments}

}