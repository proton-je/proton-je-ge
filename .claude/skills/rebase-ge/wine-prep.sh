#!/bin/bash
# Runs GE's Wine patching, the "(2) WINE PATCHING" part of patches/protonprep-valve-staging.sh, on this checkout's
# wine submodule in the podman image je-wine-build, then .github/check-proton-je-patches.sh: the Patch and the
# "Check the Proton-JE patches" steps of the CI build, in minutes and before anything is pushed.
#
# usage: wine-prep.sh [--ge-only] <work dir>
#   --ge-only  leave the PROTON-JE PATCHES section out and skip the check: GE's patched tree alone, to commit on a
#              scratch branch when one of our patches has to be refreshed
#
# The wine and wine-staging submodules are first reset to the commits this branch points at (local changes and
# untracked files in them are lost). The patched tree stays in wine/ for build-wine.sh; the log is
# <work dir>/wine-patching.log.

set -euo pipefail

ge_only=0
if [ "${1:-}" = --ge-only ]; then ge_only=1; shift; fi
work=${1:?usage: wine-prep.sh [--ge-only] <work dir>}
here=$(cd "$(dirname "$0")" && pwd)
top=$(git -C "$here" rev-parse --show-toplevel)
script=$top/patches/protonprep-valve-staging.sh
mkdir -p "$work"
work=$(cd "$work" && pwd)

podman image exists je-wine-build || podman build -q -t je-wine-build -f "$here/Containerfile" "$here"

# The patching resets the wine tree to its HEAD, so HEAD has to be the commit the branch points at.
for m in wine wine-staging; do
    sha=$(git -C "$top" ls-tree HEAD "$m" | awk '{print $3}')
    git -C "$top/$m" cat-file -e "$sha^{commit}" 2>/dev/null || git -C "$top/$m" fetch -q origin "$sha"
    git -C "$top/$m" reset -q --hard
    git -C "$top/$m" clean -qxdf
    git -C "$top/$m" checkout -q --detach "$sha"
done

{
    sed -n '1,/^### (1) PREP SECTION ###$/p' "$script" | sed '$d'
    if [ $ge_only = 1 ]; then
        sed -n '/^### (2) WINE PATCHING ###$/,/^### END WINE PATCHING ###$/p' "$script" |
            sed '/^### PROTON-JE PATCHES ###$/,/^### END PROTON-JE PATCHES ###$/d'
    else
        sed -n '/^### (2) WINE PATCHING ###$/,/^### END WINE PATCHING ###$/p' "$script"
    fi
} > "$work/wine-patching.sh"
if ! grep -q '^### END WINE PATCHING ###$' "$work/wine-patching.sh"; then
    echo "wine-prep: no complete WINE PATCHING section in $script" >&2
    exit 1
fi

echo "wine-prep: GE's Wine patching$([ $ge_only = 1 ] && echo ', without the PROTON-JE PATCHES section'), log in $work/wine-patching.log"
podman run --rm -v "$top":/src:Z -v "$work":/work:Z -w /src je-wine-build bash -c '
    git config --global --add safe.directory "*"
    git config --global user.name wine-prep; git config --global user.email wine-prep@localhost
    bash /work/wine-patching.sh > /work/wine-patching.log 2>&1' || true
echo "wine-prep: $(grep -c '^patching file' "$work/wine-patching.log") files patched in all"

if [ $ge_only = 1 ]; then
    echo "wine-prep: GE's patched tree is in $top/wine"
    exit 0
fi

# What `patch` printed for our section: from its first echo line to GE's autoconf step after it.
first=$(sed -n '/^### PROTON-JE PATCHES ###$/,/^### END PROTON-JE PATCHES ###$/p' "$script" |
    sed -n 's/^[[:space:]]*echo "\(.*\)"[[:space:]]*$/\1/p' | head -1)
awk -v f="$first" 'index($0, f) == 1 { p = 1 } /^WINE: RUN AUTOCONF/ { p = 0 } p' "$work/wine-patching.log" \
    > "$work/proton-je-section.log"
echo "wine-prep: the PROTON-JE PATCHES section:"
sed 's/^/  /' "$work/proton-je-section.log"

status=0
if [ ! -s "$work/proton-je-section.log" ]; then
    echo "wine-prep: the section's output is missing from the log" >&2
    status=1
elif grep -qE 'FAILED|fuzz|Reversed|previously applied|\.rej|malformed|can.t find|garbage' "$work/proton-je-section.log"; then
    echo "wine-prep: a patch of the section did not apply cleanly (offsets alone are fine)" >&2
    status=1
fi
"$top/.github/check-proton-je-patches.sh" || status=1
exit $status
