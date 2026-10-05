#!/usr/bin/env bash
set -uo pipefail

usage() {
    cat <<'EOF'
Usage: test-release.sh

Tests tools/changelog.sh and tools/release.sh on throwaway repositories: the changelog
regenerates identically, leaves release and style commits out and puts a breaking change
first; a release happens on a later version only, and is refused on an earlier one, on a
CITATION.cff or a CHANGELOG.md that disagrees, or on a changelog that misses a commit.
gh is replaced by a stub that records its arguments, so nothing leaves the machine.
Prints one PASS or FAIL line per check, then ALL PASS or the number of failures.
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

here="$(cd "$(dirname "$0")/.." && pwd)"
changelog="$here/tools/changelog.sh"
release="$here/tools/release.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
failures=0
checks=0

record() {
    checks=$((checks + 1))
    if [ "$1" -eq 0 ]; then echo "PASS  $2"; else echo "FAIL  $2"; failures=$((failures + 1)); fi
}

expect_success() { local label="$1"; shift; "$@" > "$work/out" 2>&1; record $? "$label"; }
expect_failure() {
    local label="$1" pattern="$2"; shift 2
    if "$@" > "$work/out" 2>&1; then record 1 "$label (it succeeded)"; return; fi
    grep -q -- "$pattern" "$work/out"; record $? "$label"
}
expect_true() { local label="$1"; shift; "$@"; record $? "$label"; }
expect_output() {
    local label="$1" pattern="$2"; shift 2
    "$@" > "$work/out" 2>&1 && grep -q -- "$pattern" "$work/out"; record $? "$label"
}

mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/gh-arguments"\n' "$work" > "$work/bin/gh"
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"

repo="$work/probe"
git init -q -b main "$repo"
cd "$repo" || exit 2
git config user.name probe
git config user.email probe@example.invalid
git config commit.gpgsign false
git config tag.gpgsign false

commit() { GIT_COMMITTER_DATE="$1T12:00:00Z" GIT_AUTHOR_DATE="$1T12:00:00Z" git commit -q --allow-empty -m "$2" "${@:3}"; }

set_version() {
    mkdir -p include
    printf '#define PROBE_NAME "Probe"\n#define PROBE_VERSION_MAJOR %s\n#define PROBE_VERSION_MINOR %s\n#define PROBE_VERSION_PATCH %s\n' \
        "$1" "$2" "$3" > include/config.h
}

cite() { printf 'cff-version: 1.2.0\ntitle: "Probe"\nversion: "%s"\ndate-released: "%s"\n' "$1" "$2" > CITATION.cff; }

today="$(date -u +%Y-%m-%d)"
commit 2026-01-01 "feat(core): a first capability (#1)"
commit 2026-01-02 "fix: a first fix (#2)"
commit 2026-01-03 "style: apply clang-format"
commit 2026-01-03 "ci(lint): a workflow change"
commit 2026-01-03 "test(core): a new case"
commit 2026-01-04 "delete: an old type outside the convention"
commit 2026-01-05 "Initial commit, not conventional"
commit 2026-01-06 "refactor(api)!: rename the entry point (#3)"

"$changelog" > "$work/first.md" 2> "$work/out"
record $? "changelog.sh prints the history"
"$changelog" > "$work/second.md" 2>&1
cmp -s "$work/first.md" "$work/second.md"; record $? "the changelog regenerates identically"
grep -q '^## \[Unreleased\]$' "$work/first.md"; record $? "untagged commits are filed under Unreleased"
! grep -qiE 'clang-format|workflow change|new case' "$work/first.md"; record $? "style, ci and test commits are left out"
! grep -q 'not conventional' "$work/first.md"; record $? "a title outside Conventional Commits is left out"
grep -q '^- An old type outside the convention$' "$work/first.md"; record $? "an unknown type is kept, under Other"
expect_true "a breaking change comes first" test "$(grep -m 1 '^### ' "$work/first.md")" = "### Breaking"
grep -q '^- \*\*core\*\*: A first capability (#1)$' "$work/first.md"; record $? "an entry is the scope and the title"
expect_true "the file ends with one newline" test "$(tail -c 2 "$work/first.md" | od -An -c | tr -d ' ')" != '\n\n'
expect_failure "changelog.sh refuses a tag that is not vX.Y.Z" "expected vX.Y.Z" "$changelog" --tag 1.0

set_version 0 1 0
expect_failure "no CITATION.cff: refused" "no CITATION.cff" "$release" --dry-run include/config.h PROBE
cite 0.2.0 "$today"
expect_failure "CITATION.cff with another version: refused" "CITATION.cff gives version 0.2.0" "$release" --dry-run include/config.h PROBE
printf 'cff-version: 1.2.0\nversion: "0.1.0"\n' > CITATION.cff
expect_failure "CITATION.cff without date-released: refused" "no date-released" "$release" --dry-run include/config.h PROBE
cite 0.1.0 "$today"
expect_failure "no CHANGELOG.md: refused" "no CHANGELOG.md" "$release" --dry-run include/config.h PROBE
"$changelog" --output CHANGELOG.md
expect_failure "a changelog without the version's section: refused" "no section for 0.1.0" "$release" --dry-run include/config.h PROBE
"$changelog" --tag v0.1.0 --output CHANGELOG.md
cite 0.1.0 2000-01-01
expect_failure "a changelog dated unlike CITATION.cff: refused" "CITATION.cff 2000-01-01" "$release" --dry-run include/config.h PROBE

sed -i -E "s/^(## \[0\.1\.0\] - ).*/\\12026-01-07/" CHANGELOG.md
cite 0.1.0 2026-01-07
expect_output "a changelog written on an earlier day still passes" "would tag v0.1.0" "$release" --dry-run include/config.h PROBE
grep -q '^- \*\*api\*\*: Rename the entry point (#3)$' "$work/out"; record $? "the release notes are the version's section"
! grep -q '^## ' "$work/out"; record $? "the release notes leave the heading out"

cp CHANGELOG.md "$work/good.md"
sed -i 's/A first fix/A first fix, edited by hand/' CHANGELOG.md
expect_failure "a changelog edited by hand: refused" "not what the history gives" "$release" --dry-run include/config.h PROBE
cp "$work/good.md" CHANGELOG.md
commit 2026-01-08 "feat: merged while the release waited (#4)"
expect_failure "a changelog that misses a commit: refused" "not what the history gives" "$release" --dry-run include/config.h PROBE
"$changelog" --tag v0.1.0 --output CHANGELOG.md
cite 0.1.0 "$today"
git add -A && commit 2026-01-09 "chore(release): 0.1.0 (#5)"
expect_output "the release commit itself is left out, so the merge passes" "would tag v0.1.0" "$release" --dry-run include/config.h PROBE

export GITHUB_OUTPUT="$work/github-output"
: > "$GITHUB_OUTPUT"
expect_output "a later version is released" "Probe 0.1.0 released as v0.1.0" "$release" include/config.h PROBE
{ grep -qx release "$work/gh-arguments" && grep -qx v0.1.0 "$work/gh-arguments" && grep -qx "$(git rev-parse HEAD)" "$work/gh-arguments"; } 2> /dev/null
record $? "gh creates release v0.1.0 on the commit"
grep -qx "Probe 0.1.0" "$work/gh-arguments" 2> /dev/null; record $? "the release is titled with the name and the version"
grep -qx 'released=true' "$GITHUB_OUTPUT" && grep -qx 'version=0.1.0' "$GITHUB_OUTPUT"; record $? "the outputs say what was released"

git tag v0.1.0
rm -f "$work/gh-arguments"
: > "$GITHUB_OUTPUT"
expect_output "the same version: nothing to release" "nothing to release" "$release" include/config.h PROBE
[ ! -e "$work/gh-arguments" ] && grep -qx 'released=false' "$GITHUB_OUTPUT"; record $? "nothing to release calls no gh"
unset GITHUB_OUTPUT

set_version 0 0 9
expect_failure "an earlier version: refused" "a version never goes back" "$release" --dry-run include/config.h PROBE
commit 2026-02-01 "perf: a faster path (#6)"
git tag v0.9.0
set_version 0 10 0
cite 0.10.0 "$today"
commit 2026-02-02 "fix: after 0.9.0 (#7)"
"$changelog" --tag v0.10.0 --output CHANGELOG.md
expect_output "0.10.0 comes after 0.9.0, not before" "would tag v0.10.0" "$release" --dry-run include/config.h PROBE
grep -q '^## \[0\.1\.0\] - 2026-01-09$' CHANGELOG.md; record $? "a released section keeps the date of its tagged commit"
expect_true "one section per release" test "$(grep -c '^## \[' CHANGELOG.md)" -eq 3

git add -A && commit 2026-02-03 "chore(release): 0.10.0 (#8)"
git tag v0.10.0
git switch -q -c feature
commit 2026-02-04 "feat: an intermediate step of the branch"
set_version 0 11 0
cite 0.11.0 "$today"
title="feat(pack)!: a new section (#9)"
"$changelog" --tag v0.11.0 --pending "$title" --history main --output CHANGELOG.md
grep -q '^- \*\*pack\*\*: A new section (#9)$' CHANGELOG.md; record $? "a pending title is filed under the release it raises"
! grep -q 'intermediate step' CHANGELOG.md; record $? "--history leaves the branch's own commits out"
expect_output "a pull request that raises the version passes before it lands" "would tag v0.11.0" \
    "$release" --dry-run --history main --pending "$title" include/config.h PROBE
expect_failure "a pull request whose title changed since: refused" "not what the history gives" \
    "$release" --dry-run --history main --pending "feat(pack)!: another title (#9)" include/config.h PROBE
expect_failure "with --history HEAD, the branch's commits are counted: refused" "not what the history gives" \
    "$release" --dry-run --history HEAD --pending "$title" include/config.h PROBE
git update-ref refs/remotes/origin/main main
"$changelog" --tag v0.11.0 --pending "$title" --output "$work/defaulted.md"
cmp -s CHANGELOG.md "$work/defaulted.md"; record $? "with --pending, changelog.sh reads origin/main by default"
expect_output "with --pending, release.sh reads origin/main by default" "would tag v0.11.0" \
    "$release" --dry-run --pending "$title" include/config.h PROBE
git switch -q main && git add -A && commit 2026-02-05 "$title"
expect_output "its squash merge then releases" "would tag v0.11.0" "$release" --dry-run include/config.h PROBE
grep -q '^### Breaking$' "$work/out" && grep -q 'A new section (#9)' "$work/out"; record $? "its notes put the breaking change first"
expect_failure "changelog.sh refuses an unknown --history" "no such commit" "$changelog" --history no-such-branch
[ "$(git worktree list | wc -l)" -eq 1 ]; record $? "no temporary worktree is left behind"

sed -i '/define PROBE_VERSION_PATCH/d' include/config.h
expect_failure "a config.h without a patch number: refused" "no numeric PROBE_VERSION_PATCH" "$release" --dry-run include/config.h PROBE
expect_failure "a missing config.h: usage error" "no such file" "$release" --dry-run include/absent.h PROBE

if [ "$failures" -eq 0 ]; then
    echo "ALL PASS ($checks checks)"
else
    echo "$failures of $checks checks FAILED"
    exit 1
fi
