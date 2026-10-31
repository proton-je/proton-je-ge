#!/bin/bash
# Runs Wine's ntdll:sync, kernel32:sync and kernel32:thread tests and Proton-JE's probes, 64- and 32-bit, with a
# Proton tool's own Wine in a scratch prefix, ntsync on, and prints one line per run.
#
# usage: run-tests.sh <tool dir> <work dir> [<label>]
#   <tool dir>  an extracted GE-Proton or Proton-JE-GE release (the directory with files/ and version)
#   <work dir>  where build-wine.sh put tests/; the prefix goes to <work dir>/pfx-<label>
#
# Expected with our patches: "0 failures" for the three test suites, "0 failed step(s)" for mutex_abandon, "OK" for
# inproc_cache, "0 stale alerts, 0 early returns" for raced_wake, "LeaveCriticalSection() returned" in all three
# cs_leave cases, and a few private allocations at most left by killed_thread_stacks' kill and suspended batches.

set -uo pipefail

T=$(cd "${1:?usage: run-tests.sh <tool dir> <work dir> [<label>]}" && pwd)
work=$(cd "${2:?usage: run-tests.sh <tool dir> <work dir> [<label>]}" && pwd)
L=${3:-$(basename "$T")}
P=$work/tests
[ -x "$T/files/bin/wine" ] || { echo "run-tests: no files/bin/wine in $T" >&2; exit 1; }
[ -f "$P/ntdll_test.exe" ] || { echo "run-tests: no test programs in $P (run build-wine.sh)" >&2; exit 1; }

export WINEPREFIX=$work/pfx-$L
export WINEDLLOVERRIDES="mscoree,mshtml=" WINEDEBUG=-all
export LD_LIBRARY_PATH=$T/files/lib/x86_64-linux-gnu:$T/files/lib/i386-linux-gnu
W=$T/files/bin/wine
WS=$T/files/bin/wineserver

run() {
    local name=$1 out rc
    shift
    out=$(cd "$P" && timeout 600 "$W" "$@" 2>&1)
    rc=$?
    "$WS" -k 2>/dev/null
    "$WS" -w 2>/dev/null
    echo "[$L] $name rc=$rc :: $(echo "$out" |
        grep -E 'tests executed|stale|early|failed|FAIL|abandon|OK|returned|timed out|hang|index|allocations' |
        grep -v 'Test marked todo' | tail -4 | tr '\n' '|')"
}

echo "[$L] $(cat "$T/version")"
rm -rf "$WINEPREFIX"
"$W" wineboot -u >/dev/null 2>&1
"$WS" -w
# The server says whether it runs on ntsync.
"$WS" -k 2>/dev/null
( "$WS" -f -p0 2>&1 | grep -m1 -i ntsync & )
sleep 1
"$W" cmd /c exit >/dev/null 2>&1
"$WS" -k
"$WS" -w

for b in "" 32; do
    run ntdll:sync$b ntdll_test$b.exe sync
    run kernel32:sync$b kernel32_test$b.exe sync
    run kernel32:thread$b kernel32_test$b.exe thread
    run mutex_abandon$b-close mutex_abandon$b.exe close 3
    run mutex_abandon$b-waitall mutex_abandon$b.exe waitall 3
    run inproc_cache$b inproc_cache_probe$b.exe 5000
    run raced_wake$b raced_wake_probe$b.exe 20000
    run cs_leave$b cs_leave_bad_semaphore$b.exe
    run killed_thread_stacks$b killed_thread_stacks$b.exe all 200
done
rm -rf "$WINEPREFIX"
