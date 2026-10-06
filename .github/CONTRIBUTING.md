# Contributing

This page is shared by every repository of the account. How to build and test a given repository is
in its own README, and what only holds in one repository is in its own CONTRIBUTING, which links back
here. Everything in a repository is written in English, the LplKernel book and LplCraftSkills
excepted.

## How a change flows

1. **An issue** says what is asked, what is true today, what is missing, and how we will know it is
   done. The issue forms ask exactly that.
2. **A branch** from the default branch, named `<type>/<issue>-<slug>`, for example
   `fix/42-empty-config`. One branch, one intention: if its summary needs an "and", it is two branches.
   Create it without tracking the default branch, `git switch --no-track -c fix/42-empty-config
   origin/main`, and push it under its own name, `git push -u origin fix/42-empty-config`. A branch
   whose upstream is `main` sends a plain push, or an editor's "Sync", to `main`
   (`git config --global branch.autoSetupMerge simple` makes the safe behaviour the default).
3. **A pull request** that closes its issue (`Closes #42`) and says what changed, why, how to verify
   it, and what is deliberately not in it. Keep it small: a pull request that is hard to read is
   approved, not reviewed.
4. **Its title** follows [Conventional Commits](https://www.conventionalcommits.org/), in English:
   `type(scope)!: description`, with `type` one of `feat`, `fix`, `docs`, `chore`, `refactor`,
   `style`, `ci`, `test`, `perf`, `build` or `revert`, a scope that may name several areas
   (`feat(apps,samples)`), and `!` when something breaks for an existing caller. Pull requests land as
   one squashed commit, so the title becomes the commit on the default branch and the description
   becomes its message. The commit check enforces the form.
5. **Each commit names the people who answer for it.** A co-author line names a person, never a
   tool, and no footer credits one; the formatting bot (`github-actions[bot]`) is the one exception,
   since it is a deterministic tool whose work is worth seeing.
6. **The changelog** is generated from the commit titles, and the pull request that raises the version
   writes it, filing everything since the last release under the new version. A title is therefore
   written for whoever updates; a `style`, `ci` or `test` commit changes nothing a user of the release
   sees, and is left out.

## What the default branch requires

- a pull request from everyone, the maintainer included: the rule can only be bypassed through a pull
  request;
- signed commits;
- the required checks green, and no new warning: a warning that crosses a merge becomes a thousand.
  A commit pushed by the formatting bot starts no check, since GitHub runs no workflow on what its
  own token pushes: when it is the last commit, edit the pull request or push again.

## Versions

Every repository has its own version, in [SemVer 2.0.0](https://semver.org/): `MAJOR.MINOR.PATCH`,
because file formats and libraries are contracts, and the number says when one breaks. `MAJOR` moves
when an existing caller breaks, a format or a behaviour included; `MINOR` when a capability is added;
`PATCH` for a fix. While a version is `0.y.z` nothing is promised; compatibility starts at `1.0.0`.
What identifies a build (a profile, debug or release) travels as build metadata, as in
`0.1.0+server.debug`, never as a fourth number. A release is a tag `vX.Y.Z` with its changelog
section.

The version is written once, in the repository's `config.h`, a copy of
[templates/config.h](https://github.com/MasterLaplace/.github/blob/main/templates/config.h): the build, the release and `CITATION.cff` read it
there, and every binary carries it. A repository without C code has no `config.h`: its version is the
one its `CITATION.cff` gives, and the release reads it there. The pull request that changes what another repository or a user
can see raises it, sets `version` and `date-released` in `CITATION.cff`, and writes `CHANGELOG.md`
with `tools/changelog.sh --tag vX.Y.Z --pending "<its title> (#<its number>)"`. Its release check
refuses a citation or a changelog that disagrees; once it is merged, the same check tags the commit
and publishes the release, whose notes are that version's section. A repository that needs another one says so in its own `config.h`, with
`<PREFIX>_COMPATIBLE_WITH(major, minor, patch)`: at least that version, in the same major, checked by
the compiler whatever the build system. Only the shared part of a `config.h` comes from the template,
and `tools/check-config-header.sh` refuses a copy where it has drifted.

## Evidence

- **A claim about behaviour comes from a run, not from reading the code.** Reading gives a
  hypothesis; a probe, a test or a measurement settles it.
- **A number quoted in an issue, a pull request or a document comes with the command that produced
  it, and that command is in the repository.** A figure computed in a one-off shell line is an
  anecdote: nobody can run it again, and the next person computes it differently.
- **A check has been seen failing.** Break what it guards once, watch it go red, restore it. A check
  that cannot fail passes for every reason, the wrong one included.
- **An expected value is computed apart from the code under test**, never copied from its output: a
  value copied from the output only asserts that the code agrees with itself.

## Before writing code

- **Search for the concept, not the name.** What you are about to write often exists under another
  name. When a second user of a piece of code appears, move it to a shared place before a third copy
  is written.
- **No capability without a caller outside the tests.** A function, a format field or a code path
  ships with the code that uses it; until then it is not written, because nothing can tell when it is
  wrong.

## Data and formats

- **Zero is a value.** An index is one-based so that zero keeps meaning "none", and where the whole
  range of a field means something, the "any" or "unknown" sentinel is taken outside that range.
- **An identifier travels as it is.** A writer never renumbers one; a stored reference is a position
  (a row, an index) or the source's own identifier, never a hash of a name, which collides at scale.

## Messages

- **Two causes of failure are two messages**: absent is not unreadable, refused is not unreachable,
  "no data" is not "all sea".
- **A refusal names what it refuses**: the file, the field, the two names that collided.
- **A zero that means "not counted" is not printed as zero.** A counter nobody fills is worse than
  one nobody prints.

## C and C++

What holds in every C and C++ repository. Each repository adds its own rules in its CONTRIBUTING.

- **Formatting** is the `.clang-format` shared by every C and C++ repository, applied by its linter
  workflow. Nobody formats by hand.
- **One kind of content per file.**
  - `.h` and `.hpp` declare. A function body longer than one line goes in a `.inl` that the header
    includes at its end; only a one-line body, such as an accessor, stays in the class.
  - `.c` and `.cpp` define. CUDA code lives in `.cu`, its headers in `.cuh`.
  - Assembly lives in `.s` or `.S` (shared constants in a `.inc`), never inline in C or C++. Where a
    compiler intrinsic or a standard function says the same thing (`__yield()`,
    `std::atomic_signal_fence`), it is used instead. The one exception is the benchmark barrier that
    keeps a value from being optimised away: nothing else can express it, and it says so where it
    stands.
- **Every header (`.h`, `.hpp`, `.cuh`) opens with its repository's licence block**: a title line with
  the repository's name and version, the licence notice, then `@file`, `@brief`, `@author`,
  `@version` and `@date`. Copy it from a neighbouring header. A `.c`, `.cpp`, `.cu` or `.inl` starts
  with its includes: what a block would say there belongs in the header's documentation.
- **Acronyms are spelled out in public identifiers**: `peripheral_component_interconnect_scan`, not
  `pci_scan`, and `hardware_abstraction_layer_display_present`, not `hal_display_present`. File
  names, `#include` paths and the include guards that mirror them keep the short form.
- **C** is `snake_case`. **C++** is `lpl::module::Type`, with `PascalCase` types and `camelCase`
  functions.
- **No `using` to shorten a namespace**, tests included: write `lpl::math::Fixed32` where it is used,
  never `using namespace` nor `using lpl::math::Fixed32;`. A short alias that names an abstraction of
  its own, such as `using FVec3 = lpl::math::Vec3<lpl::math::Fixed32>;`, is fine.
- **A source file reads from its parts to the whole**: its `static` helpers first, then the functions
  it exports.
- **No comment inside a function body**, `TODO` excepted. What a comment would say becomes the name
  of an extracted function, or the function's documentation.
- **Documentation is Doxygen, in one format.** A public function gets a deployed block, never a
  one-liner; a private one needs none:

  ```c
  /**
   * @brief Say what the function does, in one sentence.
   *
   * @param name What the parameter is.
   * @return What comes back, and when.
   */
  ```

  A member, an enum value or a `#define` gets a trailing `/**< ... */` or `///<`. A group of
  declarations under a title gets `@name` with `@{` and `@}`, never nested. No `/* ** */` or `//`
  documentation, no `///` except the trailing `///<`, and no banner comment to separate sections (a
  file's licence block is not one); `#endif /* GUARD */`, `} // namespace`, row labels in data tables
  and `#` comments in assembly stay as they are.

## Labels

`type:*` says what kind of work an issue is, `zone:*` where it happens in the repository. Status,
priority and size are fields of the project board, never labels. `good first issue` and
`help wanted` mean what they say, and are the best place to start. `forgeron` hands an issue to the
project's automated pilot, and `forgeron:hold` takes it back.

## Conduct

Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md). A breach is reported in public, in
the `abuse-report` discussion category, without ever copying personal information.
