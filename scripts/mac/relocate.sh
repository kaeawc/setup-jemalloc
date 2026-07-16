#!/usr/bin/env bash
#
# Atomically install the jemalloc dylib into its expected location on macOS.
#
# Same hazard as the Linux path (issue #5): the action persists
# DYLD_INSERT_LIBRARIES=<dest>, so a second in-job invocation would `cp` in
# place over a dylib that is mapped into running processes. rename(2) keeps the
# old inode alive for anything that already mapped it; an idempotent match
# skips the copy entirely.
#
# SUDO is overridable (e.g. SUDO="" in unit tests) so the logic can run
# unprivileged against scratch paths.

SUDO="${SUDO-sudo}"

# relocate_jemalloc <src> <dest>
relocate_jemalloc() {
  local src="$1"
  local dest="$2"
  local dest_dir
  dest_dir="$(dirname "$dest")"

  if [ ! -f "$src" ]; then
    echo "Source library not found: $src" >&2
    return 1
  fi

  $SUDO install -d "$dest_dir" || return 1

  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "jemalloc already in place at $dest; skipping relocate"
    return 0
  fi

  local tmp
  tmp="$($SUDO mktemp "${dest}.XXXXXX")" || return 1
  if ! $SUDO cp "$src" "$tmp"; then
    $SUDO rm -f "$tmp"
    return 1
  fi
  # mktemp creates 0600; restore world-readable 0755 so a non-root workload
  # can map the dylib via DYLD_INSERT_LIBRARIES.
  $SUDO chmod 0755 "$tmp" || { $SUDO rm -f "$tmp"; return 1; }
  $SUDO mv -f "$tmp" "$dest" || { $SUDO rm -f "$tmp"; return 1; }
  echo "Relocated jemalloc to $dest"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  set -euo pipefail
  relocate_jemalloc "$@"
fi
