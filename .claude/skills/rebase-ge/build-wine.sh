#!/bin/bash
# Builds, in the podman image je-wine-build, from the patched tree wine-prep.sh left in wine/: ntdll and wineserver,
# 64- and 32-bit, Wine's ntdll and kernel32 conformance tests (with the tests our patches add), Proton-JE's
# probes and the ones in probes/. A compile error in our patches shows here instead of two hours into the CI build.
#
# usage: build-wine.sh <work dir> [<stock GE-Proton tool dir>]
#
# Puts the test programs in <work dir>/tests. With a stock GE-Proton tool dir (an extracted release, on the same
# file system as <work dir>), also makes <work dir>/swapped: that release with our ntdll and wineserver, hard-linked
# so the stock copy is never written to.

set -euo pipefail

work=${1:?usage: build-wine.sh <work dir> [<stock GE-Proton tool dir>]}
stock=${2:-}
here=$(cd "$(dirname "$0")" && pwd)
top=$(git -C "$here" rev-parse --show-toplevel)
mkdir -p "$work"
work=$(cd "$work" && pwd)
wb=$work/wb

podman image exists je-wine-build || podman build -q -t je-wine-build -f "$here/Containerfile" "$here"

rm -rf "$wb" "$work/tests"
mkdir -p "$wb/src" "$wb/b64" "$wb/b32" "$wb/probes" "$work/tests"
tar -C "$top/wine" --exclude=.git -cf - . | tar -C "$wb/src" -xf -

# Proton-JE's probes: from a checkout of jegglest/proton-je next to this one, else from GitHub.
probes="cs_leave_bad_semaphore inproc_cache_probe killed_thread_stacks mutex_abandon raced_wake_probe"
for p in $probes; do
    if [ -f ~/repos/proton-je/docs-je/repro/$p.c ]; then
        cp ~/repos/proton-je/docs-je/repro/$p.c "$wb/probes/"
    else
        curl -fsSL -o "$wb/probes/$p.c" "https://raw.githubusercontent.com/jegglest/proton-je/je-11.0/docs-je/repro/$p.c"
    fi
done
# Proton-JE-GE's own probes, in probes/ next to this script.
cp "$here"/probes/*.c "$wb/probes/"

cat > "$wb/build.sh" <<'EOF'
set -e
cd /w/src
tools/make_requests >/dev/null
tools/make_specfiles >/dev/null 2>&1 || true
(cd dlls/winevulkan && XDG_CACHE_HOME=/tmp/x ./make_vulkan >/dev/null 2>&1) || { echo "make_vulkan failed"; exit 1; }
autoreconf -if >/dev/null 2>&1
W="--without-x --without-freetype --without-wayland --without-vulkan --without-gnutls \
    --without-gstreamer --without-pulse --without-alsa --without-dbus --without-sdl --without-usb --without-v4l2 \
    --without-cups --without-fontconfig --without-krb5 --without-netapi --without-opencl --without-pcap \
    --without-sane --without-udev --without-unwind --without-gphoto --without-capi --without-inotify \
    --without-oss --without-pcsclite --without-ffmpeg --disable-werror"
cd /w/b64 && /w/src/configure --enable-win64 $W > configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j$(nproc) __tooldeps__ > tooldeps.log 2>&1 || { tail -30 tooldeps.log; exit 1; }
make -j$(nproc) server/wineserver dlls/ntdll/ntdll.so dlls/ntdll/x86_64-windows/ntdll.dll \
    dlls/ntdll/tests/x86_64-windows/ntdll_test.exe dlls/kernel32/tests/x86_64-windows/kernel32_test.exe \
    > make.log 2>&1 || { grep -E 'error|Error' make.log | head -30; exit 1; }
echo "build-wine: 64-bit OK, $(grep -cE 'warning:' make.log || true) warnings"
cd /w/b32 && CC='gcc -m32' /w/src/configure --with-wine64=/w/b64 $W > configure.log 2>&1 || { tail -20 configure.log; exit 1; }
make -j$(nproc) __tooldeps__ > tooldeps.log 2>&1 || { tail -30 tooldeps.log; exit 1; }
make -j$(nproc) dlls/ntdll/ntdll.so dlls/ntdll/i386-windows/ntdll.dll \
    dlls/ntdll/tests/i386-windows/ntdll_test.exe dlls/kernel32/tests/i386-windows/kernel32_test.exe \
    > make.log 2>&1 || { grep -E 'error|Error' make.log | head -30; exit 1; }
echo "build-wine: 32-bit OK, $(grep -cE 'warning:' make.log || true) warnings"
cd /w/probes
for c in *.c; do
    x86_64-w64-mingw32-gcc -O2 -D__USE_MINGW_ANSI_STDIO=1 -o "${c%.c}.exe" "$c" -lpsapi
    i686-w64-mingw32-gcc -O2 -D__USE_MINGW_ANSI_STDIO=1 -o "${c%.c}32.exe" "$c" -lpsapi
done
echo "build-wine: probes OK"
EOF
podman run --rm -v "$wb":/w:Z je-wine-build bash /w/build.sh

cp "$wb"/probes/*.exe "$work/tests/"
cp "$wb/b64/dlls/ntdll/tests/x86_64-windows/ntdll_test.exe" "$work/tests/ntdll_test.exe"
cp "$wb/b32/dlls/ntdll/tests/i386-windows/ntdll_test.exe" "$work/tests/ntdll_test32.exe"
cp "$wb/b64/dlls/kernel32/tests/x86_64-windows/kernel32_test.exe" "$work/tests/kernel32_test.exe"
cp "$wb/b32/dlls/kernel32/tests/i386-windows/kernel32_test.exe" "$work/tests/kernel32_test32.exe"
echo "build-wine: test programs in $work/tests"

if [ -n "$stock" ]; then
    stock=$(cd "$stock" && pwd)
    rm -rf "$work/swapped"
    cp -al "$stock" "$work/swapped"
    # Replace each file with a new one (copy, then rename): writing into a hard link would change the stock copy.
    for f in bin/wineserver:b64/server/wineserver \
             lib/wine/x86_64-unix/ntdll.so:b64/dlls/ntdll/ntdll.so \
             lib/wine/x86_64-windows/ntdll.dll:b64/dlls/ntdll/x86_64-windows/ntdll.dll \
             lib/wine/i386-unix/ntdll.so:b32/dlls/ntdll/ntdll.so \
             lib/wine/i386-windows/ntdll.dll:b32/dlls/ntdll/i386-windows/ntdll.dll; do
        dst=$work/swapped/files/${f%%:*}
        [ -e "$dst" ] || { echo "build-wine: $dst is not in the stock release" >&2; exit 1; }
        cp "$wb/${f#*:}" "$dst.new" && chmod 755 "$dst.new" && mv -f "$dst.new" "$dst"
    done
    echo "build-wine: $work/swapped = $(basename "$stock") with our ntdll and wineserver"
fi
