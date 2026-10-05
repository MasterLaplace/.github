# MasterLaplace/.github

The files every public repository of this account shows when it has none of its own: the code of
conduct, how to contribute, the security policy, where to get support, the issue and pull request
forms, and the form for reporting a breach of the code of conduct.

`etabli.json` declares how the Laplace repositories are kept: labels, merge settings, security
switches and branch rules. It is applied by `forgeron etabli` from
[LplCraftSkills](https://github.com/MasterLaplace/LplCraftSkills):

```bash
python3 -m forgeron etabli --file etabli.json            # the plan, nothing is written
python3 -m forgeron etabli --file etabli.json --write    # apply, then read again
```

`templates/config.h` is the header every Laplace repository copies under its own prefix: its name,
its version, the build it went into, what it needs from the other repositories, and where it runs.
`tools/check-config-header.sh` compares a copy with the template, and `--write` brings a copy back to
it:

```bash
tools/check-config-header.sh ../LplKernel/kernel/include/kernel/config.h KERNEL
tools/test-config-header.sh                                   # the template and the check, tested
```

`actions/check-config-header` runs that check in a repository's own CI, against the template at the
commit it is pinned to, from `.github/workflows/config-header.yml`:

```yaml
name: config.h
on:
  pull_request:
    paths: [kernel/include/kernel/config.h, .github/workflows/config-header.yml]
  push:
    branches: [main]
    paths: [kernel/include/kernel/config.h, .github/workflows/config-header.yml]
permissions:
  contents: read
jobs:
  template:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: MasterLaplace/.github/actions/check-config-header@<commit> # main
        with:
          config-header: kernel/include/kernel/config.h
          prefix: KERNEL
```

Moving the pin to a newer commit is how a repository takes a change of the template: the pull
request that moves it is where its copy is brought back with `--write`.

A release is cut from that version. `tools/changelog.sh` writes a repository's `CHANGELOG.md` from
its commit titles with the shared `templates/cliff.toml`, and `actions/release` runs
`tools/release.sh`: when `config.h` gives a version later than the last `vX.Y.Z` tag, it checks that
`CITATION.cff` and `CHANGELOG.md` agree with it, then tags the commit and publishes the GitHub
release, whose notes are that version's section. On a pull request it runs the same check as the
squash merge will land, and creates nothing. A repository calls it from
`.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    branches: [main]
  pull_request:
    types: [opened, edited, reopened, synchronize]
  workflow_dispatch:
permissions:
  contents: read
jobs:
  check:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
      - uses: MasterLaplace/.github/actions/release@<commit> # main
        with:
          config-header: kernel/include/kernel/config.h
          prefix: KERNEL
  release:
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-24.04
    permissions:
      contents: write
    concurrency: release
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
      - uses: MasterLaplace/.github/actions/release@<commit> # main
        with:
          config-header: kernel/include/kernel/config.h
          prefix: KERNEL
```

```bash
tools/changelog.sh ../LplKernel                                     # what is not released yet
tools/changelog.sh --tag v0.2.0 --pending "feat(boot): a title (#42)" --output ../LplKernel/CHANGELOG.md ../LplKernel
tools/release.sh --dry-run kernel/include/kernel/config.h KERNEL    # from a repository's root
tools/test-release.sh                                               # the changelog and the release, tested
```

A change to any of these goes through a pull request here, like code.
