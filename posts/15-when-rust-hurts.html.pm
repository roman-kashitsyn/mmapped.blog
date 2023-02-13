#lang pollen

◊(define-meta title "When Rust hurts")
◊(define-meta keywords "rust")
◊(define-meta summary "Why I am not enjoying programming in Rust.")
◊(define-meta doc-publish-date "2023-02-14")
◊(define-meta doc-updated-date "2023-02-14")

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
  It allows us to build efficient and memory-safe programs with concise, portable, and sometimes even pretty code.
}
◊p{
  However, it is not all roses and sunshine.
  Memory management details often stay in your way and make the code uglier or more repetitive than it could be in a ◊quoted{higher-level} programming language, such as ◊a[#:href "https://www.haskell.org/"]{Haskell} or ◊a[#:href "https://ocaml.org"]{OCaml}.
  In almost all cases, these issues are not defects of the compiler but direct consequences of the Rust's team design choices.
}
◊p{
  This article details on how frustrating Rust can be if you approach it with a functional programming mindset and why Rust has no choice but to frustrate you.
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
  Understanding the difference between objects, values, and references is helpful before diving deeper into Rust.
}
◊p{
  In the context of this article, ◊em{values} are entities with distinct identities, such as numbers and strings.
  An ◊em{object} is a representation of a value in the computer memory.
  A ◊em{reference} is the address of an object that we can use to access the object or its parts.
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-objects-values-refs"]{
  A visualization of values, objects, and references on an example of an integer in a 16-bit computer.
  The value is number five, which has no inherent type.
  The object is a 16-bit integer stored at address ◊code{0x0300} (◊a[#:href "https://en.wikipedia.org/wiki/Endianness"]{little-endian}).
  The memory contains a ◊em{reference} to the number, represented as a pointer to address ◊code{0x0300}.
}
◊(embed-svg "images/15-objects-values-references.svg")
}
◊p{
  System programming languages, such as C++ and Rust, force the programmer to deal with the distinction between objects and references.
  This distinction allows us to write blazingly fast code, but it comes with a high price: it is a never-ending source of bugs.
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
  A unified storage model frees up a programmer's mental resources and enables the programmer to write more expressive and elegant code.
  However, what we gain in convenience, we lose in efficiency: pure functional programs often require more memory, can become unresponsive, and are harder to optimize (your mileage may vary).
}
}


◊section{
◊section-title["abstraction-is-painful"]{When abstraction is painful}
◊p{
  Manual memory management and the ownership-aware type system interfere with our ability to break down the code into smaller pieces.
}

◊subsection-title["common-expression-elimination"]{Common expression elimination}
◊p{
  Extracting a common expression into a variable can pose unexpected challenges.
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
  However, our first naive version will only compile if the type of x implements the ◊code{Copy} trait.
  We must write the following expression instead:
}
◊source-code["good"]{
let x = compute_x();
f(x◊b{.clone()});
g(x);
}
◊p{
  We can see the extra verbosity in a positive light if we care about extra memory allocations because copying memory became explicit.
  But it can be quite annoying in practice, especially when you add ◊code{h(x)} two months later.
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
  One example of when this natural property breaks is when ◊code{y} is an overloaded function.
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
Factoring code into a function might be harder than you expect because the compiler cannot reason about aliasing across function boundaries.
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
  Why not extract it into a method◊ellipsis{}
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
  However, if we inline the definition of ◊code{or_insert_with} and the lambda function, the compiler can finally see that the borrowing rules hold.
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
  When someone asks you, ◊quoted{what tricks can Rust closures do that named functions cannot?} you will know the answer: they can capture only the fields they use.
}

◊subsection-title["newtype-abstrction"]{Newtype abstraction}

◊p{
  The ◊a[#:href "https://doc.rust-lang.org/rust-by-example/generics/new_types.html"]{new type idiom}◊sidenote["sn-strong-typedef"]{
    Folks in the C++ land call this idiom ◊a[#:href "https://www.boost.org/doc/libs/1_42_0/boost/strong_typedef.hpp"]{strong typedef}.
  } in Rust allows the programmer to give a new identity to an existing type.
  The idiom's name comes from Haskell's ◊code-ref["https://wiki.haskell.org/Newtype"]{newtype} keyword.
}
◊p{
  One of the common uses of this idiom is to work around the ◊a[#:href "#orphan-rules"]{orphan rules} and define trait implementation for the aliased type.
  For example, the following code defines a new type that displays byte vectors in hex.
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
  The new type idiom is efficient: the representation of the ◊code{Hex} type in the machine's memory is identical to those of ◊code{Vec<u8>}.
  However, despite the identical representation, the compiler does not treat our new type as a strong alias for ◊code{Vec<u8>}.
  For example, we cannot safely transform ◊code{Vec<Hex>} to ◊code{Vec<Vec<u8>>} and back without reallocating the outer vector.
  Also, without copying the bytes, we cannot safely coerce ◊code{&Vec<u8>} to ◊code{&Hex}.
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
  Overall, the newtype idiom is a leaky abstraction because it is a convention, not a first-class language feature.
  If you wonder how Haskell solved this problem, I recommend watching the ◊a[#:href "https://www.youtube.com/watch?v=iLZdN-R1JGk"]{Safe, Zero-Cost Coercions in Haskell} talk by Simon Peyton Jones.
}

◊subsection-title["views-and-bundles"]{Views and bundles}
◊p{
  Each time the programmer describes a struct field or passes an argument to a function, she must decide whether the field/argument should be ◊a[#:href "#objects-values-references"]{an object or a reference}.
  Or maybe the best option is to ◊a[#:href "https://doc.rust-lang.org/std/borrow/enum.Cow.html"]{decide at runtime}?
  That is a lot of decision-making!
  Unfortunately, sometimes there is no optimal choice.
  On such occasions, we grit our teeth and define several versions of the same type with slightly different field types.
}

◊p{
  Most functions in Rust take arguments by reference and return results as a self-contained object◊sidenote["sn-view-exceptions"]{
    There are plenty of exceptions, of course.
    Sometimes we pass arguments by value if making a copy is cheap or the function can efficiently reuse its input to produce the result.
    Some functions return references to one of their arguments.
  }.
  This pattern is so common that it might be helpful to define new terms.
  I call input types with lifetime parameters ◊em{views} because they are optimal for inspecting data.
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
    This representation is helpful for functions that construct values of type ◊code{GlobalSpec} and pass them around or put them into a container.
  }
}
◊p{
  In a language with automatic memory management, we can combine the efficiency of ◊code{GlobalSpec<'a>} with the versatility of ◊code{OwnedGlobalSpec} in a single type declaration.
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
  Sounds easy? Not in Rust.
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
  Rust folks call this arrangement ◊quoted{sibling pointers}.
  The Rust language forbids sibling pointers because they undermine Rust's safety model.
}
◊p{
  As discussed in the ◊a[#:href "#objects-values-references"]{Objects, values, and references} section, modifying a referenced object is usually a bug.
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
  Luckily, the compiler suggests an easy fix: we must replace ◊code{x} with ◊code{x[..]} in the ◊code{match} expression.
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

◊subsection-title["orphan-rules"]{Orphan rules}
◊p{
  Rust uses ◊a[#:href "https://doc.rust-lang.org/reference/items/implementations.html?highlight=orphan#orphan-rules"]{orphan rules} to decide whether a type can implement a trait.
  For non-generic types, these rules forbid implementing a trait for a type outside of crates defining the trait or the type.
  In other words, the package defining the trait must depend on the package defining the type or vice versa.
}
◊figure[#:class "grayscale-diagram"]{
◊marginnote["mn-orphan-rules"]{
  Orphan rules in Rust demand that a trait implementation resides in the crate defining the trait or the crate defining the type.
  Boxes represent separate crates, arrows◊mdash{}crate dependencies.
}
◊(embed-svg "images/15-orphan-rules.svg")
}
◊p{
  These rules make it easy for the compiler to guarantee ◊em{coherence}, which is a smart way to say that all parts of your program see the same trait implementation for a particular type.
  In exchange, this rule makes your life unnecessarily complicated.
  Orphan rules significantly complicate integrating traits and types coming from an unrelated library.
}
◊p{
  One example is traits we want to use only in tests, such as ◊code-ref["https://altsysrq.github.io/rustdoc/proptest/1.0.0/proptest/arbitrary/trait.Arbitrary.html"]{Arbitrary} from the ◊a[#:href "https://crates.io/crates/proptest"]{proptest} package.
  We can save a lot of typing if the compiler derives implementations for types from our package, but we want our production code to be independent of the ◊code{proptest} package.
  In the perfect setup, all the ◊code{Arbitrary} implementations would go into a separate test-only package.
  Unfortunately, orphan rules oppose this arrangement, forcing us to bite the bullet and write proptest strategies ◊a[#:href "https://altsysrq.github.io/proptest-book/proptest/tutorial/macro-prop-compose.html"]{manually} instead◊sidenote["sn-orphan-workaround"]{
    There are workarounds for this issue, such as using ◊a[#:href "https://doc.rust-lang.org/cargo/reference/features.html"]{cargo features} and conditional compilation, but they complicate the build setup so much that writing boilerplate is usually a better option.
  }.
}

◊p{
  Type conversion traits, such as ◊code{From} and ◊code{Into}, are also problematic under orphan rules.
  I often see ◊code{xxx-types} packages that start small but end up as bottlenecks in the compilation chain.
  Splitting such packages into smaller pieces is often daunting because of the intricate webs of type conversions connecting distant types together.
  Orphan rules do not allow us to cut these packages on module boundaries and move all conversions into a separate package without doing a lot of tedious work.
}

◊p{
  Do not get me wrong: orphan rules are a great default.
  Haskell allows you to define ◊a[#:href "https://wiki.haskell.org/Orphan_instance"]{orphan instances}, but programmers frown upon this practice.
  It is the inability to escape orphan rules that makes me sad.
  In large codebases, decomposing large packages into smaller pieces and maintaining shallow dependencies graphs are the only path to acceptable compilation speed.
  Orphan rules often stay in the way of trimming dependency graphs.
}
}


◊section{
◊section-title["fearless-concurrency-lie"]{Fearless concurrency is a lie}
◊p{
  The Rust team coined the term ◊a[#:href "https://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html"]{Fearless Concurrency} to indicate that Rust helps you avoid common pitfalls associated with parallel and concurrent programming.
  Despite these claims, my ◊a[#:href "https://en.wikipedia.org/wiki/Cortisol"]{cortisol} level goes up every time I introduce concurrency to my Rust programs.
}

◊subsection-title["deadlocks"]{Deadlocks}
◊epigraph{
  ◊blockquote{
    ◊p{
      So it's perfectly ◊quoted{fine} for a Safe Rust program to get deadlocked or do something nonsensical with incorrect synchronization.
      Obviously such a program isn't very good, but Rust can only hold your hand so far.
    }
    ◊footer{The Rustonomicon, ◊a[#:href "https://doc.rust-lang.org/nomicon/races.html"]{Data Races and Race Conditions}}
  }
}
◊p{
  Safe Rust prevents a specific type of concurrency bug called ◊em{data race}.
  Concurrent Rust programs have plenty of other ways to behave incorrectly.
}
◊p{
  One class of concurrency bugs that I experienced firsthand is ◊a[#:href "https://en.wikipedia.org/wiki/Deadlock"]{deadlock}.
  A typical explanation of this class of bugs involves two locks and two processes trying to acquire the locks in opposite orders.
  However, if the locks you use are not ◊a[#:href "https://stackoverflow.com/questions/1312259/what-is-the-re-entrant-lock-and-concept-in-general"]{re-entrant} (and Rust's locks are not), having a single lock is enough to cause a deadlock.
}
◊p{
  For example, the following code is buggy because it attempts to acquire the same lock twice.
  The bug might be hard to spot if ◊code{do_something} and ◊code{helper_function} are large and live far apart in the source file or if we call ◊code{helper_function} or a rare execution path.
}
◊source-code["bad"]{
impl Service {
  pub fn do_something(&self) {
    let guard = self.lock.read();
    ◊em{// ◊ellipsis{}}
    self.helper_function(); ◊em{// ◊b{BUG}: will panic or deadlock}
    ◊em{// ◊ellipsis{}}
  }

  fn helper_function(&self) {
    let guard = self.lock.read();
    ◊em{// ◊ellipsis{}}
  }
}
}
◊p{
  The documentation for ◊code-ref["https://doc.rust-lang.org/std/sync/struct.RwLock.html#method.read"]{RwLock::read} mentions that the function ◊em{might} panic if the current thread already holds the lock.
  All I got was a hanging program.
}
◊p{
  Some languages tried to provide a solution to this problem in their concurrency toolkits.
  The Clang compiler provides ◊a[#:href "https://clang.llvm.org/docs/ThreadSafetyAnalysis.html"]{Thread safety annotations} enabling a form of static analysis that can detect race conditions and deadlocks.
  However, the best way to avoid deadlocks is not to have locks.
  Two technologies that approach the problem fundamentally are ◊a[#:href "https://en.wikipedia.org/wiki/Software_transactional_memory"]{Software Transaction Memory} (implemented in ◊a[#:href "https://wiki.haskell.org/Software_transactional_memory"]{Haskell}, ◊a[#:href "https://clojure.org/reference/refs"]{Clojure}, and ◊a[#:href "https://nbronson.github.io/scala-stm/"]{Scala}) and the ◊a[#:href "https://en.wikipedia.org/wiki/Actor_model"]{actor model} (◊a[#:href "https://www.erlang.org/"]{Erlang} was the first language that fully embraced it).
}

◊subsection-title["filesystem-shared-resource"]{Filesystem is a shared resource}
◊epigraph{
  ◊blockquote{
    ◊p{
      We can view a path as an ◊em{address}.
      Then a string representing a path is a pointer, and accessing a file through a path is a pointer dereference.
      Thus, component interference due to file overwriting can be viewed as an address collision problem: two components occupy overlapping parts of the address space.
    }
    ◊footer{Eelco Dolstra, ◊a[#:href "The Purely Functional Software Deployment Model"]{The Purely Functional Software Deployment Model}, p. 53}
  }
}
◊p{
  Rust gives us powerful tools to deal with shared memory.
  However, once our programs need to interact with the outside world (e.g., use a network interface or a filesystem), we are on our own.
  Rust is similar to most modern languages in this regard.
  However, it can give you a false sense of security.
}
◊p{
  Remember that paths are raw pointers, even in Rust.
  Most file operations are inherently unsafe and can lead to data races (in a broad sense) if you do synchronize file access properly.
  For example, as of February 2023, I still experience a six-year-old ◊a[#:href "https://github.com/rust-lang/rustup/issues/988"]{concurrency bug} in ◊a[#:href "https://rustup.rs/"]{rustup}.
}

◊subsection-title["implicit-async-runtimes"]{Implicit async runtimes}
◊epigraph{
  ◊blockquote{
    ◊p{I cannot seriously believe in it because the theory cannot be reconciled with the idea that physics should represent a reality in time and space, free from spooky action at a distance.}
    ◊footer{Albert Einstein, ◊a[#:href "https://books.google.ch/books?redir_esc=y&hl=de&id=HvZAAQAAIAAJ&focus=searchwithinvolume&q=spooky+action"]{The Born-Einstein letters}, p. 158.}
  }
}

◊p{
  The value of Rust that I like the most is its focus on local reasoning.
  Looking at the function's type signature often gives you a solid understanding of what the function can do.
  State mutations are explicit thanks to mutability and lifetime annotations.
  Error handling is explicit and intuitive thanks to the ubiquitous ◊code{Result} type.
  When used correctly, these features often lead to the mystical ◊a[#:href "https://wiki.haskell.org/Why_Haskell_just_works"]{if it compiles◊mdash{}it works} effect.
  Asynchronous programming in Rust is different, however.
}
◊p{

}
◊p{
  Rust supports the ◊code-ref["https://rust-lang.github.io/async-book/01_getting_started/04_async_await_primer.html"]{async/.await} syntax for defining and composing asynchronous functions, but the runtime support is limited.
  Several libraries (called ◊a[#:href "https://ncameron.org/blog/what-is-an-async-runtime/"]{async runtimes}) define asynchronous functions to interact with the operating system.
  The ◊a[#:href "https://crates.io/crates/tokio"]{tokio} package is the most popular library.
}
◊p{
  One common issue with runtimes is that they rely on passing arguments implicitly.
  For example, the tokio runtime allows you to ◊code-ref["https://docs.rs/tokio/latest/tokio/fn.spawn.html"]{spawn} a concurrent task at any point in your program.
  For this function the work, the programmer has to construct a runtime object in advance.
}
◊source-code["rust"]{
fn innocently_looking_function() {
  ◊code-ref["https://docs.rs/tokio/1.25.0/tokio/fn.spawn.html"]{tokio::spawn}(some_async_func());
  // ^
  // |
  // ◊em{This code will panic if we remove this line. Spukhafte Fernwirkung!}
} //                                     |
  //                                     |
fn main() { //                           v
  let _rt = ◊code-ref["https://docs.rs/tokio/1.25.0/tokio/runtime/struct.Runtime.html"]{tokio::runtime::Runtime}::new().unwrap();
  innocently_looking_function();
}
}
◊p{
  These implicit arguments turn compile-time errors into runtime errors.
  What should have been a compile error turns into a debugging adventure:
}
◊ul[#:class "arrows"]{
  ◊li{
    If the runtime were an explicit argument, the code would not compile unless the programmer constructed a runtime and passed it as an argument.
    When the runtime is implicit, your code might compile fine but will crash at runtime if you forget to annotate your main function with a ◊a[#:href "https://docs.rs/tokio/latest/tokio/attr.main.html"]{magical macro}.
  }
  ◊li{
    Mixing libraries that chose different runtimes is ◊a[#:href "https://www.ncameron.org/blog/portable-and-interoperable-async-rust/"]{complicated}.
    The problem is even more confusing if it involves multiple major versions of the same runtime.
    My experience writing async Rust code resonates with the ◊a[#:href "https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo.html"]{Status Quo} stories collected by the ◊a[#:href "https://rust-lang.github.io/wg-async/welcome.html"]{Async Working Group}.
  }
}
◊p{
  Some might argue that threading ubiquitous arguments through the entire call stack is unergonomic.
  ◊a[#:href "http://localhost:8080/posts/03-rust-packages-crates-modules.html#explicit-dependencies"]{Explicitly passing all arguments} is the only approach that scales well.
}
}

◊section{
◊section-title["conclusion"]{Conclusion}
◊epigraph{
  ◊blockquote[#:cite "https://www.stroustrup.com/quotes.html"]{
    ◊p{There are only two kinds of languages: the ones people complain about and the ones nobody uses.}
    ◊footer{Bjarne Stroustrup}
  }
}
◊p{
  Rust is a disciplined language that got many important decisions right, such as an uncompromising focus on safety, the trait system design◊sidenote["sn-trait-system-cpp"]{I'm looking at you, ◊a[#:href "https://en.cppreference.com/w/cpp/language/constraints"]{C++ Concepts}.}, the lack of implicit conversions, and a holistic approach to ◊a[#:href "/posts/12-rust-error-handling.html"]{error handling}.
  It allows us to develop robust and memory-safe programs relatively quickly without compromising execution speed.
}
◊p{
  Yet, I often find myself overwhelmed with accidental complexity, especially when I care little about performance and want to get something working quickly (for example, in test code).
  Oh well, no language is perfect for every problem.
}
}