#lang pollen

◊(define-meta title "Rust at scale: packages, crates, and modules")
◊(define-meta keywords "rust")
◊(define-meta summary "Lessons learned from scaling a Rust codebase.")
◊(define-meta doc-publish-date "2022-01-20")
◊(define-meta doc-updated-date "2022-01-20")

◊blockquote{
  Good decisions come from experience. Experience comes from making bad decisions.
}

◊p{
  I was lucky enough to see how ◊a[#:href "https://github.com/dfinity/ic"]{the Internet Computer (IC) Rust codebase} has grown from a few files to almost 350,000 lines of code within just about two years.
  The team learned that code organization that works just fine for relatively small projects might start dragging you down over time.
  In this article, we shall evaluate code organization options that Rust gives us and look at how to use them well.
}

◊section["personae"]{Dramatis Personae}

◊p{
Rust terminology might be confusing for newcomers.
I believe one of the reasons for that is that the term ◊em{crate} is somewhat overloaded in the community.
Even the first edition of the venerable ◊a[#:href "https://doc.rust-lang.org/1.25.0/book/"]{The Rust Programming Language} book contained the following misleading passage
}
◊blockquote[#:cite "https://doc.rust-lang.org/1.25.0/book/first-edition/crates-and-modules.html"]{
Rust has two distinct terms that relate to the module system: ‘crate’ and ‘module’. A crate is synonymous with a ‘library’ or ‘package’ in other languages. Hence “Cargo” as the name of Rust’s package management tool: you ship your crates to others with Cargo. Crates can produce an executable or a library, depending on the project.
}
◊p{
Wait a minute, `library` and `package` are different things, aren't they?
Mixing up these two concepts can lead to a lot of frustration, even if you already have a few months of experience with Rust under your belt.
Tooling conventions contribute to the confusion as well: If a Rust package defines a library crate, cargo derives the library name from the package name by default (you can override the library name to be completely different, but please don't).
}
◊p{
Let us become familiar with the code organization concepts we will be dealing with.
}

◊dl{
 ◊dt{Module}
 ◊dd{
   A ◊a[#:href "https://doc.rust-lang.org/reference/items/modules.html"]{Module} is a language construct that acts as the basic building block of code organization within a ◊em{crate}.
   A module is a container for functions, types, and nested modules.
   Modules also specify the visibility for all the items that they contain or re-export.
 }
 ◊dt{Crate}
 ◊dd{
   A ◊a[#:href "https://doc.rust-lang.org/reference/crates-and-source-files.html"]{Crate} is the basic unit of compilation and linking.
   Crates are also part of the language (◊code{crate} is a ◊a[#:href "https://doc.rust-lang.org/reference/keywords.html"]{keyword}), but you usually don't mention them much in your source code.
   There are two main types of crates: libraries and executable files.
 }
 ◊dt{Package}
 ◊dd{
   A ◊a[#:href "https://doc.rust-lang.org/cargo/appendix/glossary.html#package"]{Package} is the basic unit of software distribution.
   Packages are not part of the language, so you will not find them in the language reference.
   Packages are artifacts of the Rust package manager, ◊a[#:href "https://doc.rust-lang.org/cargo/index.html"]{Cargo}.
   Packages can contain one or more crates: at most one library and any number of executables.
 }
}

◊section["modules-vs-crates"]{Modules vs Crates}

◊p{
  In this section, I will use the terms "crate" and "package" almost interchangeably, assuming that most of your crates are libraries.
  As you remember, we can have at most one library crate per package.
}

◊p{
  When you factor a large codebase into components, there are two extremes you can go to:
  (1) to have a few big packages with lots of modules in each package, or
  (2) to have lots of tiny packages with just a bit of code in each package.
}

◊p{Having few packages with lots of modules definitely has some advantages:}

◊ul[#:class "arrows"]{
◊li{It's less work to add or remove a module than to add or remove a package.}
◊li{
Modules are more flexible.
For example, modules in the same crate can form a dependency cycle: module ◊code{foo} can use definitions from module ◊code{bar}, which in turn can use definitions from module ◊code{foo}.
In contrast, the package dependency graph must be acyclic.
}
◊li{You don't have to modify your ◊code{Cargo.toml} file every time you shuffle modules around.}
}

◊p{
  Sounds like modules are a clear winner.
  In the ideal world where arbitrary-sized Rust crates compile instantly, turning the whole repository into one huge package with lots of modules would be the most convenient setup.
  The bitter reality though is that Rust takes quite some time to compile, and modules do not help you shorten the compilation time:
}

◊ul[#:class "arrows"]{
◊li{
  The basic unit of compilation is ◊em{crate}, not ◊em{module}.
  You have to recompile all the modules in a crate even you change only a single module.
  The more code you have in a single crate, the longer it takes to compile.
}
◊li{
  Cargo can compile crates in parallel.
  Modules do not form translation units by themselves, so cargo cannot parallelize the compilation of a single crate.
  You don't use the full potential of your multi-core CPU if you have a few large packages.
}
}

◊p{
  It all boils down to the tradeoff between convenience and compilation speed.
  Modules are very convenient, but they don't help the compiler do less work.
  Packages are less convenient, but they deliver a better overall development experience as the code base grows.
}

◊section["code-organization-advice"]{Advice on code organization}

◊advice["avoid-dependency-hubs"]{Split dependency hubs.}

◊p{There are two types of dependency hubs:}
◊ul[#:class "arrows"]{
◊li{
  Packages with lots of dependencies.
  Examples from the IC codebase are: (1) the ◊code{test-utils} package that contains auxiliary code for integration tests (
  proptest strategies, mock and fake implementations of various components, helper functions, etc.),
  and the ◊code{replica} package that instantiates and starts all the components.
}
◊li{
  Packages with lots of ◊em{reverse dependencies}.
  Examples from the IC codebase are ◊code{types} and ◊code{interfaces} packages that contain definitions and trait implementations
  for common types and traits specifying interfaces of major components.
}
}

◊figure[#:class "grayscale-diagram"]{
  ◊p{◊(embed-svg "images/03-dep-hubs.svg")}
  ◊figcaption{A small subgraph of the Internet Computer project package dependency graph. ◊code{types} and ◊code{interfaces} are type-one dependency hubs, ◊code{replica} is a type-two dependency hub, ◊code{test-utils} is both a type-one and a type-two hub.}
}

◊p{
  The main reason why dependency hubs are undesirable is their devastating effect on incremental compilation.
  If you modify a package with lots of reverse dependencies (e.g., ◊code{types}),
  cargo has to re-compile all those dependencies to check that your change makes sense.
}

◊p{
  The only way to get rid of dependency hubs is to split them into smaller packages.
}

◊p{
  Sometimes it is possible to eliminate a dependency hub.
  For example, ◊code{test-utils} is a conglomeration of independent utilities.
  We can group these utilities by component they help to test and factor them into multiple ◊code{◊em{<component>}-test-utils} packages.
}

◊p{
  More often, however, there is no way to get rid of a dependency hub entirely.
  Some types from ◊code{types} are pervasive.
  The package that contains those types is doomed to be a type-one dependency hub.
  The ◊code{replica} package contains the main function that ties everything together so it has to depend on all components.
  The ◊code{replica} is doomed to be a type-two dependency hub.
  The best you can do is to localize such hubs and make the code inside relatively stable.
}

◊advice["generic-no-deps"]{Consider using generics and associated types to eliminate dependencies.}

◊p{
  Among the first few packages that appeared in the IC codebase were: ◊code{types}, ◊code{interfaces}, and ◊code{replicated_state} (that package defines data structures that represent the state of a single subnet).
  But why do we even need the ◊code{types} package?
  Types are an integral part of the interface, why not define them in the ◊code{interfaces} package as well?
}
◊p{
  The problem is that some interfaces operate on instances of ◊code{ReplicatedState}.
  And the ◊code{replicated_state} package depends on type definitions from the ◊code{types} package.
  So if all the types lived in the ◊code{interfaces} package, there would be a circular dependency between ◊code{interfaces} and ◊code{replicated_state}.
  Generally, there are two ways to break a circular dependency:
    (1) to move common definitions into another package, or
    (2) to merge two packages into a single one.
  Merging interfaces with the replicated state was not an option.
  So we conceived ◊code{types} to contain types that both ◊code{interfaces} and ◊code{replicated_state} depend on.
}
◊p{
  An interesting property of trait definitions in ◊code{interfaces} is that they only depend on the ◊code{ReplicatedState} type by name.
  These definitions do not need to know the definition of that type.
}

◊figure{
◊source-code["good"]{
trait StateManager {
  fn get_latest_state(&self) -> ReplicatedState;

  fn commit_state(&self, state: ReplicatedState, version: Version);
}
}
◊figcaption{An example of a trait definition from the ◊code{interfaces} package that depends on the ◊code{ReplicatedState} type.}
}

◊p{
  This property of the trait definitions allows us to break the direct dependency between ◊code{interfaces} and ◊code{replicated_state}.
  We just need to replace the exact type with a generic type argument.
}

◊figure{
◊source-code["good"]{
trait StateManager {
  type State; //< We turned a specific type into an associated type.
  
  fn get_latest_state(&self) -> State;

  fn commit_state(&self, state: State, version: Version);
}
}
◊figcaption{A generic version of the ◊code{StateManager} trait that does not depend on ◊code{ReplicatedState}.}
}

◊p{
  This little trick saves us a lot of compilation time:
  Now we do not need to recompile the ◊code{interfaces} package and its numerous dependencies every time we add a new field to the replicated state.
}

◊advice["dyn-polymorphism"]{Prefer runtime polymorphism.}

◊p{
  One of the big questions that the team had when we were designing the component architecture is how to connect components.
  Should we pass instances of components around as ◊code{Arc<dyn StateManager>} (runtime polymorphism) or rather as generic arguments (compile-time polymorphism)?
}

◊figure{
◊source-code["good"]{
pub struct Consensus {
  Arc<dyn ArtifactPool> artifact_pool;
  Arc<dyn StateManager> state_manager;
}
}
◊figcaption{Composing components using runtime polymorphism.}
}

◊figure{
◊source-code["bad"]{
pub struct Consensus<AP: ArtifactPool, SM: StateManager> {
  AP artifact_pool;
  SM state_manager;
}
}
◊figcaption{Composing components using compile-time polymorphism.}
}

◊p{
  Compile-time polymorphism is an indispensable tool, but a heavy-weight one.
  Most team members also found that the code becomes easier to write, read, and understand when we use runtime polymorphism for composition.
  Delaying work until runtime also helps with compile times.
}

◊advice["explicit-dependencies"]{Prefer explicit dependencies.}

◊p{
  One of the most common questions that new developers ask on the dev channel is something like ◊quote{"Why do we explicitly pass around loggers? Global loggers seem to work pretty well."}.
  That's a very good question.
  I would ask the same thing two years ago!
  Sure, global variables are ◊em{bad}, but my previous experience suggested that loggers and metrics are somehow special.
  Oh well, there aren't after all.
}
◊p{
  The usual problems with implicit state dependencies are especially prominent in Rust.
}
◊ul[#:class "arrows"]{
◊li{
  Most Rust libraries do not rely on true global variables.
  The usual way to pass implicit state around is to use ◊a[#:href "https://doc.rust-lang.org/stable/std/macro.thread_local.html"]{thread-local} state.
  This becomes a problem when you start spawning new threads: these threads tend to inherit the values of thread locals that you did not expect.
}
◊li{
  Cargo runs tests in parallel by default.
  If you're not careful with how you're passing loggers between threads, your test output might become an intangible mess.
  Especially if your code uses loggers in background threads.
  Passing loggers explicitly eliminates that problem.
}
◊li{
  Testing code that relies on implicit state in a multi-threaded environment is often hard or impossible.
  The code that records your metrics is, well, ◊em{code}.
  It also deserves to be tested.
}
◊li{
  If you use a library that relies on implicit thread-local state, it is easy to introduce subtle bugs by depending on incompatible versions of the library in different packages.
  For example, we use the ◊a[#:href "https://crates.io/crates/prometheus"]{prometheus} package to record metrics.
  This package relies on an implicit thread local variable that holds the current metrics registry.
  ◊p{
    At some point we could not see metrics recorded by some of our components.
    Our code seemed correct, yet the metrics were not there.
    It turned out that one of the packages used prometheus version ◊code{0.9} while all other packages used ◊code{0.10}.
    According to ◊a[#:href "https://semver.org/"]{semver}, these versions are incompatible, so cargo linked both versions into the binary, introducing ◊em{two} implicit registries.
    Only one of these implicit registries could be exposed.
    The HTTP endpoint never pulled the metrics recorded to the other registry.
  }
  ◊p{
    Passing loggers, metrics registries, async runtimes, etc. explicitly turns a runtime bug into a compile time error: the compiler will complain if you pass incompatible types around.
    Switching to passing the metrics registry explicitly is what helped me to discover the issue with the metrics recording.
  }
  }
}
◊p{
  The official documentation of the venerable ◊a[#:href "https://crates.io/crates/slog"]{slog} package also recommends passing loggers explicitly:
}
◊blockquote[#:cite "https://github.com/slog-rs/slog/wiki/FAQ#do-i-have-to-pass-logger-around"]{
  ◊p{
    The reason is: manually passing ◊code{Logger} gives maximum flexibility.
    Using ◊code{slog_scope} ties the logging data structure to the stacktrace, which is not the same a logical structure of your software.
    Especially libraries should expose full flexibility to their users, and not use implicit logging behaviour.
  }
  ◊p{
    Usually ◊code{Logger} instances fit pretty neatly into data structures in your code representing resources, so it's not that hard to pass them in constructors, and use ◊code{info!(self.log, ...)} everywhere. 
  }
}
◊p{
 By passing state implicitly, you gain temporary convenience, but make your code less clear, less testable, and more error prone.
 Every type of resource that we used to pass implicitly caused hard to diagnose issues (◊a[#:href "https://crates.io/crates/slog-scope"]{scoped} loggers, ◊a[#:href "https://crates.io/crates/prometheus"]{Prometheus} metrics registries, ◊a[#:href "https://crates.io/crates/rayon"]{Rayon} thread pools, ◊a[#:href "https://crates.io/crates/tokio"]{Tokio} runtimes, to name a few) and wasted a lot of engineering time.
}
◊p{
  Some people in other programming communities also realized that global loggers are evil.
  You might enjoy reading ◊a[#:href "https://www.yegor256.com/2019/03/19/logging-without-static-logger.html"]{Logging Without a Static Logger}, for example.
}

◊advice["dedup-dependencies"]{Deduplicate dependencies.}

◊p{
  Cargo makes it easy to add dependencies to your code, but it does not provide any tools to consolidate and maintain them in a large workspace.
  At least until cargo developers implement ◊a[#:href "https://github.com/rust-lang/rfcs/pull/2906"]{RFC 2906}.
  Until then, every time you bump a version of a dependency, try to do it consistently in all the packages in your workspace.
}
◊p{
  The same applies to package features: if you use the same dependency with different feature sets in different packages, that dependency needs to be compiled twice.
}
◊p{
  Unfortunately, using multiple versions of the same package might also result in correctness issues, especially with packages that have zero as their major version (◊code{0.y.z}).
  If you depend on versions ◊code{0.1} and ◊code{0.2} of the same package in a single binary, cargo will link both versions into the executable.
  If you ever pulled your hair off trying to figure out why you get that ◊a[#:href "https://github.com/awslabs/aws-lambda-rust-runtime/issues/266"]{"there is no reactor running"} error, you know how painful these issues can be to debug.
}

◊advice["tests-in-separate-files"]{Put unit tests into separate files.}

◊p{
  Rust allows you to write unit tests right next to your production code.
}
◊figure{
◊source-code["bad"]{
pub fn frobnicate(x: &Foo) -> u32 {
    todo!("implement frobnication")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frobnication() {
        assert!(frobnicate(&Foo::new()), 5);
    }
}
}
◊figcaption{A module that has unit tests and production code in the same file, ◊code{foo.rs}.}
}
◊p{
  That's very convenient, but we found that it can slow down test compilation time considerably.
  Cargo build cache can get confused when you modify the file, tricking cargo into re-compiling the crate under both ◊code{dev} and ◊code{test} profiles, even if you touched only the test part.
  By trial and error, we discovered that the issue does not occur if the tests live in a separate file.
}

◊figure{
◊source-code["good"]{
pub fn frobnicate(x: &Foo) -> u32 {
    todo!("implement frobnication")
}

// The contents of the module moved to foo/tests.rs.
#[cfg(test)]
mod tests;
}
◊figcaption{Moving unit tests into ◊code{foo/tests.rs}.}
}

◊p{
  This technique tightened our edit-check-test loop and made the code easier to navigate.
}

◊section["common-pitfalls"]{Common pitfalls}

◊p{
  In this section, we will take a look at some tricky issues that Rust newcomers might run into.
  I experienced these issues myself, and I saw several collegues running into them as well.
}

◊subsection["confusing-crates-and-packages"]{Confusing crates and packages}

◊p{
Imagine you have package ◊code{image-magic} that defines a library for working with images and also provides a command-line utility for image transformation called ◊code{transmogrify}.
Naturally, you want to use the library to implement ◊code{transmogrify}.
Your ◊code{Cargo.toml} file will look like the following snippet of code.
}

◊figure{
◊source-code["good"]{
[package]
name = "image-magic"
version = "1.0.0"
edition = 2018

[lib]

[[bin]]
name = "transmogrify"
path = "src/transmogrify.rs"

# dependencies...
}
◊figcaption{Contents of ◊code{image-magic/Cargo.toml}.}
}


◊p{
Now you open ◊code{transmogrify.rs} and write something like:
}

◊figure{
◊source-code["bad"]{
use crate::{Image, transform_image}; //< Compile error.
}
}

◊p{
The compiler will become upset and will tell you something like
}

◊figure{
◊source-code["bad"]{
error[E0432]: unresolved imports `crate::Image`, `crate::transform_image`
 --> src/transmogrify.rs:1:13
  |
1 | use crate::{Image, transform_image};
  |             ^^^^^  ^^^^^^^^^^^^^^^ no `transform_image` in the root
  |             |
  |             no `Image` in the root
}
}

◊p{
Oh, how is that?
Aren't ◊code{lib.rs} and ◊code{transmogrify.rs} in the same ◊em{crate}?
No, they are not.
The ◊code{image-magic} ◊em{package} defines two ◊em{crates}: a ◊em{library crate} named ◊code{image_magic} (note that cargo replaced the dash in the package name with an underscore) and a ◊em{binary crate} named ◊code{transmogrify}.
So when you write ◊code{use crate::Image} in ◊code{transmogrify.rs}, you tell the compiler to look for the type defined in the same binary.
The ◊code{image_magic} ◊em{crate} is just as external to ◊code{transmogrify} as any other library would be, so we have to specify the library name in the use declaration:
}

◊figure{
◊source-code["good"]{
use image_magic::{Image, transform_image}; //< OK.
}
}

◊subsection["quasi-circular"]{Quasi-circular dependencies}

To understand this issue, we'll first have to learn about ◊a[#:href "https://doc.rust-lang.org/cargo/reference/profiles.html"]{Cargo build profiles}.
Build profiles are named compiler configurations that cargo uses when compiling a crate.
For example:
◊dl{
 ◊dt{release}
 ◊dd{
   This is the profile that you want to use for the binaries you deploy to production.
   Highest optimization level, disabled debug assertions, long compile times.
   Cargo uses this profile when you run ◊br{} ◊code{cargo build --release}.
 }
 ◊dt{dev}
 ◊dd{
   This is the profile that you use for the normal development cycle, the profile that you get when you run ◊code{cargo build}.
   Debug asserts and overflow checks are enabled, optimizations are disabled for much faster compile times.
 }
 ◊dt{test}
 ◊dd{
   Mostly the same as the ◊em{dev} profile.
   This profile is enabled when you run ◊code{cargo test}.
   When you test a library crate, cargo builds this library with a test profile and injects the main function that executes the test harness.
   Cargo builds dependencies of the crate being tested using the ◊em{dev} profile.
 }
}

◊p{
  Imagine now that you have a package with a fancy library ◊code{foo}.
  You want to have good test coverage for that library, and you want the tests to be easy to write.
  So you introduce another package, ◊code{foo-test-utils}, that make testing code that works with ◊code{foo} significantly easier.
}

◊p{
  It also feels natural to use ◊code{foo-test-utils} for testing the ◊code{foo} itself.
  Let's add ◊code{foo-test-utils} as a dev dependency of ◊code{foo}.
  Wait doesn't this create a dependency cycle?
  ◊code{foo} depends on ◊code{foo-test-utils} that depends on ◊code{foo}, right?
}

◊figure{
◊source-code["good"]{
[package]
name = "foo"
version = "1.0.0"
edition = "2018"

[lib]

[dev-dependencies]
foo-test-utils = { path = "../foo-test-utils" }
}
◊figcaption{Contents of ◊code{foo/Cargo.toml}.}
}

◊figure{
◊source-code["good"]{
[package]
name = "foo-test-utils"
version = "1.0.0"
edition = "2018"

[lib]

[dependencies]
foo = { path = "../foo" }
}
◊figcaption{Contents of ◊code{foo-test-utils/Cargo.toml}.}
}

◊p{
  There is no circular dependency because cargo compiles ◊code{foo} that ◊code{foo-test-utils} depends on using the ◊em{dev} profile.
  Then cargo compiles the test version of ◊code{foo} with the test harness using the ◊em{test} profile and links it with ◊code{foo-test-utils}.
}

◊figure[#:class "grayscale-diagram"]{
  ◊p{◊(embed-svg "images/03-foo-test-profile.svg")}
  ◊figcaption{Dependency diagram for ◊code{foo} library test.}
}

◊figure{
◊source-code["good"]{
use foo::Foo;

pub fn make_test_foo() -> Foo {
    Foo {
        name: "John Doe".to_string(),
        age: 32,
    }
}

}
◊figcaption{Contents of ◊code{foo-test-utils/src/lib.rs}.}
}

◊figure{
◊source-code["bad"]{
#[derive(Debug)]
pub struct Foo {
    pub name: String,
    pub age: u32,
}

fn private_fun(x: &Foo) -> u32 {
    x.age / 2
}

pub fn frobnicate(x: &Foo) -> u32 {
    todo!("complete frobnication")
}

#[test]
fn test_private_fun() {
    let x = foo_test_utils::make_test_foo();
    private_fun(&x);
}
}
◊figcaption{Contents of ◊code{foo/src/lib.rs}.}
}

◊p{
  However, when we try to run ◊code{cargo test -p foo}, we get a cryptic compile error:
}

◊figure{
◊source-code["bad"]{
error[E0308]: mismatched types
  --> src/lib.rs:14:17
   |
14 |     private_fun(&x);
   |                 ^^ expected struct `Foo`, found struct `foo::Foo`
   |
   = note: expected reference `&Foo`
              found reference `&foo::Foo`
}
}

◊p{
  What could that mean?
  The reason we get an error is that type definitions in the test version of ◊code{foo} aren't compatible with type definitions in the dev version of ◊code{foo}.
  These are different, incompatible crates even though these crates have the same name.
}

◊p{
  The way out of this trouble is to define a separate integration test crate in the ◊code{foo} package and move the tests there.
  You'll be limited to testing only the public interface of the ◊code{foo} library.
}

◊figure{
◊source-code["good"]{
#[test]
fn test_foo_frobnication() {
    let foo = foo_test_utils::make_test_foo();
    assert_eq!(foo::frobnicate(&foo), 2);
}
}
◊figcaption{Contents of ◊code{foo/tests/foo_test.rs}.}
}

◊p{
  The test above compiles fine because both this test and ◊code{foo_test_utils} are linked against the version of the ◊code{foo} library build with the ◊em{dev} profile.
}

◊figure[#:class "grayscale-diagram"]{
  ◊p{◊(embed-svg "images/03-foo-dev-profile.svg")}
  ◊figcaption{Dependency diagram for ◊code{foo_test} integration test.}
}

◊p{
  Quasi-circular dependencies are tricky and confusing.
  They also tend to have negative effect on compilation time.
  My advice is to avoid them when possible.
}

◊section["conclusion"]{Conclusion}

◊p{
  In this article, we looked at the tools that Rust gives us to organize our code.
  Rust's module system is very convenient, but packing many modules into a single crate tend to have negative effect on the build speeds.
  Our experience suggests that factoring the system into many cohesive packages instead is a better approach in most cases.
}