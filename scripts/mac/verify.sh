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
  exit 1
else
  echo "Process '$PROCESS_NAME' (PID: $PID) is using jemalloc."
  echo "jemalloc reference found at:"
  echo "$JEMALLOC_REF"
fi
