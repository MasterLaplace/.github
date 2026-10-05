#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: release.sh [--dry-run] [--history <rev>] [--pending <title>] <config.h> <PREFIX>

Releases a Laplace repository when the version in its config.h is later than its last
vX.Y.Z tag. Run it from the root of a clone that has its tags, on the commit to release.

  <config.h>         the repository's copy of templates/config.h
  <PREFIX>           its macro prefix, for example KERNEL or LPLPLUGIN
  --dry-run          print the decision and the release notes, create nothing
  --history <rev>    the commit whose history the changelog is checked against, HEAD by
                     default; for a pull request, the tip of the branch it merges into
  --pending <title>  check the changelog as it will be once a commit titled <title> lands
                     on top of that history: for a pull request, its title followed by
                     " (#<number>)", which is what a squash merge writes

The version in <config.h>, compared with the last tag:
  the same          nothing to release
  earlier           refused: a version never goes back
  later, or no tag  CITATION.cff must give that version and a date-released, and
                    CHANGELOG.md must have a section for it dated the same day and be what
                    tools/changelog.sh --tag vX.Y.Z gives, that date apart; then the commit
                    is tagged vX.Y.Z and the GitHub release published with gh, its notes
                    being that section

Writes version=X.Y.Z and released=true or false to $GITHUB_OUTPUT when it is set.
Exit status: 0 when released or when there is nothing to release, 1 when refused,
2 on a usage error.
EOF
}

here="$(cd "$(dirname "$0")/.." && pwd)"

dry_run=0
history=HEAD
pending=""
arguments=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --dry-run) dry_run=1; shift ;;
        --history | --pending)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            if [ "$1" = "--history" ]; then history="$2"; else pending="$2"; fi
            shift 2
            ;;
        -*) usage >&2; exit 2 ;;
        *) arguments+=("$1"); shift ;;
    esac
done
[ "${#arguments[@]}" -eq 2 ] || { usage >&2; exit 2; }
config="${arguments[0]}"
prefix="${arguments[1]}"
[ -f "$config" ] || { echo "$config: no such file" >&2; exit 2; }

refuse() {
    echo "release refused: $*" >&2
    exit 1
}

report() {
    [ -n "${GITHUB_OUTPUT:-}" ] || return 0
    printf 'version=%s\nreleased=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

read_define() {
    sed -nE "s/^[[:space:]]*#[[:space:]]*define[[:space:]]+${prefix}_$1[[:space:]]+(.*[^[:space:]])[[:space:]]*$/\\1/p" "$config" | head -n 1
}

read_field() {
    sed -nE "s/^$1:[[:space:]]*\"?([^\"]*[^\"[:space:]])\"?[[:space:]]*$/\\1/p" CITATION.cff | head -n 1
}

version=""
for part in MAJOR MINOR PATCH; do
    number="$(read_define "VERSION_$part")"
    [[ $number =~ ^[0-9]+$ ]] || refuse "$config has no numeric ${prefix}_VERSION_$part"
    version="${version:+$version.}$number"
done
name="$(read_define NAME | sed -E 's/^"(.*)"$/\1/')"
[ -n "$name" ] || refuse "$config has no ${prefix}_NAME"

last_tag="$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
if [ -n "$last_tag" ]; then
    if [ "$version" = "${last_tag#v}" ]; then
        echo "$name $version is already released as $last_tag: nothing to release"
        report "$version" false
        exit 0
    fi
    if [ "$(printf '%s\n%s\n' "${last_tag#v}" "$version" | sort -V | tail -n 1)" != "$version" ]; then
        refuse "$config says $version, earlier than the last release $last_tag: a version never goes back"
    fi
fi

regenerate="tools/changelog.sh --tag v$version --pending \"${pending:-<pull request title> (#<number>)}\" --output CHANGELOG.md, from MasterLaplace/.github"

[ -f CITATION.cff ] || refuse "no CITATION.cff at the root of the repository"
cited_version="$(read_field version)"
cited_date="$(read_field date-released)"
[ "$cited_version" = "$version" ] || refuse "CITATION.cff gives version ${cited_version:-(none)}, $config says $version"
[[ $cited_date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || refuse "CITATION.cff has no date-released: YYYY-MM-DD"

[ -f CHANGELOG.md ] || refuse "no CHANGELOG.md at the root of the repository: write it with $regenerate"
heading="$(grep -m 1 -E "^## \[${version//./\\.}\] - " CHANGELOG.md || true)"
[ -n "$heading" ] || refuse "CHANGELOG.md has no section for $version: regenerate it with $regenerate"
[ "${heading##* - }" = "$cited_date" ] || refuse "CHANGELOG.md dates $version ${heading##* - }, CITATION.cff ${cited_date}"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
"$here/tools/changelog.sh" --tag "v$version" --history "$history" ${pending:+--pending "$pending"} \
    --output "$work/expected.md" .
awk -v version="## [$version] - " -v heading="$heading" \
    'index($0, version) == 1 { print heading; next } { print }' "$work/expected.md" > "$work/expected-dated.md"
if ! diff -u --label "what the history gives, dated $cited_date" --label CHANGELOG.md \
    "$work/expected-dated.md" CHANGELOG.md > "$work/difference"; then
    head -n 60 "$work/difference" >&2
    refuse "CHANGELOG.md is not what the history gives: regenerate it with $regenerate"
fi

awk -v heading="$heading" '
    $0 == heading { inside = 1; next }
    inside && /^## \[/ { exit }
    inside { print }' CHANGELOG.md | sed '/./,$!d' > "$work/notes.md"

target="$(git rev-parse HEAD)"
if [ "$dry_run" -eq 1 ]; then
    echo "would tag v$version on $target and publish \"$name $version\", with these notes:"
    cat "$work/notes.md"
    report "$version" false
    exit 0
fi

gh release create "v$version" --target "$target" --title "$name $version" --notes-file "$work/notes.md"
echo "$name $version released as v$version on $target"
report "$version" true
