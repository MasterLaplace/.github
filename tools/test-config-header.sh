#!/usr/bin/env bash
set -uo pipefail

usage() {
    cat <<'EOF'
Usage: test-config-header.sh

Tests templates/config.h and tools/check-config-header.sh: the template compiles with
every compiler found (C11 and C++, hosted and freestanding, i686-elf when $CROSS_BIN or
PATH has it), a requirement refuses a version too old or of another major, and the check
passes a faithful copy, fails a drifted one, and --write repairs it.
Prints one PASS or FAIL line per check, then ALL PASS or the number of failures.
EOF
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { usage; exit 0; }

here="$(cd "$(dirname "$0")/.." && pwd)"
template="$here/templates/config.h"
check="$here/tools/check-config-header.sh"
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

make_copy() {
    mkdir -p "$work/$1/include/$2"
    sed -E "s/\\bLAPLACE_TEMPLATE_/$3_/g; s/LaplaceTemplate/$1/g" "$template" > "$work/$1/include/$2/config.h"
}

set_version() {
    sed -i -E "s/(define $1_VERSION_MAJOR) [0-9]+/\\1 $2/; s/(define $1_VERSION_MINOR) [0-9]+/\\1 $3/; s/(define $1_VERSION_PATCH) [0-9]+/\\1 $4/" "$5"
}

printf '#include "%s"\n#if !LAPLACE_TEMPLATE_PREREQ_VERSION(0, 1, 0) || LAPLACE_TEMPLATE_PREREQ_VERSION(0, 1, 1)\n#error "version arithmetic"\n#endif\nconst char *config = LAPLACE_TEMPLATE_CONFIG_STRING;\n' "$template" > "$work/probe.c"
cp "$work/probe.c" "$work/probe.cpp"

for compiler in gcc clang; do
    command -v "$compiler" > /dev/null || continue
    expect_success "$compiler, C11 hosted" "$compiler" -std=c11 -Wall -Wextra -Werror -c "$work/probe.c" -o /dev/null
    expect_success "$compiler, C11 freestanding" "$compiler" -std=c11 -ffreestanding -Wall -Wextra -Werror -c "$work/probe.c" -o /dev/null
done
for compiler in g++ clang++; do
    command -v "$compiler" > /dev/null || continue
    for standard in c++17 c++23; do
        expect_success "$compiler, $standard" "$compiler" -std="$standard" -Wall -Wextra -Werror -c "$work/probe.cpp" -o /dev/null
    done
done
cross="${CROSS_BIN:-}"
for candidate in "$cross/i686-elf-gcc" "$(command -v i686-elf-gcc 2>/dev/null)"; do
    [ -x "$candidate" ] || continue
    expect_success "i686-elf-gcc, C11 kernel target" "$candidate" -std=gnu11 -ffreestanding -D__is_kernel -Wall -Wextra -Werror -c "$work/probe.c" -o /dev/null
    "$candidate" -std=gnu11 -ffreestanding -D__is_kernel -E -dM "$work/probe.c" > "$work/macros"
    grep -q 'LAPLACE_TEMPLATE_SYSTEM_STRING "Laplace Kernel"' "$work/macros"; record $? "i686-elf-gcc sees the Laplace Kernel as the system"
    break
done
gcc -std=c11 -DLPL_TARGET_KERNEL=1 -E -dM "$work/probe.c" > "$work/macros"
grep -q 'LAPLACE_TEMPLATE_SYSTEM_STRING "Laplace Kernel"' "$work/macros"; record $? "LPL_TARGET_KERNEL=1 selects the Laplace Kernel, whatever the compiler"

for real in KERNEL:LplKernel LPLPLUGIN:LplPlugin LPLKNOWLEDGE:LplKnowledge LPLASSISTANT:LplAssistant; do
    make_copy "${real#*:}" "${real#*:}" "${real%%:*}"
    expect_success "a copy under the real prefix ${real%%:*}_ passes the check" "$check" "$work/${real#*:}/include/${real#*:}/config.h" "${real%%:*}"
done

make_copy Alpha alpha ALPHA
make_copy Beta beta BETA
python3 - "$work/Beta/include/beta/config.h" <<'EOF'
import sys
path = sys.argv[1]
text = open(path).read()
anchor = "/** @name Requirements: what this repository needs, checked by the compiler whatever the build system @{ */\n"
requirement = """#include <alpha/config.h>
#if !ALPHA_COMPATIBLE_WITH(0, 3, 0)
    #pragma message("found Alpha " ALPHA_VERSION_STRING)
    #if ALPHA_VERSION_MAJOR != 0
        #error "Beta was written for Alpha 0.x"
    #else
        #error "Beta needs Alpha 0.3.0 or later"
    #endif
#endif
"""
assert anchor in text
open(path, "w").write(text.replace(anchor, anchor + requirement))
EOF
printf '#include <beta/config.h>\n' > "$work/beta.c"
beta_build() { gcc -std=c11 -I"$work/Alpha/include" -I"$work/Beta/include" -c "$work/beta.c" -o /dev/null; }
alpha_header="$work/Alpha/include/alpha/config.h"

set_version ALPHA 0 2 0 "$alpha_header"
expect_failure "a requirement refuses a version too old" "Beta needs Alpha 0.3.0 or later" beta_build
grep -q 'found Alpha 0.2.0' "$work/out"; record $? "the refusal prints the version it found"
set_version ALPHA 0 3 0 "$alpha_header"
expect_success "a requirement accepts the version it names" beta_build
set_version ALPHA 0 4 7 "$alpha_header"
expect_success "a requirement accepts a later version of the same major" beta_build
set_version ALPHA 1 0 0 "$alpha_header"
expect_failure "a requirement refuses another major" "Beta was written for Alpha 0.x" beta_build

expect_success "the check passes a faithful copy" "$check" "$alpha_header" ALPHA
cp "$alpha_header" "$work/alpha.before"
"$check" --write "$alpha_header" ALPHA > /dev/null
cmp -s "$work/alpha.before" "$alpha_header"; record $? "--write leaves a faithful copy byte for byte"
set_version ALPHA 2 5 1 "$alpha_header"
expect_success "the identity block is the copy's own" "$check" "$alpha_header" ALPHA
sed -i 's/#define LPL_UNUSED(x) (void)(x)/#define LPL_UNUSED(x) ((void)(x))/' "$alpha_header"
expect_failure "the check fails a drifted copy" "has drifted" "$check" "$alpha_header" ALPHA
grep -q '^+#define LPL_UNUSED(x) ((void)(x))' "$work/out"; record $? "the failure shows the drifted line"
expect_success "--write repairs the shared part" "$check" --write "$alpha_header" ALPHA
expect_success "the repaired copy passes" "$check" "$alpha_header" ALPHA
grep -q '#define ALPHA_VERSION_MAJOR 2' "$alpha_header"; record $? "--write keeps the copy's identity"
grep -q 'Beta needs Alpha' "$work/Beta/include/beta/config.h"
"$check" --write "$work/Beta/include/beta/config.h" BETA > /dev/null
grep -q 'Beta needs Alpha 0.3.0 or later' "$work/Beta/include/beta/config.h"; record $? "--write keeps the copy's requirements"

if [ "$failures" -eq 0 ]; then
    echo "ALL PASS (0 failures, $checks checks)"
else
    echo "$failures failure(s) out of $checks checks"
    exit 1
fi
