#!/bin/bash
#
# Verify that a given PID has jemalloc inserted (macOS). Prints diagnostics and
# exits non-zero if jemalloc is not mapped into the process. Read-only verifier
# — it does not signal the target.
#
# The action inserts a dyld interposer (jemalloc_interpose.dylib) via
# DYLD_INSERT_LIBRARIES, which pulls in libjemalloc.2.dylib and routes the
# process's malloc to jemalloc.

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

if ! ps -p "$PID" >/dev/null 2>&1; then
  echo "Process $PID is not running." >&2
  exit 1
fi
PROCESS_NAME=$(ps -p "$PID" -o comm=)

# Is jemalloc actually mapped into the process's address space?
MAPPED=""
if command -v vmmap >/dev/null 2>&1; then
  MAPPED=$(vmmap "$PID" 2>/dev/null | grep -m1 "libjemalloc.2.dylib" || true)
fi
if [ -z "$MAPPED" ] && command -v lsof >/dev/null 2>&1; then
  MAPPED=$(lsof -p "$PID" 2>/dev/null | grep -m1 "libjemalloc.2.dylib" || true)
fi

if [ -n "$MAPPED" ]; then
  echo "Process '$PROCESS_NAME' (PID: $PID) is using jemalloc."
  echo "$MAPPED"
else
  echo "No jemalloc references found for process '$PROCESS_NAME' (PID: $PID)." >&2
  echo "(On macOS, SIP strips DYLD_* from Apple-protected binaries, so jemalloc" >&2
  echo " cannot be inserted into those; use a non-restricted binary.)" >&2
  exit 1
fi
