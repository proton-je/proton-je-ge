#!/bin/bash
# Checks, after patches/protonprep-valve-staging.sh has run, that every patch of its PROTON-JE PATCHES
# section is in the wine tree exactly as written. The script applies patches with `patch -Np1`, which goes on
# with fuzz and keeps going after a failure, and CI runs it with `|| true`; this check fails the build instead.
#
# Method, on a scratch copy of the files the patches touch (the wine tree is never modified): take the
# patches off in reverse order with `git apply -R`, then put them back in order with `git apply`. Both refuse
# fuzz, so a patch that is missing, partly applied, or applied with fuzz fails here. The copy must end up
# byte for byte like the tree.

set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
script="$top/patches/protonprep-valve-staging.sh"
wine="$top/wine"

mapfile -t patches < <(sed -n '/^### PROTON-JE PATCHES ###$/,/^### END PROTON-JE PATCHES ###$/p' "$script" |
    sed -n 's|^[[:space:]]*apply_patch "\.\./\(patches/[^"]*\)".*|\1|p')
if [ ${#patches[@]} -eq 0 ]; then
    echo "check-proton-je-patches: no apply_patch lines in the PROTON-JE PATCHES section of $script" >&2
    exit 1
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mapfile -t files < <(for p in "${patches[@]}"; do git apply --numstat "$top/$p" | cut -f3; done | sort -u)
for f in "${files[@]}"; do
    if [ -e "$wine/$f" ]; then
        mkdir -p "$scratch/copy/$(dirname "$f")"
        cp -p "$wine/$f" "$scratch/copy/$f"
    fi
done

cd "$scratch/copy"
for (( i = ${#patches[@]} - 1; i >= 0; i-- )); do
    if ! git apply -R --whitespace=nowarn "$top/${patches[$i]}"; then
        echo "check-proton-je-patches: ${patches[$i]} is not applied exactly (missing, partial or fuzzed)" >&2
        exit 1
    fi
done
for p in "${patches[@]}"; do
    if ! git apply --whitespace=nowarn "$top/$p"; then
        echo "check-proton-je-patches: $p does not apply to the tree without the later patches" >&2
        exit 1
    fi
done
for f in "${files[@]}"; do
    if ! cmp -s "$wine/$f" "$scratch/copy/$f"; then
        echo "check-proton-je-patches: $f differs from the tree after taking the patches off and on again" >&2
        exit 1
    fi
done

echo "check-proton-je-patches: all ${#patches[@]} patches applied exactly:"
printf '  %s\n' "${patches[@]}"
