#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install-git-cliff.sh <directory>

Installs the git-cliff pinned in tools/git-cliff.requirements.txt, checked against its
hashes, in a Python virtual environment created at <directory>, then prints the path of
the program, for $GIT_CLIFF. CI installs it this way; on a workstation, changelog.sh
finds git-cliff through uvx without installing anything.
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }
[ $# -eq 1 ] || { usage >&2; exit 2; }

here="$(cd "$(dirname "$0")/.." && pwd)"
python3 -m venv "$1"
"$1/bin/pip" install --quiet --no-deps --require-hashes -r "$here/tools/git-cliff.requirements.txt" >&2
echo "$1/bin/git-cliff"
