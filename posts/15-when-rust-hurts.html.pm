#lang pollen

◊(define-meta title "When Rust hurts")
◊(define-meta keywords "rust")
◊(define-meta summary "Why I am not enjoying programming in Rust.")
◊(define-meta doc-publish-date "2022-02-03")
◊(define-meta doc-updated-date "2022-02-03")


◊section{
◊section-title["intro"]{Introduction}
◊p{
  Rust is in a sweet spot in the language design space.
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
◊section-title["values-and-references"]{Values and references}
◊p{
  It is helpful to understand the difference between values and references before we dive into details.
  In a high-level programming language that operate mostly on immutable data, we tend to ignore this distinction.
}
◊p{
  The value/reference dichotomy explodes the number of choices that the programmer must make.
  Each time a programmer describes a field in a struct, she needs to decide whether the field will hold a value or a reference.
  Or maybe the best option is to ◊a[#:href "https://doc.rust-lang.org/std/borrow/enum.Cow.html"]{decide at runtime}?
}
}


◊section{
◊section-title["rust-cannot-abstract"]{Rust cannot abstract}
◊p{
  Manual memory management, and the ownership-aware type system seems to not play well with the ability to break down code into smaller pieces.
  Note that some of the items are just as well applicable to other language differentiating between values and references, such as C++.
}
◊subsection-title["common-expression-elimination"]{Common expression elimination}
◊p{
  Extracting common expression into a variable often creates unexpected challenges.
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
}



◊section{
◊section-title["rust-cannot-compose"]{Rust cannot compose}

◊subsection-title["function-composition"]{Function composition}
◊p{
  Function composition is bread and butter of functional programming.
}
◊p{
  In Rust, most functions take arguments by reference and return results by value.
  
  This often requires writing glue lambdas to take an explicit reference to an argument passed by value:
}

◊source-code["bad"]{
fn f(x: &X) -> Y;
fn map(t: T<X>, f: impl Fn(X) -> Y) -> T<Y>;
let ty = map(tx, f); ◊em{// ← compile error}
}

◊source-code["good"]{
fn f(x: &X) -> Y;
fn map(t: T<X>, f: impl Fn(X) -> Y) -> T<Y>;
let ty = map(tx, |x| f(&x)); ◊em{// <= glue lambda is required}
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
  This configuration is called ◊quote{sibling pointers}.
  There is no way to build the desired structure without using unsafe Rust or packages that rely on unsafe Rust.
}
◊p{
  As usual, Rust is trying to save us from ourselves: the Snapshot object might depend on the physical location of the ◊code{Db} object.
  If we move ◊code{DbSnapshot}, the physical location will change, and the snapshot might become invalid.
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
}


◊section{
◊section-title["fearless-concurrency-lie"]{Fearless concurrency is a lie}
}