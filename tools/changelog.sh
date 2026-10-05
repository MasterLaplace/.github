#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: changelog.sh [--tag vX.Y.Z] [--pending <title>] [--history <rev>] [--output FILE] [repository]

Prints the CHANGELOG.md of a Laplace repository, generated from the commit titles of its
history by git-cliff with the shared templates/cliff.toml.

  [repository]       a clone of the repository, the current directory by default
  --tag vX.Y.Z       file the commits since the last release under vX.Y.Z, dated today
  --pending <title>  as if a commit titled <title> had landed on top of the history: the
                     pull request that raises the version passes its own title followed by
                     " (#<number>)", which is what its squash merge will write
  --history <rev>    the commit whose history is read, HEAD by default
  --output FILE      write FILE instead of printing

So the pull request #42 titled "feat(pack)!: a new section" that raises the version to
1.0.0 writes its changelog with:
  changelog.sh --tag v1.0.0 --pending "feat(pack)!: a new section (#42)" --output CHANGELOG.md

git-cliff is the version pinned in tools/git-cliff.requirements.txt: the program named by
$GIT_CLIFF when it is set, git-cliff from PATH when it is that version, else uvx runs it.

Exit status: 0 on success, 1 when git-cliff fails, 2 on a usage error or when git-cliff
cannot be found.
EOF
}

here="$(cd "$(dirname "$0")/.." && pwd)"
config="$here/templates/cliff.toml"
pinned="$(sed -nE 's/^git-cliff==([0-9.]+).*/\1/p' "$here/tools/git-cliff.requirements.txt")"

tag=""
pending=""
history=HEAD
output=""
repository="."
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --tag | --pending | --history | --output)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            case "$1" in
                --tag) tag="$2" ;;
                --pending) pending="$2" ;;
                --history) history="$2" ;;
                --output) output="$2" ;;
            esac
            shift 2
            ;;
        -*) usage >&2; exit 2 ;;
        *) repository="$1"; shift ;;
    esac
done
if [ -n "$tag" ] && [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "--tag $tag: expected vX.Y.Z" >&2
    exit 2
fi
[ -d "$repository" ] || { echo "$repository: no such directory" >&2; exit 2; }
git -C "$repository" rev-parse -q --verify "$history^{commit}" > /dev/null \
    || { echo "--history $history: no such commit in $repository" >&2; exit 2; }

if [ -n "${GIT_CLIFF:-}" ]; then
    cliff=("$GIT_CLIFF")
elif command -v git-cliff > /dev/null && [ "$(git-cliff --version)" = "git-cliff $pinned" ]; then
    cliff=(git-cliff)
elif command -v uvx > /dev/null; then
    cliff=(uvx --quiet "git-cliff@$pinned")
else
    echo "git-cliff $pinned not found: pip install git-cliff==$pinned, or install uv" >&2
    exit 2
fi

work="$(mktemp -d)"
cleanup() {
    git -C "$repository" worktree remove --force "$work/history" 2> /dev/null || true
    rm -rf -- "$work"
}
trap cleanup EXIT

source="$repository"
if [ -n "$pending" ] || [ "$(git -C "$repository" rev-parse "$history")" != "$(git -C "$repository" rev-parse HEAD)" ]; then
    git -C "$repository" worktree add -q --detach "$work/history" "$history"
    if [ -n "$pending" ]; then
        git -C "$work/history" -c user.name=changelog -c user.email=changelog@example.invalid \
            -c commit.gpgsign=false commit -q --allow-empty -m "$pending"
    fi
    source="$work/history"
fi

if ! changelog="$(cd "$source" && "${cliff[@]}" --config "$config" ${tag:+--tag "$tag"} 2> "$work/log")"; then
    cat "$work/log" >&2
    exit 1
fi

if [ -n "$output" ]; then
    printf '%s\n' "$changelog" > "$output"
else
    printf '%s\n' "$changelog"
fi
