#!/usr/bin/env bash
set -uo pipefail

usage() {
    cat <<'EOF'
Usage: test-compare-images.sh

Tests tools/compare-images.py and tools/publish-images.sh: the comparison's self-test, a draw
from two commits of a scratch repository, and the images branch against a local bare repository
(a folder published, replaced by a newer run, removed, and a folder name that would escape
refused). Prints one PASS or FAIL line per check, then ALL PASS or the number of failures.
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

here="$(cd "$(dirname "$0")/.." && pwd)"
compare="$here/tools/compare-images.py"
publish="$here/tools/publish-images.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
failures=0
checks=0

record() {
    checks=$((checks + 1))
    if [ "$1" -eq 0 ]; then echo "PASS  $2"; else echo "FAIL  $2"; failures=$((failures + 1)); fi
}

python3 -I "$compare" --self-test >"$work/self-test" 2>&1
record $? "the comparison's self-test"

git init --quiet "$work/drawn"
cd "$work/drawn" || exit 1
git config user.name test && git config user.email test@example.invalid
printf '0\n' >shade
git add shade && git commit --quiet -m first
printf '40\n' >shade
git commit --quiet -am second
draw='python3 -c "import os; s = int(open(\"shade\").read()); d = os.environ[\"IMAGES_DIR\"]; open(d + \"/square.ppm\", \"wb\").write(b\"P6\n2 2\n255\n\" + bytes((100 + s, 100, 100)) * 4); open(d + \"/side.ppm\", \"wb\").write(b\"P6\n1 1\n255\n\" + bytes(3))"'
python3 -I "$compare" --draw "$draw" --before HEAD~1 --after HEAD --out "$work/out" >"$work/table" 2>&1
status=$?
[ "$status" -eq 1 ] && grep -q '| square | changed |' "$work/table" && grep -q 'Same on both sides: side.' "$work/table"
record $? "a draw from two commits finds the image that changed, and the one that did not"
[ -f "$work/out/images/square-diff.png" ] && [ -f "$work/out/index.html" ] && [ -f "$work/out/result.json" ]
record $? "and writes its diff, the page and the result"
[ "$(git worktree list | wc -l)" -eq 1 ]
record $? "and leaves no worktree behind"
python3 -I "$compare" --draw "exit 3" --before HEAD~1 --out "$work/failed" >/dev/null 2>&1
[ $? -eq 2 ]
record $? "a side that cannot be drawn exits with 2"

git init --quiet --bare "$work/remote.git"
git clone --quiet "$work/remote.git" "$work/clone" 2>/dev/null
cd "$work/clone" || exit 1
mkdir -p "$work/first/run-1" "$work/second/run-2"
printf 'one' >"$work/first/run-1/a.png"
printf 'two' >"$work/second/run-2/a.png"
listing() { git fetch --quiet origin images && git ls-tree -r --name-only FETCH_HEAD | tr '\n' ' '; }
"$publish" origin images frames/pr-1 "$work/first" >/dev/null 2>&1
[ "$(listing)" = "frames/pr-1/run-1/a.png " ]
record $? "a folder is published"
"$publish" origin images frames/pr-2 "$work/second" >/dev/null 2>&1
"$publish" origin images frames/pr-1 "$work/second" >/dev/null 2>&1
[ "$(listing)" = "frames/pr-1/run-2/a.png frames/pr-2/run-2/a.png " ]
record $? "a newer run replaces its pull request's folder, and leaves the others"
[ "$(git log --format=%P -1 FETCH_HEAD)" = "" ]
record $? "the branch is one commit, with no history of old images"
"$publish" origin images frames/pr-1 --remove >/dev/null 2>&1
[ "$(listing)" = "frames/pr-2/run-2/a.png " ]
record $? "a folder is removed"
"$publish" origin images ../escape "$work/first" >/dev/null 2>&1
[ $? -eq 2 ]
record $? "a folder that would escape the branch is refused"

if [ "$failures" -eq 0 ]; then echo "ALL PASS ($checks checks)"; else echo "$failures of $checks FAILED"; fi
[ "$failures" -eq 0 ]
