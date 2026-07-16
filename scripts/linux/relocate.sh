#!/usr/bin/env bash
#
# Atomically install the jemalloc shared library into its expected location.
#
# Why this exists (issue #5): the action persists LD_PRELOAD=<dest> into
# $GITHUB_ENV, so on a second in-job invocation `dest` is mapped into every
# running process — including the very tool doing the copy. A plain
# `cp src dest` opens the destination O_TRUNC and rewrites it in place, which
# truncates that live-mapped shared object out from under those processes and
# crashes them with SIGSEGV (exit 139).
#
# The fix: write to a temp file in the destination directory and rename(2) it
# over the target. rename() atomically swaps the directory entry while any
# process that already mapped the old inode keeps reading it unharmed. We also
# short-circuit when the destination already byte-matches the source, so an
# idempotent re-invocation never touches a mapped library at all.
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

  # Idempotent: destination already correct -> do not touch a possibly-mapped lib.
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "jemalloc already in place at $dest; skipping relocate"
    return 0
  fi

  # Atomic replace via a temp file in the same directory + rename(2).
  local tmp
  tmp="$($SUDO mktemp "${dest}.XXXXXX")" || return 1
  if ! $SUDO cp "$src" "$tmp"; then
    $SUDO rm -f "$tmp"
    return 1
  fi
  # mktemp creates 0600; restore the world-readable 0755 that `make install`
  # gives the shared object so a non-root workload can LD_PRELOAD it.
  $SUDO chmod 0755 "$tmp" || { $SUDO rm -f "$tmp"; return 1; }
  $SUDO mv -f "$tmp" "$dest" || { $SUDO rm -f "$tmp"; return 1; }
  echo "Relocated jemalloc to $dest"
}

# Allow direct execution: scripts/linux/relocate.sh <src> <dest>
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  set -euo pipefail
  relocate_jemalloc "$@"
fi
