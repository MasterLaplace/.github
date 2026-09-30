# Contributing

This page is shared by every repository of the account. How to build and test a given repository is
in its own README.

## How a change flows

1. **An issue** says what is asked, what is true today, what is missing, and how we will know it is
   done. The issue forms ask exactly that.
2. **A branch** from the default branch, named `<type>/<issue>-<slug>`, for example
   `fix/42-empty-config`. One branch, one intention: if its summary needs an "and", it is two branches.
3. **A pull request** that closes its issue (`Closes #42`) and says what changed, why, how to verify
   it, and what is deliberately not in it. Keep it small: a pull request that is hard to read is
   approved, not reviewed.
4. **Its title** follows [Conventional Commits](https://www.conventionalcommits.org/), in English, for
   example `fix(config): refuse an empty file`. Pull requests land as one squashed commit, so the
   title becomes the commit on the default branch and the description becomes its message. The
   commits inside the branch can be as small as you like.
5. **The changelog**: every change someone could notice adds a line under `## [Unreleased]`, written
   for whoever updates.

## What the default branch requires

- a pull request, from everyone but the maintainer, who can bypass the rule to rewrite history;
- the CI green, when the repository has one;
- no new warning: a warning that crosses a merge becomes a thousand.

## Labels

`type:*` says what kind of work an issue is, `zone:*` where it happens in the repository. Status,
priority and size are fields of the project board, never labels. `good first issue` and
`help wanted` mean what they say, and are the best place to start. `forgeron` hands an issue to the
project's automated pilot, and `forgeron:hold` takes it back.

## Conduct

Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md). A breach is reported in public, in
the `abuse-report` discussion category, without ever copying personal information.
