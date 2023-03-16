#lang pollen

◊(define-meta title "Scaling Rust builds with Bazel")
◊(define-meta keywords "rust, bazel")
◊(define-meta summary "How and why DFINITY builds Rust with Bazel.")
◊(define-meta doc-publish-date "2023-03-20")
◊(define-meta doc-updated-date "2023-03-20")

◊section{
◊section-title["introduction"]{Introduction}
◊p{
  As of March 2023, the Internet Computer repository contains about six hundred thousand lines of Rust code.
  Last year, we started using Bazel as our primary build system, and we couldn't have been happier with the switch.
  This article explains the motivation behind this move and the migration process details.
}
}

◊section{
◊section-title["cargo-limitations"]{Cargo's limitations}
◊p{
  Many Rust newcomers, especially those with a C++ background, swear by cargo.
  Rust tooling is fantastic for beginners, but we became dissatisfied with cargo as the project size increased.
}
◊subsection-title["not-a-build-system"]{Cargo is not a build system}
◊epigraph{
  ◊blockquote[#:cite "https://doc.rust-lang.org/cargo/"]{
    ◊p{
      Cargo is the ◊a[#:href "https://www.rust-lang.org/"]{Rust} ◊a[#:href "https://doc.rust-lang.org/cargo/appendix/glossary.html#package-manager"]{◊em{package manager}}.
      Cargo downloads your Rust ◊a[#:href "https://doc.rust-lang.org/cargo/appendix/glossary.html#package"]{package's} dependencies, compiles your packages, makes distributable packages, and uploads them to ◊a[#:href "https://crates.io"]{crates.io}.
    }
    ◊footer{◊a[#:href "https://doc.rust-lang.org/cargo/"]{The Cargo Book}}
  }
}
◊p{
  Let's acknowledge the elephant in the room: cargo is not a build system; it's a tool for building and distributing Rust packages.
  It can build Rust code for a specific platform with a given set of features in a single invocation.
  Cargo chose simplicity and ease of use over generality and scalability; it does not track dependencies well or support arbitrary build graphs.
}
◊p{
  These trade-offs make cargo easy to pick up but impose severe limitations in a complex project.
  Some workarounds work up to a point, such as ◊a[#:href "https://github.com/matklad/cargo-xtask"]{xtask}, but they will only get you so far.
  Let's consider an example of what many of our tests must do:
}
◊ul[#:class "arrows"]{
  ◊li{Build a sandbox binary for executing WebAssembly.}
  ◊li{Build a WebAssembly program.}
  ◊li{Post-process the WebAssembly program (strip some custom sections and compress the result, for example).}
  ◊li{Build a test binary that launches the sandbox binary, sends the WebAssembly program to the sandbox and interacts with the program.}
}
◊p{
  This simple scenario requires invoking cargo three times with different arguments and appropriately post-processing and threading the build artifacts.
  There is no way to express such a test using cargo alone; another build system must orchestrate the test execution.
}
◊subsection-title["poor-caching"]{Poor caching and dependency tracking}
◊p{
  Like notorious ◊a[#:href "https://en.wikipedia.org/wiki/Make_(software)"]{Make}, cargo relies on file modification timestamps for incremental builds.
  Updating code comments or switching git branches can invalidate cargo's cache, causing long rebuilds.
  Furthermore, cargo does not track specific dependencies of the build artifacts.
  For example, we can tell cargo to ◊a[#:href "https://doc.rust-lang.org/cargo/reference/build-scripts.html#outputs-of-the-build-script"]{rerun build.rs} if some input files or environment variables change.
  Still, cargo has no idea which files or other resources tests might be accessing, so it must be conservative with caching.
  Consequently, we often build way more than we need to, and sometimes our builds fail with confusing errors that go away after ◊code{cargo clean}.
}
}

◊section{
◊section-title["the-ci-saga"]{The CI saga}
◊p{
  Over the project life, we used various tools to mitigate the cargo's limitations, with mixed success. 
}
◊subsection-title["the-nix-days"]{The nix days}
◊p{
  When we started the Rust implementation in mid-2019, we relied on nix to build all our software and set up the development environment in a cross-platform way (we develop both on macOS and Linux).
}
◊p{
  As our code base grew, we started to feel nix's limitations.
  The unit of caching in nix is a derivation.
  If we wanted to take full advantage of nix's caching capabilities, we would have to "nixify" all our external dependencies and internal Rust packages (one derivation per Rust package).
  After a long fight with build reproducibility issues, our glorious dev-infra team implemented fine-grained caching using the cargo2nix project.
}
◊p{
  Unfortunately, most developers in the team were uncomfortable with nix.
  Nix became a constant source of confusion and lost developer productivity.
  Since nix has a steep learning curve, only a few Nix wizards could understand and modify the build rules.
  This nix-alienation bifurcated our build environment: the CI servers built the code with nix-build, and developers built the code by entering the nix-shell and invoking cargo.
}
◊subsection-title["the-iceberg"]{The Iceberg}
◊p{
  The final blow to the nix story came around late-2020, close to the network launch.
  Our security team chose Ubuntu as the deployment target and insisted that production binaries link against the regularly updated system libraries (libc, libc++, openssl, etc.) the deployment platform provides.
  This setup is hard to achieve in nix without compromising correctness◊sidenote["sn-patchelf"]{We considered using patchelf, but it's a bad idea in general:  libc++ from nix packages can be incompatible with the one installed on the deployment platform}.
}
◊p{
  Furthermore, the infrastructure team got a few new members unfamiliar with nix and decided to switch from nix to a more familiar technology, Docker containers.
  The team implemented a new build system that runs regular cargo builds inside a docker container with the versions of dynamic libraries identical to those in the production environment.
  The new system grew organically and eventually evolved into a hot mess of a hundred GitLab Yaml configuration files calling shell and python scripts in the correct order.
  These scripts used the known filesystem locations and environment variables to pass the build artifacts around.
  Most integration tests ended up as shell scripts expected some inputs that the CI pipeline produces.
}
◊p{
  Of course, the new Docker-based build system lost the granular caching capabilities of nix-build.
  The infra team attempted to build a custom caching system but eventually abandoned the project.
  Cache invalidation is a challenging problem indeed.
}
◊p{
  With the new system, the chasm between the CI and development environments deepened further because the nix-shell didn't go anywhere.
  The developers continued to use nix-shell for everyday development.
  It's hard to pinpoint the exact reason.
  I attribute that to the fact that entering the nix-shell is less invasive than entering a docker container, and nix-shell does not require running in a virtual machine on macOS (Rust compile times are slow).
  Also, the infra team was so busy rewriting the build system that improving the everyday developer experience was out of reach.
}
◊p{
  I call this setup an "iceberg": on the surface, a developer needed only nix and cargo to work on the code, but in practice, that was only 10% of the story.
  Since most tests required a CI environment, developers had to create merge requests to check whether their code worked beyond the basic unit tests.
  The tests accumulated over time, the load on the CI system grew, and eventually, the builds became unbearably slow and flaky.
  It was time for another change.
}
◊subsection-title["enter-bazel"]{Enter Bazel}
◊p{
  Among about a dozen build systems I worked with, Bazel is the only one that made sense to me (it might also well be that I never learned to do anything without involving protocol buffers).
  One of my favorite features of Bazel is how explicit and intuitive it is for everyday use.
}
◊p{
  Bazel is like a good videogame: it's easy to learn and challenging to master.
  It's easy to define and wire build targets (that's what most engineers do), but adding new build rules requires some expertise.
  Every engineer at Google can write correct build files without knowing much about Blaze (Google's internal variant of Bazel).
  The build files are verbose bordering plain boring, but it's a good thing.
  They tell the reader precisely what the module's artifacts and dependencies are.
}
◊p{
  Bazel offers many features, but we mostly cared about the following:
}
◊ul[#:class "arrows"]{
  ◊li{
    Bazel is extensible enough to cover all our use cases.
    Bazel gracefully handled everything we threw at it: Linux and macOS binaries, WebAssembly programs, OS images, Docker containers, Motoko programs, TLA+ specifications, etc.
    The best part is: We can also combine and mix these artifacts in any way we like.
  }
  ◊li{
    Aggressive caching.
    The sandboxing feature ensures that build actions do not use undeclared dependencies, making it much safer to cache build artifacts and, most importantly for us, test results.
  }
  ◊li{
    Remote caching.
    We use the cache from our CI system to speed up developer builds.
  }
  ◊li{
    Distributed builds.
    Bazel can distribute tasks across multiple machines to finish builds even faster.
  }
  ◊li{
    Visibility control.
    Bazel allows package authors to mark some packages as internal to prevent other teams from importing the code.
    Controlling dependency graphs is crucial for fast builds.
  }
  ◊li{
    Even more importantly, Bazel unifies our development and CI environments.
    All our tests are Bazel tests now, meaning that every developer can run any test locally.
    At its heart, our CI job is ◊code{bazel test --config=ci //...}.
  }
  ◊li{
    One nice feature of our Bazel setup is that we can configure versions of our external dependencies in a single file.
    Ironically, cargo developers implemented support for workspace dependency inheritance a few weeks after we finished the migration.
  }
}
}

◊section{
◊section-title["the-migration-process"]{The migration process}
◊epigraph{
  ◊blockquote{
    ◊p{You are such a naïve academic. I asked you how to do it, and you told me what I should do. I know what I need to do. I just don't know how to do it.}
    ◊footer{Attributed to Andy Groove; see ◊quoted{The 4 Disciplines of Execution} by Jim Huling, Chris McChesney, and Sean Covey, page xx.}
  }
}

◊p{
  The idea of migrating the build system came from a few engineers (read Xooglers) who were tired of fighting with long build times and poor tooling.
  To our surprise, a few volunteers expressed interest in joining the rebellion at its earliest stage.
  We needed a plan for executing the switch and getting the management's buy-in.
}
◊p{
  The first rule of large codebases is to introduce significant changes gradually. This section describes our process of migration, which took several months.
}
◊subsection-title["prototype"]{Build a prototype}
◊p{
  We started migration by building a prototype.
  We created a sample repository that mimicked the features of our code base that we expected to bring the most trouble, such as generating Protocol Buffer types using the prost library, compiling Rust to WebAssembly and native code in a single invocation, and setting up rust-analyzer support.
  Once we knew that the most complex problems we face have a solution at a small scale, we presented the case to the management, explained the final vision, how many people and time we needed, and got a green light.
  Now the real work began.
}

◊subsection-title["dig-a-tunner-from-the-middle"]{Dig a tunnel from the middle}
◊p{
  Our CI was a multi-stage process that treated cargo as a black box producing binaries from the source code.
  There were two major work streams in our mission to minimize build times:
}
◊ol-circled{
  ◊li{
    Replace the spaghetti of YAML files and scripts using cargo as a black box with neat Bazel targets with explicit dependencies.
    This change would bring clarity and confidence to our CI routines and enable developers to access the build artifacts without an entire CI run.
  }
  ◊li{
    Use Bazel to build binaries from Rust code directly, bypassing cargo.
    This change would significantly improve our cache hit rate and allow us to avoid running expensive tests.
  }
}
◊p{
  These work streams require different skill sets, and we wanted to start working on them in parallel.
  To unblock the first workstream, we created a simple Bazel rule that treated cargo as a black box and produced binaries for deployment and tests.
  This way, our infrastructure experts could figure out how to build OS images with Bazel, while our Rust experts could proceed with the Rust code "bazelification".
}

◊subsection-title["run-ci-early"]{Run CI early}
◊p{
  We added the "bazel test //..." job to our CI pipeline as soon as we had the first BUILD file in our repository.
  The extra job slightly increased the CI wait time but ensured that packages converted to Bazel wouldn't degrade over time.
  As a side benefit, developers started to experience Bazel-related CI failures during their code refactorings.
  They actively learned to modify BUILD files and gradually became accustomed to the new world.
}

◊subsection-title["one-package-at-a-time"]{One package at a time}
◊p{
  The goal of the second workstream was converting a few hundred Rust packages to the new build rules.
  We started from the core packages at the bottom of the stack that needed special treatment, and then project volunteers bazelified a few packages at a time when they had a free time slot.
  Two little tricks helped us with this tedious task:
}
◊ul[#:class "arrows"]{
  ◊li{
    Automation.
    The infra team invested a few days in a script that converted a ◊code{Cargo.toml} file to a 90% complete ◊code{BUILD} file matching our guidelines.
    Many packages required manual treatment, and the generated BUILD file was far from optimal, but the script boosted the conversion process significantly.
  }
  ◊li{
    Progress visualization.
    One team member wrote a utility visualizing the migration progress by inspecting the cargo dependency graph and searching for packages with and without BUILD files.
    This little tool had a tremendous effect on our morale.
  }
}
◊p{
  Eventually, we could build and test every piece of our Rust code with Bazel. We then switched the OS build from the cargo_build bootstrapping to the binaries built from the source using Bazel rules.
}

◊subsection-title["test-parity"]{Ensure test parity}
◊p{
  The last piece of the puzzle was ensuring the test parity.
  Cargo discovers tests automagically, while Bazel BUILD files require explicit targets for each type of test (crate tests, doc tests, integration tests).
  The infra team wrote another little utility that analyzed the outputs of cargo and Bazel build pipelines and compared the list of executed tests, ensuring that the volunteers accounted for every test during the migration and that developers didn't forget to update BUILD files when they added new tests.
}

◊subsection-title["rough-edges"]{Rough edges}
◊p{
  Bazel solves most of our needs regarding building artifacts, but we have yet to replicate a few cargo features related to developer flow.
}
◊ul[#:class "arrows"]{
  ◊li{
    Cargo check.
    Cargo does not produce binaries when run in check mode, making it much faster than cargo build.
    Developers often use this mode to check whether the entire code base compiles after a refactoring.
  }
  ◊li{
    IDE support.
    The rules_rust Bazel plugin offers experimental support for rust-analyzer, which worked perfectly in the prototype but choked on our code base.
    We invested a lot of time in making the new setup work, but we still keep cargo files around to keep developers relying on IntelliJ Rust happy (see https://github.com/intellij-rust/intellij-rust/issues/5594). 
  }
  ◊li{
    Publishing packages.
    We want to publish some of our Rust packages to crates.io, and the rules_rust Bazel plugin does not provide a replacement for "cargo publish" yet.
  }
}
◊p{
  Because of these issues, we still keep cargo files around. Luckily, this does not affect our CI times much because the only check we need is that "cargo check --tests --benches" succeeds. 
}
}

◊section{
◊section-title["acknowledgements"]{Acknowledgments}
◊p{
  The Bazel migration project was a definitive success.
  I thank our talented infra team and all the volunteers who contributed to the project.
  Special thanks go to the developers and maintainers of the rules_rust Bazel plugin, who unblocked us many times during the migration, especially Andre Uebel (https://github.com/UebelAndre) and Daniel Wagner-Hall (https://github.com/illicitonion).
}
}
