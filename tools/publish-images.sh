#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/publish-images.sh <remote> <branch> <folder> <images-directory>
       tools/publish-images.sh <remote> <branch> <folder> --remove

Puts the files of <images-directory> under <folder> on <branch> of <remote>, replacing what the
folder held, or removes the folder with --remove. The branch holds a single commit with no
parent, rewritten on every change, so it never keeps a history of old images: a folder removed
is gone from the branch, and its files become unreachable.

Concurrent runs are safe: the push is a force push with a lease on the commit the change was
made from, and a refused push starts over from the branch as it now is, up to five times.

Run from inside a clone of the repository. GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL name the author of
the commit, github-actions[bot] by default.

Exit status: 0 when the branch holds the change, 1 when five tries were refused, 2 on a usage error.
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }
[ $# -eq 4 ] || { usage >&2; exit 2; }
remote="$1" branch="$2" folder="$3" source="$4"
case "$folder" in "" | /* | *..*) echo "publish-images: refusing the folder '$folder'" >&2; exit 2 ;; esac
[ "$source" = --remove ] || [ -d "$source" ] || { echo "publish-images: no directory $source" >&2; exit 2; }

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-github-actions[bot]}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export GIT_INDEX_FILE="$work/index"

for attempt in 1 2 3 4 5; do
    rm -f "$GIT_INDEX_FILE"
    if base="$(git ls-remote --exit-code "$remote" "refs/heads/$branch" | cut -f1)"; then
        git fetch --quiet --no-tags "$remote" "$base"
        git read-tree "$base"
        git rm -r --cached --quiet --ignore-unmatch -- "$folder"
    else
        base=""
        git read-tree --empty
    fi
    if [ "$source" != --remove ]; then
        while IFS= read -r -d '' file; do
            relative="${file#"$source"/}"
            blob="$(git hash-object -w -- "$file")"
            git update-index --add --cacheinfo "100644,$blob,$folder/$relative"
        done < <(find "$source" -type f -print0)
    fi
    tree="$(git write-tree)"
    if [ -n "$base" ] && [ "$tree" = "$(git rev-parse "$base^{tree}")" ]; then
        echo "publish-images: $branch already holds this"
        exit 0
    fi
    commit="$(echo "Images of the open pull requests" | git commit-tree "$tree")"
    if git push --quiet --force-with-lease="refs/heads/$branch:$base" "$remote" "$commit:refs/heads/$branch"; then
        echo "publish-images: $branch is $commit"
        exit 0
    fi
    echo "publish-images: try $attempt refused, starting over" >&2
    sleep $((attempt * 2))
done
echo "publish-images: $branch was not updated after five tries" >&2
exit 1
