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

A repository without C code has no `config.h`: it passes `config-header: CITATION.cff` and no
`prefix`, and the release takes its version and its name from the citation's `version` and `title`.

```bash
tools/changelog.sh ../LplKernel                                     # what is not released yet
tools/changelog.sh --tag v0.2.0 --pending "feat(boot): a title (#42)" --output ../LplKernel/CHANGELOG.md ../LplKernel
tools/release.sh --dry-run kernel/include/kernel/config.h KERNEL    # from a repository's root
tools/test-release.sh                                               # the changelog and the release, tested
```

`actions/compare-images` shows what a change does to the images a repository draws. The repository
gives a command that writes its images (PNG or PPM) into `$IMAGES_DIR`, and
`tools/compare-images.py` compares two commits' images as [pixelmatch](https://github.com/mapbox/pixelmatch)
does. A commit's images are drawn once, on the runner, and kept on the `compare-images` branch as
its reference; the next comparisons with that commit read them back. `actions/compare-images/scope`
decides, before the drawing's setup, what to do and what to compare with:

| Event | Before | Where the comparison goes |
|---|---|---|
| a pull request touching `paths`, or labelled `label` | its target, with the pull request merged into it | a comment, with the images inline |
| a comment `/compare-images` on a pull request, from the owner, a member or a collaborator | its target; `/compare-images start` where it branched; `/compare-images v1.2.0` any commit, branch or tag | a comment for that comparison |
| a push to the default branch touching `paths` | none: the commit's images are kept as its reference | |
| a release run that tagged `vX.Y.Z` | the previous release | the release's notes |
| a manual run | its `before` input | the run's summary |
| a pull request closed | | its images and pages are deleted, its comments keep their numbers |

A new run replaces the comment of the same comparison, its images and its earlier pages. Every
comparison also leaves the table in the run's summary and a page with each changed image under a
curtain as an artifact. The branch holds a single commit rewritten each time
(`tools/publish-images.sh`): one folder per open pull request, the newest 20 references and the
newest 10 releases, and no history of old images.

```yaml
name: Frames
on:
  push:
    branches: [main]
  pull_request:
    types: [opened, synchronize, reopened, labeled, closed]
  issue_comment:
    types: [created]
  workflow_run:
    workflows: [Release]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      before:
        description: A commit, branch or tag to compare with
        default: main
permissions:
  contents: write
  pull-requests: write
  actions: write
jobs:
  compare:
    if: >-
      github.event_name != 'issue_comment' ||
      github.event.issue.pull_request && startsWith(github.event.comment.body, '/compare-images')
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          persist-credentials: false
          ref: >-
            ${{ github.event_name == 'issue_comment' && format('refs/pull/{0}/merge', github.event.issue.number) ||
            github.event_name == 'workflow_run' && github.event.workflow_run.head_sha || '' }}
      - id: scope
        uses: MasterLaplace/.github/actions/compare-images/scope@<commit> # main
        with:
          paths: '^(render|samples|engine)/'
          label: frames
          before: ${{ inputs.before }}
      # the setup the drawing needs, under: if: steps.scope.outputs.run == 'true'
      - if: steps.scope.outputs.run == 'true' || steps.scope.outputs.closed == 'true'
        uses: MasterLaplace/.github/actions/compare-images@<commit> # main
        with:
          title: Reference frames
          before: ${{ steps.scope.outputs.before }}
          draw: xmake run lpl-frames --write "$IMAGES_DIR"
          comment-when: ${{ steps.scope.outputs.labelled == 'true' && 'always' || 'changed' }}
```

Its other inputs: `threshold` (0.1), `comment` (`replace`, `update` or `off`), `release-notes`
(true), `images-branch`, `keep-references` (20), `keep-releases` (10), `retention-days` (14) and
`fail-on-change` (false: a changed image is for the reviewer to judge).

```bash
python3 tools/compare-images.py --draw 'xmake run lpl-frames --write "$IMAGES_DIR"' --before main   # from a repository's root
python3 tools/compare-images.py --compare before/ after/ --out build/compare-images                  # two directories already drawn
tools/test-compare-images.sh                                                                         # the comparison and the images branch, tested
```

A change to any of these goes through a pull request here, like code.
