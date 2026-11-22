# Repository

This project is my blog built on top of a custom blog engine.

# Code comments

The first line in any doc comment should be a short sentence providing a summary of the code.
The summary line should be written in third person singular present indicative form.
Use simple, direct language.
Avoid passive voice whenever possible.
Start every sentence on a new line.

Don't describe implementation details in doc comments.
Comment before the relevant line in the function body instead.

# Code structure

Don't create `mod.rs` files.
Use the `mymod.rs` + `mymod/submod.rs` convention instead.
When adding a new module, place its tests in a separate file.

Prefer importing from packages that defined the symbols.
Don't use full symbol qualifiers (`crate::mod::X`) in regular code,
import the module instead.
If an import list doesn't fit on a single line,
prefer importing the module and qualifying symbols (`mod::X`, not `crate::...`) instead.

Prioritize test execution speed.
Avoid relying on timing.
Use proper synchronization instead.

# Docs

Never touch README.md without an explicit request.

# Dependencies

Ask permission to import any new dependency.

# Git

Ask for permission before invoking any mutating `git` or `gh` commands.
