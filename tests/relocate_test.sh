#!/usr/bin/env bash
# shellcheck disable=SC1090  # relocate scripts are sourced via known-constant path vars
#
# Unit tests for the jemalloc relocate scripts (issue #5).
#
# These tests are dependency-free (no bats) so they run identically on a dev
# machine and on a bare CI runner. They exercise the relocate logic without
# sudo by exporting SUDO="" and operating inside a scratch directory.
#
# Each test maps to an evaluation criterion in PLAN.md (EC1..EC5).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_RELOCATE="$REPO_ROOT/scripts/linux/relocate.sh"
MAC_RELOCATE="$REPO_ROOT/scripts/mac/relocate.sh"

export SUDO=""

PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "FAIL - $1: ${2:-}"; }

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" == "$3" ]; then pass "$1"; else fail "$1" "expected '$2' got '$3'"; fi
}

new_workdir() {
  mktemp -d "${TMPDIR:-/tmp}/relocate_test.XXXXXX"
}

# ---------------------------------------------------------------------------
# EC1 — Fresh install into a missing destination dir
# ---------------------------------------------------------------------------
test_fresh_install() {
  local wd src dest
  wd="$(new_workdir)"
  src="$wd/src.so"
  dest="$wd/libdir/libjemalloc.so.2"   # libdir does not exist yet
  printf 'NEWLIB' > "$src"

  if ( . "$LINUX_RELOCATE"; relocate_jemalloc "$src" "$dest" ) >/dev/null 2>&1; then
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
      pass "EC1 fresh install copies file and creates dir"
    else
      fail "EC1 fresh install copies file and creates dir" "dest missing or mismatched"
    fi
  else
    fail "EC1 fresh install copies file and creates dir" "relocate returned non-zero"
  fi
  rm -rf "$wd"
}

# ---------------------------------------------------------------------------
# EC2 — Idempotent skip when destination already matches (inode unchanged)
# ---------------------------------------------------------------------------
test_idempotent_skip() {
  local wd src dest ino_before ino_after
  wd="$(new_workdir)"
  src="$wd/src.so"
  dest="$wd/lib/libjemalloc.so.2"
  mkdir -p "$wd/lib"
  printf 'SAME' > "$src"
  cp "$src" "$dest"
  ino_before="$(stat -f '%i' "$dest" 2>/dev/null || stat -c '%i' "$dest")"

  ( . "$LINUX_RELOCATE"; relocate_jemalloc "$src" "$dest" ) >/dev/null 2>&1
  ino_after="$(stat -f '%i' "$dest" 2>/dev/null || stat -c '%i' "$dest")"

  assert_eq "EC2 idempotent skip leaves inode unchanged" "$ino_before" "$ino_after"
  rm -rf "$wd"
}

# ---------------------------------------------------------------------------
# EC3 — Atomic replace preserves the old inode for a process holding it open.
#       This is the direct regression guard for the exit-139 SIGSEGV: a live
#       mmap/open fd on the old library must NOT be truncated in place.
# ---------------------------------------------------------------------------
test_atomic_replace_preserves_open_fd() {
  local wd src dest via_fd
  wd="$(new_workdir)"
  src="$wd/src.so"
  dest="$wd/lib/libjemalloc.so.2"
  mkdir -p "$wd/lib"
  printf 'OLDBYTES' > "$dest"
  printf 'NEWBYTES' > "$src"

  # Open a long-lived fd on the destination BEFORE relocating (stands in for a
  # process that has LD_PRELOAD'd / mmap'd the old library).
  exec 9<"$dest"
  ( . "$LINUX_RELOCATE"; relocate_jemalloc "$src" "$dest" ) >/dev/null 2>&1
  # Read what the still-open fd sees. With an atomic rename the old inode is
  # intact ("OLDBYTES"). With an in-place truncating cp it would be clobbered.
  via_fd="$(cat <&9)"
  exec 9<&-

  assert_eq "EC3 open fd still sees old inode (no in-place truncate)" "OLDBYTES" "$via_fd"
  rm -rf "$wd"
}

# ---------------------------------------------------------------------------
# EC4 — After replacing a differing destination, dest matches the new source
# ---------------------------------------------------------------------------
test_content_updated() {
  local wd src dest
  wd="$(new_workdir)"
  src="$wd/src.so"
  dest="$wd/lib/libjemalloc.so.2"
  mkdir -p "$wd/lib"
  printf 'OLDBYTES' > "$dest"
  printf 'NEWBYTES' > "$src"

  ( . "$LINUX_RELOCATE"; relocate_jemalloc "$src" "$dest" ) >/dev/null 2>&1
  if cmp -s "$src" "$dest"; then
    pass "EC4 destination updated to new content"
  else
    fail "EC4 destination updated to new content" "dest does not match src"
  fi
  rm -rf "$wd"
}

# ---------------------------------------------------------------------------
# EC5 — Missing source fails cleanly (non-zero, no destination created)
# ---------------------------------------------------------------------------
test_missing_source_fails() {
  local wd dest rc
  wd="$(new_workdir)"
  dest="$wd/lib/libjemalloc.so.2"

  if ( . "$LINUX_RELOCATE"; relocate_jemalloc "$wd/does-not-exist.so" "$dest" ) >/dev/null 2>&1; then
    rc=0
  else
    rc=1
  fi
  if [ "$rc" -ne 0 ] && [ ! -f "$dest" ]; then
    pass "EC5 missing source fails without creating destination"
  else
    fail "EC5 missing source fails without creating destination" "rc=$rc dest_exists=$([ -f "$dest" ] && echo yes || echo no)"
  fi
  rm -rf "$wd"
}

# ---------------------------------------------------------------------------
# EC3 (mac parity) — same atomic guarantee for the dylib relocate script
# ---------------------------------------------------------------------------
test_mac_atomic_replace_preserves_open_fd() {
  local wd src dest via_fd
  wd="$(new_workdir)"
  src="$wd/src.dylib"
  dest="$wd/lib/libjemalloc.2.dylib"
  mkdir -p "$wd/lib"
  printf 'OLDDYLIB' > "$dest"
  printf 'NEWDYLIB' > "$src"

  exec 8<"$dest"
  ( . "$MAC_RELOCATE"; relocate_jemalloc "$src" "$dest" ) >/dev/null 2>&1
  via_fd="$(cat <&8)"
  exec 8<&-

  assert_eq "EC3-mac open fd still sees old inode (no in-place truncate)" "OLDDYLIB" "$via_fd"
  rm -rf "$wd"
}

echo "== relocate unit tests =="
test_fresh_install
test_idempotent_skip
test_atomic_replace_preserves_open_fd
test_content_updated
test_missing_source_fails
test_mac_atomic_replace_preserves_open_fd

echo ""
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'Failing: %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
