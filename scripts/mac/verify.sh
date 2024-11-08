#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <process_name>"
  exit 1
fi

export PID="$1"
if [ -z "$PID" ]; then
  echo "Process '$1' not found."
  exit 1
fi

export DYLD_INSERT_LIBRARIES=/usr/local/lib/libjemalloc.2.dylib
export DYLD_FORCE_FLAT_NAMESPACE=1
export MallocNanoZone=0


echo "DYLD_INSERT_LIBRARIES: $DYLD_INSERT_LIBRARIES"
echo "DYLD_FORCE_FLAT_NAMESPACE: $DYLD_FORCE_FLAT_NAMESPACE"

if [ -z "$DYLD_INSERT_LIBRARIES" ]; then
  echo "DYLD_INSERT_LIBRARIES is not set, required on Mac platform to preload jemalloc"
  kill -9 "$PID"
  exit 1
fi

if [ -z "$DYLD_FORCE_FLAT_NAMESPACE" ]; then
  echo "DYLD_FORCE_FLAT_NAMESPACE is not set, required on Mac platform to preload jemalloc"
  kill -9 "$PID"
  exit 1
fi

if [ "$DYLD_FORCE_FLAT_NAMESPACE" != "1" ]; then
  echo "DYLD_FORCE_FLAT_NAMESPACE is not set to 1, required on Mac platform to preload jemalloc"
  kill -9 "$PID"
  exit 1
fi

echo "DYLD_INSERT_LIBRARIES is set to $DYLD_INSERT_LIBRARIES"

# Get the process name
PROCESS_NAME=$(ps -p "$PID" -o comm=)

# Check for jemalloc references in the open files of the process
echo "Running lsof -p"
echo "$(lsof -p "$PID")"
echo ""

echo "Looking in /proc/$PID/maps"
find "/proc/$PID/maps"
echo ""
JEMALLOC_REF=$(lsof -p "$PID" | grep "libjemalloc.2.dylib")

if [ -z "$JEMALLOC_REF" ]; then
  echo "No jemalloc references found for process '$PROCESS_NAME' (PID: $PID)."
  kill -9 "$PID"
  exit 1
else
  echo "Process '$PROCESS_NAME' (PID: $PID) is using jemalloc."
  echo "jemalloc reference found at:"
  echo "$JEMALLOC_REF"
fi
