#!/bin/bash
#
# Verify that a given PID has jemalloc inserted (macOS). Prints diagnostics and
# exits non-zero if jemalloc is not inserted. Read-only verifier — it does not
# signal the target. macOS is currently unsupported (see README); this is kept
# in parity with the Linux verifier.

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <pid>"
  exit 1
fi
PID="$1"

if [ -z "${DYLD_INSERT_LIBRARIES:-}" ]; then
  echo "DYLD_INSERT_LIBRARIES is not set — required on macOS to insert jemalloc" >&2
  exit 1
fi
echo "DYLD_INSERT_LIBRARIES is set to $DYLD_INSERT_LIBRARIES"

if [ "${DYLD_FORCE_FLAT_NAMESPACE:-}" != "1" ]; then
  echo "DYLD_FORCE_FLAT_NAMESPACE must be set to 1 on macOS to insert jemalloc" >&2
  exit 1
fi
echo "DYLD_FORCE_FLAT_NAMESPACE is set to $DYLD_FORCE_FLAT_NAMESPACE"

if ! ps -p "$PID" >/dev/null 2>&1; then
  echo "Process $PID is not running." >&2
  exit 1
fi
PROCESS_NAME=$(ps -p "$PID" -o comm=)

LSOF_OUT=$(lsof -p "$PID" || true)
echo "Open files (lsof -p $PID):"
echo "$LSOF_OUT"
echo ""

if echo "$LSOF_OUT" | grep -q "libjemalloc.2.dylib"; then
  echo "Process '$PROCESS_NAME' (PID: $PID) is using jemalloc."
else
  echo "No jemalloc references found for process '$PROCESS_NAME' (PID: $PID)." >&2
  exit 1
fi
