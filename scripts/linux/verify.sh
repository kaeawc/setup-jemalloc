#!/bin/bash
#
# Verify that a given PID has jemalloc preloaded (Linux). Prints diagnostics and
# exits non-zero if jemalloc is not preloaded. Intended for CI checks and manual
# debugging. This is a read-only verifier — it does not signal the target.
#
# It relies only on /proc (universal on Linux), so it works in minimal distro
# containers without ps or lsof installed. lsof, if present, is used only for
# extra diagnostics.

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <pid>"
  exit 1
fi
PID="$1"

if [ -z "${LD_PRELOAD:-}" ]; then
  echo "LD_PRELOAD is not set — required on Linux to preload jemalloc" >&2
  exit 1
fi
echo "LD_PRELOAD is set to $LD_PRELOAD"

if [ ! -d "/proc/$PID" ]; then
  echo "Process $PID is not running." >&2
  exit 1
fi
PROCESS_NAME="$(cat "/proc/$PID/comm" 2>/dev/null || echo '?')"

# Authoritative check: is jemalloc mapped into the process's address space?
if grep -q "libjemalloc.so.2" "/proc/$PID/maps" 2>/dev/null; then
  echo "Process '$PROCESS_NAME' (PID: $PID) is using jemalloc."
  grep "libjemalloc.so.2" "/proc/$PID/maps" | head -n 1
else
  echo "No jemalloc references found for process '$PROCESS_NAME' (PID: $PID)." >&2
  echo "--- /proc/$PID/maps (first lines) ---" >&2
  head -n 5 "/proc/$PID/maps" 2>/dev/null >&2 || true
  if command -v lsof >/dev/null 2>&1; then
    echo "--- lsof -p $PID (jemalloc) ---" >&2
    lsof -p "$PID" 2>/dev/null | grep -i jemalloc >&2 || true
  fi
  exit 1
fi
