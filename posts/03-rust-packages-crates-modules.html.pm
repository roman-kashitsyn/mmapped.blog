#lang pollen

◊(define-meta title "Rust at scale: packages, crates, and modules")
◊(define-meta keywords "rust")
◊(define-meta summary "Lessons learned from scaling a Rust code base.")
◊(define-meta doc-publish-date "2022-01-20")
◊(define-meta doc-updated-date "2023-06-16")

◊section{
◊epigraph{
◊blockquote{
  ◊p{
    Good judgment is the result of experience and experience the result of bad judgment.
  }
  ◊footer{Attributed to Mark Twain.}
}
}

◊p{
  The ◊a[#:href "https://internetcomputer.org"]{Internet Computer} (IC) ◊a[#:href "https://github.com/dfinity/ic"]{Rust code base} grew from an empty repository in June 2019 to almost 350,000 lines of code in early 2022.
  This rapid growth taught me that decisions working fine for relatively small projects might start dragging the project down over time.
  This article evaluates Rust code organization options and suggests ways to use them effectively.
}
}

◊section{
◊section-title["personae"]{Dramatis Personae}

◊p{
Rust terminology proved to be confusing because the term ◊em{crate} is overloaded.
For example, the first edition of the venerable ◊a[#:href "https://doc.rust-lang.org/1.25.0/book/"]{The Rust Programming Language} book contained the following misleading passage
}
◊blockquote[#:cite "https://doc.rust-lang.org/1.25.0/book/first-edition/crates-and-modules.html"]{
◊p{
  Rust has two distinct terms that relate to the module system: ‘crate’ and ‘module’. A crate is synonymous with a ‘library’ or ‘package’ in other languages.
  Hence “Cargo” as the name of Rust’s package management tool: you ship your crates to others with Cargo. Crates can produce an executable or a library, depending on the project.
}
}
◊p{
Wait a minute, a library and a package are different concepts, aren't they?
Mixing up these concepts leads to frustration, even if you already have a few months of Rust exposure.
Tooling conventions also contribute to the confusion: If a Rust package defines a library crate, ◊code{cargo} automatically derives the library name from the package name◊sidenote["sn-library-name-override"]{You can override this behavior, but please don't.}.
}
◊p{
Let's familiarize ourselves with the concepts we'll be dealing with.
}

◊dl{
 ◊dt{Module}
 ◊dd{
   A ◊a[#:href "https://doc.rust-lang.org/reference/items/modules.html"]{module} is the unit of code organization.
   It is a container for functions, types, and nested modules.
   Modules also specify the visibility for the names they define or re-export.
 }
 ◊dt{Crate}
 ◊dd{
   A ◊a[#:href "https://doc.rust-lang.org/reference/crates-and-source-files.html"]{crate} is the unit of compilation and linking.
   Crates are part of the language (◊code{crate} is a ◊a[#:href "https://doc.rust-lang.org/reference/keywords.html"]{keyword}), but you don't mention them much in the source code.
   Libraries and executables are the most common crate types.
 }
 ◊dt{Package}
 ◊dd{
   A ◊a[#:href "https://doc.rust-lang.org/cargo/appendix/glossary.html#package"]{package} is the unit of software distribution.
   Packages are not part of the language but artifacts of the Rust package manager, ◊a[#:href "https://doc.rust-lang.org/cargo/index.html"]{Cargo}.
   Packages can contain one or more crates: at most one library and any number of executables.
 }
}
}

◊section{
◊section-title["modules-vs-crates"]{Modules vs Crates}

◊p{
  When you factor a large codebase into components, there are two extremes:
  to have a few large packages with lots of modules or
  to have lots of small packages.
}

◊p{Having few packages with lots of modules has some advantages:}

◊ul[#:class "arrows"]{
  ◊li{
    Adding or removing a module is less work than adding or removing a package.
  }
  ◊li{
    Modules are more flexible.
    For example, modules in the same crate can form a dependency cycle: module ◊code{foo} can use definitions from module ◊code{bar}, which in turn can use definitions from module ◊code{foo}.
    In contrast, the package dependency graph must be acyclic.
  }
  ◊li{
    You don't have to modify your ◊code{Cargo.toml} file every time you rearrange your modules.
  }
}

◊p{
  In the ideal world where Rust compiles instantly, turning the repository into a massive package with many modules would be the most convenient setup.
  The bitter reality is that Rust takes quite some time to compile, and modules don't help you shorten the compilation time:
}

◊ul[#:class "arrows"]{
◊li{
  The basic unit of compilation is a ◊em{crate}, not a ◊em{module}.
  You must recompile all the modules in a crate even if you change only one.
  The more code you put in a crate, the longer it takes to compile.
}
◊li{
  Cargo parallelizes compilations across crates, not within a crate.
  You don't use the full potential of your multi-core CPU if you have a few large packages.
}
}

◊p{
  It boils down to the tradeoff between convenience and compilation speed.
  Modules are convenient but don't help the compiler do less work.
  Packages are less convenient but deliver better compilation speed as the code base grows.
}
}

◊section{
◊section-title["code-organization-advice"]{Advice on code organization}

◊advice["avoid-dependency-hubs"]{Split dependency hubs.}

◊p{There are two types of dependency hubs:}
◊ul[#:class "arrows"]{
◊li{
  Packages with lots of dependencies.
  Two examples from the IC codebase are the ◊code{test-utils} package containing auxiliary code for integration tests
  (proptest strategies, mock and fake component implementations, helper functions, etc.),
  and the ◊code{replica} package instantiating all the components.
}
◊li{
  Packages with lots of ◊em{reverse dependencies}.
  Examples from the IC codebase are the ◊code{types} package containing common type definitions and the ◊code{interfaces} package specifying component interfaces.
}
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-dep-hubs"]{A piece of the Internet Computer package dependency graph. ◊code{types} and ◊code{interfaces} are type-two dependency hubs, ◊code{replica} is a type-one dependency hub, ◊code{test-utils} is both a type-one and a type-two hub.}
  ◊(embed-svg "images/03-dep-hubs.svg")
}

◊p{
  Dependency hubs are undesirable because of their devastating effect on incremental compilation.
  If you modify a package with many reverse dependencies (e.g., ◊code{types}), cargo must to recompile all those dependencies to check your change.
}

◊p{
  Sometimes it is possible to eliminate a dependency hub.
  For example, the ◊code{test-utils} package is a union of independent utilities.
  We can group these utilities by the component they help to test and factor the code into multiple ◊code{◊em{<component>}-test-utils} packages.
}

◊p{
  More often, however, dependency hubs will have to stay.
  Some types from ◊code{types} are pervasive.
  The package containing these types is doomed to be a type-two dependency hub.
  The ◊code{replica} package wiring all the components is doomed to be a type-one dependency hub.
  The best you can do is to localize the hubs and make them small and stable.
}

◊advice["generic-no-deps"]{Consider using generics and associated types to eliminate dependencies.}

◊p{
  This advice needs an example, so bear with me.
}

◊p{
  ◊code{types}, ◊code{interfaces}, and ◊code{replicated_state} were among the first packages in the IC code base.
  The ◊code{types} package contains common type definitions, the ◊code{interfaces} package defines traits for software components, and the ◊code{replicated_state} package defines IC's replicated state machine data structures, with the ◊code{ReplicatedState} type at the root.
}
◊p{
  But why do we need the ◊code{types} package?
  Types are an integral part of the interface.
  Why not define them in the ◊code{interfaces} package?
}
◊p{
  The problem is that some interfaces refer to the ◊code{ReplicatedState} type.
  And the ◊code{replicated_state} package depends on type definitions from the ◊code{types} package.
  If all the types lived in the ◊code{interfaces} package, there would be a circular dependency between ◊code{interfaces} and ◊code{replicated_state}.
}
◊figure{
  ◊marginnote["mn-types-interfaces-state"]{The dependency graph for ◊code{types}, ◊code{interfaces}, and ◊code{replicated_state} packages.}
  ◊(embed-svg "images/03-types-ifaces-state.svg")
}
◊p{
  When we need to break a circular dependency, we can move common definitions into a new package or merge some packages.
  The ◊code{replicated_state} package is heavy; we didn't want to merge its contents with ◊code{interfaces}.
  So we took the first option and moved the types shared between ◊code{interfaces} and ◊code{replicated_state} into the ◊code{types} package.
}
◊p{
  One property of trait definitions in the ◊code{interfaces} package is that the traits depend only on the ◊code{ReplicatedState} type ◊em{name}.
  The traits do not need to know ◊code{ReplicatedState}'s definition.
}

◊figure{
◊marginnote["mn-example-trait"]{An example of a trait definition from the ◊code{interfaces} package that depends on the ◊code{ReplicatedState} type.}
◊source-code["good"]{
trait StateManager {
  fn get_latest_state(&self) -> ReplicatedState;

  fn commit_state(&self, state: ReplicatedState, version: Version);
}
}
}

◊p{
  This property allows us to break the direct dependency between ◊code{interfaces} and ◊code{replicated_state}.
  We only need to replace the exact type with a generic type argument.
}

◊figure{
◊marginnote["mn-generic-sm"]{A generic version of the ◊code{StateManager} trait that does not depend on ◊code{ReplicatedState}.}
◊source-code["good"]{
trait StateManager {
  type State; //< We turned a specific type into an associated type.
  
  fn get_latest_state(&self) -> State;

  fn commit_state(&self, state: State, version: Version);
}
}
}

◊p{
  Now, we don't need to recompile the ◊code{interfaces} package and its numerous dependencies every time we add a new field to the replicated state.
}

◊advice["dyn-polymorphism"]{Prefer runtime polymorphism.}

◊p{
  One of the design choices we had was how to connect software components.
  Should we pass instances of components as ◊code{Arc<dyn Interface>} (runtime polymorphism) or as generic type arguments (compile-time polymorphism)?
}

◊figure{
◊marginnote["mn-runtime-poly"]{Composing components using runtime polymorphism.}
◊source-code["good"]{
pub struct Consensus {
  artifact_pool: Arc<dyn ArtifactPool>,
  state_manager: Arc<dyn StateManager>,
}
}
}

◊figure{
◊marginnote["mn-compile-poly"]{Composing components using compile-time polymorphism.}
◊source-code["bad"]{
pub struct Consensus<AP: ArtifactPool, SM: StateManager> {
  artifact_pool: AP,
  state_manager: SM,
}
}
}

◊p{
  Compile-time polymorphism is an essential tool but a heavy-weight one.
  Runtime polymorphism requires less code and results in less binary bloat.
  Most team members also found the ◊code{dyn} version easier to read.
}

◊advice["explicit-dependencies"]{Prefer explicit dependencies.}

◊p{
  One of the most common questions new developers ask on the dev channel is ◊quoted{Why do we explicitly pass around loggers? Global loggers seem to work pretty well.}
  What a great question.
  I would ask the same thing in 2019!
}
◊p{
  Global variables are ◊a[#:href "http://wiki.c2.com/?GlobalVariablesAreBad"]{◊em{bad}}, but my previous experience suggested that loggers and metric sinks are special.
  Oh well, they aren't, after all.
}
◊p{
  The usual problems with implicit state dependencies are especially prominent in Rust.
}
◊ul[#:class "arrows"]{
◊li{
  Most Rust libraries do not rely on true global variables.
  The usual way to pass an implicit state is to use a ◊a[#:href "https://doc.rust-lang.org/stable/std/macro.thread_local.html"]{thread-local} variable, which can become problematic when you spawn a new thread.
  New threads tend to inherit and retain unexpected values of thread locals.
}
◊li{
  Cargo runs tests within a test binary in parallel by default.
  The test output might become an intangible mess if you’re not careful with threading loggers through the call stack.
  The problem usually manifests when a background thread needs to access the log.
  Explicitly passing loggers eliminates that problem.
}
◊li{
  Testing code relying on an implicit state often becomes hard or impossible in a multi-threaded environment.
  The code recording your metrics is, well, ◊em{code}.
  It also deserves to be tested.
}
◊li{
  If you use a library relying on implicit state, you can introduce subtle bugs if you depend on incompatible library versions in different packages.
}
}
◊p{
  The latter point desperately needs an example.
  So here is a little detective story.
}
◊p{
  We use the ◊a[#:href "https://crates.io/crates/prometheus"]{prometheus} package for metrics recording.
  This package can keep the metrics registry in a ◊a[#:href "https://docs.rs/prometheus/0.10.0/src/prometheus/registry.rs.html#307-317"]{global variable}.
}
◊p{
  One day, we discovered a bug: we could not see metrics from some of our components.
  Our code seemed correct, yet the metrics were missing.
}
◊p{
  One of the packages depended on prometheus version ◊code{0.9}, while all other packages used ◊code{0.10}.
  According to ◊a[#:href "https://semver.org/"]{semver}, these versions are incompatible, so cargo linked both versions into the binary, introducing ◊em{two} implicit registries.
  We exposed only the ◊code{0.10} version registry over the HTTP interface.
  As you correctly guessed, the missing components recorded metrics to the ◊code{0.9} registry.
}
◊p{
  Passing loggers, metrics registries, and async runtimes explicitly turns a runtime bug into a compile-time error.
  Switching to explicit passing the metrics registry helped me find and fix the bug.
}
◊p{
  The official documentation of the venerable ◊a[#:href "https://crates.io/crates/slog"]{slog} package also ◊a[#:href "https://github.com/slog-rs/slog/wiki/FAQ#do-i-have-to-pass-logger-around"]{recommends passing loggers explicitly}:
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
 By passing state implicitly, you gain temporary convenience but make your code less clear, less testable, and more error-prone.
 Every type of resource we passed implicitly◊sidenote["sn-resource-types"]{◊a[#:href "https://crates.io/crates/slog-scope"]{scoped} loggers, ◊a[#:href "https://crates.io/crates/prometheus"]{Prometheus} metrics registries, ◊a[#:href "https://crates.io/crates/rayon"]{Rayon} thread pools, ◊a[#:href "https://crates.io/crates/tokio"]{Tokio} runtimes, to name a few.} caused hard-to-diagnose issues and wasted a lot of engineering time.
}
◊p{
  People in other programming communities also realized that global loggers are evil.
  You might enjoy reading ◊a[#:href "https://www.yegor256.com/2019/03/19/logging-without-static-logger.html"]{Logging Without a Static Logger}.
}

◊advice["dedup-dependencies"]{Deduplicate dependencies.}

◊p{
  Cargo makes it easy to add dependencies, but this convenience comes with a cost.
  You might accidentally introduce incompatible version of the same package.
}
◊p{
  Multiple versions of the same package might result in correctness issues, especially with packages with zero major version component (◊code{0.y.z}).
  If you depend on versions ◊code{0.1} and ◊code{0.2} of the same package in a single binary, cargo will link both versions into the executable.
  If you ever pulled your hair off trying to figure out why you get that ◊a[#:href "https://github.com/awslabs/aws-lambda-rust-runtime/issues/266"]{"there is no reactor running"} error, you know how painful these issues can be to debug.
}
◊p{
  ◊a[#:href "https://doc.rust-lang.org/cargo/reference/workspaces.html#the-dependencies-table"]{Workspace dependencies} and ◊a[#:href "https://doc.rust-lang.org/cargo/commands/cargo-update.html"]{cargo update} will help you keep your dependency graph in order.
}
◊p{
  You do not have to unify the feature sets for the same dependency across the workspace packages.
  Cargo compiles each dependency version once, thanks to the ◊a[#:href "https://doc.rust-lang.org/cargo/reference/features.html#feature-unification"]{feature unification} mechanism.
}

◊advice["tests-in-separate-files"]{Put unit tests into separate files.}

◊p{
  Rust allows you to write unit tests right next to your production code.
}
◊figure{
◊marginnote["mn-test-code"]{A module that has unit tests and production code in the same file, ◊code{foo.rs}.}
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
}
◊p{
  This feature is very convenient, but it can slow down test compilation time.
  Cargo build cache can get confused when you modify the file, tricking cargo into re-compiling the crate under both ◊code{dev} and ◊code{test} profiles, even if you touched only the test part.
  By trial and error, we discovered that the issue does not occur if the tests live in a separate file.
}

◊figure{
◊marginnote["mn-moving-test"]{Moving unit tests into ◊code{foo/tests.rs}.}
◊source-code["good"]{
pub fn frobnicate(x: &Foo) -> u32 {
    todo!("implement frobnication")
}

// The contents of the module moved to foo/tests.rs.
#[cfg(test)]
mod tests;
}
}

◊p{
  This technique tightened our edit-check-test loop and made the code easier to navigate.
}
}

◊section{
◊section-title["common-pitfalls"]{Common pitfalls}

◊p{
  This section describes common issues Rust newcomers might run into.
  I experienced these issues myself and saw several colleagues struggling with them.
}

◊subsection-title["confusing-crates-and-packages"]{Confusing crates and packages}

◊p{
Imagine you have package ◊code{image-magic} defining a library for image processing and providing a command-line utility for image transformation called ◊code{transmogrify}.
Naturally, you want to use the library to implement ◊code{transmogrify}.
}

◊figure{
◊marginnote["mn-im-cargo"]{Contents of ◊code{image-magic/Cargo.toml}.}
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
}


◊p{
Now you open ◊code{transmogrify.rs} and write something like the following:
}

◊figure{
◊source-code["bad"]{
use crate::{Image, transform_image}; //< Compile error.
}
}

◊p{
The compiler will become upset and tell you something like
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
}
◊p{
So when you write ◊code{use crate::Image} in ◊code{transmogrify.rs}, you tell the compiler to look for the type defined in the same binary.
The ◊code{image_magic} ◊em{crate} is just as external to ◊code{transmogrify} as any other library would be, so we have to specify the library name in the use declaration:
}

◊figure{
◊source-code["good"]{
use image_magic::{Image, transform_image}; //< OK.
}
}

◊subsection-title["quasi-circular"]{Quasi-circular dependencies}

◊p{
To understand this issue, we'll first learn about ◊a[#:href "https://doc.rust-lang.org/cargo/reference/profiles.html"]{Cargo build profiles}.
Build profiles are named compiler configurations.
For example:
}
◊dl{
 ◊dt{release}
 ◊dd{
   The profile for production binaries.
   Highest optimization level, disabled debug assertions, long compile times.
   Cargo uses this profile when you run ◊code{cargo build --release}.
 }
 ◊dt{dev}
 ◊dd{
   The profile for the normal development cycle.
   Debug asserts and overflow checks are enabled, optimizations are disabled for faster compile times.
   Cargo uses this profile when you run ◊code{cargo build}.
 }
 ◊dt{test}
 ◊dd{
   Mostly the same as the ◊em{dev} profile.
   When you test a library crate, cargo builds the library with the ◊code{test} profile and injects the main function executing the test harness.
   This profile is enabled when you run ◊code{cargo test}.
   Cargo builds dependencies of the crate under test using the ◊em{dev} profile.
 }
}

◊p{
  Imagine now that you have a package with a library ◊code{foo}.
  You want good test coverage and the tests to be easy to write.
  So you introduce another package with many test utilities for ◊code{foo}, ◊code{foo-test-utils}.
}

◊p{
  It also feels natural to use ◊code{foo-test-utils} for testing the ◊code{foo} itself.
  Let's add ◊code{foo-test-utils} as a dev dependency of ◊code{foo}.
}

◊figure{
◊marginnote["mn-foo-cargo"]{Contents of ◊code{foo/Cargo.toml}.}
◊source-code["good"]{
[package]
name = "foo"
version = "1.0.0"
edition = "2018"

[lib]

[dev-dependencies]
foo-test-utils = { path = "../foo-test-utils" }
}
}

◊figure{
◊marginnote["mn-foo-test-cargo"]{Contents of ◊code{foo-test-utils/Cargo.toml}.}
◊source-code["good"]{
[package]
name = "foo-test-utils"
version = "1.0.0"
edition = "2018"

[lib]

[dependencies]
foo = { path = "../foo" }
}
}

◊p{
  Wait, didn't we create a dependency cycle?
  ◊code{foo} depends on ◊code{foo-test-utils} that depends on ◊code{foo}, right?
}

◊p{
  There is no circular dependency because cargo compiles ◊code{foo} twice: once with ◊em{dev} profile to link with ◊code{foo-test-utils} and once with ◊em{test} profile to add the test harness.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-dep-foo"]{Dependency diagram for ◊code{foo} library test.}
  ◊(embed-svg "images/03-foo-test-profile.svg")
}

◊p{
  Time to write some tests!
}

◊figure{
◊marginnote["mn-foo-test-lib"]{Contents of ◊code{foo-test-utils/src/lib.rs}.}
◊source-code["good"]{
use foo::Foo;

pub fn make_test_foo() -> Foo {
    Foo {
        name: "John Doe".to_string(),
        age: 32,
    }
}
}
}

◊figure{
◊marginnote["mn-foo-lib"]{Contents of ◊code{foo/src/lib.rs}.}
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
  The compiler tells us that type definitions in the ◊em{test} and the ◊em{dev} versions of ◊code{foo} are incompatible.
  Technically, these are different, incompatible crates even though these crates share the name.
}

◊p{
  The way out of trouble is to define a separate integration test crate in the ◊code{foo} package and move the tests there.
  This approach allows you to test only the public interface of the ◊code{foo} library.
}

◊figure{
◊marginnote["mn-foo-test"]{Contents of ◊code{foo/tests/foo_test.rs}.}
◊source-code["good"]{
#[test]
fn test_foo_frobnication() {
    let foo = foo_test_utils::make_test_foo();
    assert_eq!(foo::frobnicate(&foo), 2);
}
}
}

◊p{
  The test above compiles fine because cargo links the test and ◊code{foo_test_utils} with the ◊em{dev} version of ◊code{foo}.
}

◊figure[#:class "grayscale-diagram"]{
  ◊marginnote["mn-foo-test-dep-diag"]{Dependency diagram for ◊code{foo_test} integration test.}
  ◊(embed-svg "images/03-foo-dev-profile.svg")
}

◊p{
  Quasi-circular dependencies are confusing.
  They also increase the incremental compilation time considerably.
  My advice is to avoid them when possible.
}
}

◊section{
◊section-title["conclusion"]{Conclusion}

◊p{
  In this article, we looked at Rust's code organization tools.
  The key takeaways:
}
◊ul[#:class "arrows"]{
  ◊li{
    Understand the difference between modules, crates, and packages.
  }
  ◊li{
    Rust's module system is convenient, but packing many modules into a single crate degrades the build time.
  }
  ◊li{
    Factoring the code into many cohesive packages is the most scalable approach.
  }
  ◊li{
    All implicit state is nasty.
  }
}
}

◊section{
◊section-title["links"]{Further reading}

◊ul[#:class "arrows"]{
  ◊li{
    Discuss this article on ◊a[#:href "https://www.reddit.com/r/rust/comments/s818q3/blog_post_rust_at_scale_packages_crates_and/"]{r/rust}.
  }
  ◊li{
    ◊a[#:href "https://github.com/matklad"]{Alexey Kladov} wrote a fantastic blog post series on the same topic, ◊a[#:href "https://matklad.github.io/2021/09/05/Rust100k.html"]{One Hundred Thousand Lines of Rust}.
  }
  ◊li{
    If you liked this article, consider reading ◊a[#:href "/posts/17-scaling-rust-builds-with-bazel.html"]{Scaling Rust builds with Bazel}.
  }
}
}
<<<<<<< Updated upstream
}
=======
>>>>>>> Stashed changes
