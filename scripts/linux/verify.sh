#!/bin/bash
#
# Verify that a given PID has jemalloc preloaded (Linux). Prints diagnostics and
# exits non-zero if jemalloc is not preloaded. Intended for CI checks and manual
# debugging. This is a read-only verifier — it does not signal the target.

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

if ! ps -p "$PID" >/dev/null 2>&1; then
  echo "Process $PID is not running." >&2
  exit 1
fi
PROCESS_NAME=$(ps -p "$PID" -o comm=)

# Diagnostics: open files (captured once) and memory mappings.
LSOF_OUT=$(lsof -p "$PID" || true)
echo "Open files (lsof -p $PID):"
echo "$LSOF_OUT"
echo ""
echo "jemalloc entries in /proc/$PID/maps:"
grep "libjemalloc.so.2" "/proc/$PID/maps" || echo "  (none)"
echo ""

if echo "$LSOF_OUT" | grep -q "libjemalloc.so.2"; then
  echo "Process '$PROCESS_NAME' (PID: $PID) is using jemalloc."
else
  echo "No jemalloc references found for process '$PROCESS_NAME' (PID: $PID)." >&2
  exit 1
fi
