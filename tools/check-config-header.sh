#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: check-config-header.sh [--write] <copy of config.h> <PREFIX> [template]

Compares the shared part of a repository's config.h with the Laplace template, after
putting the template's LAPLACE_TEMPLATE_ prefix back in place of <PREFIX>_. The shared
part runs from the line that defines <PREFIX>_CONFIG_TEMPLATE to the line before the
Requirements group. Everything outside it (the licence block, the identity, the
requirements) belongs to the repository and is not compared.

  <copy>      the repository's config.h, for example kernel/include/kernel/config.h
  <PREFIX>    its macro prefix, for example KERNEL or LPLPLUGIN
  [template]  defaults to templates/config.h next to this script
  --write     replace the copy's shared part with the template's, under <PREFIX>_, instead of comparing

A new copy starts as the template itself, renamed:
  sed -E 's/\bLAPLACE_TEMPLATE_/<PREFIX>_/g; s/LaplaceTemplate/<Name>/g' templates/config.h > <copy>

Exit status: 0 when the shared parts match, 1 when they differ (the diff is printed),
2 on a usage error or a file without the markers.
EOF
}

shared_part() {
    awk '
        /^#define [A-Z0-9_]+_CONFIG_TEMPLATE [0-9]+$/ { inside = 1; print previous }
        /^\/\*\* @name Requirements/ { inside = 0 }
        inside { print }
        { previous = $0 }' "$1"
}

write=0
[ "${1:-}" = "--write" ] && { write=1; shift; }
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }
[ $# -ge 2 ] && [ $# -le 3 ] || { usage >&2; exit 2; }
copy="$1"
prefix="$2"
template="${3:-$(cd "$(dirname "$0")/.." && pwd)/templates/config.h}"

for file in "$copy" "$template"; do
    [ -f "$file" ] || { echo "$file: no such file" >&2; exit 2; }
    if [ -z "$(shared_part "$file")" ]; then
        echo "$file: no shared part (no #define <PREFIX>_CONFIG_TEMPLATE <n> line)" >&2
        exit 2
    fi
done

if [ "$write" -eq 1 ]; then
    first="$(awk '/^#define [A-Z0-9_]+_CONFIG_TEMPLATE [0-9]+$/ { print NR - 1; exit }' "$copy")"
    after="$(awk '/^\/\*\* @name Requirements/ { print NR; exit }' "$copy")"
    [ -n "$after" ] || { echo "$copy: no Requirements group after the shared part" >&2; exit 2; }
    rewritten="$(mktemp)"
    {
        head -n "$((first - 1))" "$copy"
        shared_part "$template" | sed -E "s/\\bLAPLACE_TEMPLATE_/${prefix}_/g"
        tail -n "+$after" "$copy"
    } > "$rewritten"
    mv "$rewritten" "$copy"
    echo "$copy: shared part rewritten from the template"
    exit 0
fi

if diff -u --label "template" --label "$copy (prefix ${prefix}_ read back as LAPLACE_TEMPLATE_)" \
    <(shared_part "$template") \
    <(shared_part "$copy" | sed -E "s/\\b${prefix}_/LAPLACE_TEMPLATE_/g"); then
    echo "$copy: the shared part matches the template"
else
    echo "$copy: the shared part has drifted from the template; copy it again from templates/config.h" >&2
    exit 1
fi
