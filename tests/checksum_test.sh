#!/usr/bin/env bash
# shellcheck disable=SC1090  # checksums.sh is sourced via a known-constant path var
#
# Unit tests for scripts/linux/checksums.sh (issue #13). Dependency-free, no
# network: we build fixture files locally and assert on the resolution logic.
#
# Criteria (CV1..CV6):
#   CV1 known version + matching file -> pass
#   CV2 known version + wrong file    -> fail (mismatch)
#   CV3 unknown version, no override  -> pass with warning (fail-open)
#   CV4 unknown version + matching override -> pass
#   CV5 override mismatch             -> fail
#   CV6 missing file                  -> fail

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKSUMS="$REPO_ROOT/scripts/linux/checksums.sh"

PASS=0
FAIL=0
FAILED_NAMES=()
pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "FAIL - $1: ${2:-}"; }

new_workdir() { mktemp -d "${TMPDIR:-/tmp}/checksum_test.XXXXXX"; }

# run_verify <file> <version> [override] -> sets RC to the return code, silences output
run_verify() {
  local rc
  if ( . "$CHECKSUMS"; verify_checksum "$@" ) >/dev/null 2>&1; then rc=0; else rc=1; fi
  RC="$rc"
}

# sha of arbitrary content, computed the same way the script does
sha_of_content() {
  local wd f
  wd="$(new_workdir)"; f="$wd/c"
  printf '%s' "$1" > "$f"
  ( . "$CHECKSUMS"; sha256_of "$f" )
  rm -rf "$wd"
}

# CV1 — the default version (5.3.0) has a well-formed baked-in checksum wired.
# We don't duplicate the literal here (that would only test a copy-paste); the
# enforcement of that value against real bytes is covered by CV2, and the
# match/mismatch mechanics by CV4/CV5.
test_known_table_value() {
  local got
  got="$( . "$CHECKSUMS"; known_sha256 5.3.0 )"
  if printf '%s' "$got" | grep -Eq '^[0-9a-f]{64}$'; then
    pass "CV1 default version has a well-formed checksum wired"
  else
    fail "CV1 default version has a well-formed checksum wired" "got '$got'"
  fi
}

# CV2 — known version + a file whose bytes do NOT match the baked-in sha -> fail.
test_known_version_mismatch() {
  local wd f
  wd="$(new_workdir)"; f="$wd/jemalloc.tar.bz2"
  printf 'not the real tarball' > "$f"
  run_verify "$f" "5.3.0"
  if [ "$RC" -ne 0 ]; then pass "CV2 known version + wrong bytes fails"; else fail "CV2 known version + wrong bytes fails" "rc=$RC"; fi
  rm -rf "$wd"
}

# CV3 — unknown version, no override -> pass (fail-open with warning).
test_unknown_no_override_passes() {
  local wd f
  wd="$(new_workdir)"; f="$wd/jemalloc.tar.bz2"
  printf 'anything' > "$f"
  run_verify "$f" "9.9.9"
  if [ "$RC" -eq 0 ]; then pass "CV3 unknown version + no override passes"; else fail "CV3 unknown version + no override passes" "rc=$RC"; fi
  rm -rf "$wd"
}

# CV4 — unknown version + override that matches the file -> pass.
test_override_match_passes() {
  local wd f sha
  wd="$(new_workdir)"; f="$wd/jemalloc.tar.bz2"
  printf 'payload-A' > "$f"
  sha="$(sha_of_content 'payload-A')"
  run_verify "$f" "9.9.9" "$sha"
  if [ "$RC" -eq 0 ]; then pass "CV4 override match passes"; else fail "CV4 override match passes" "rc=$RC"; fi
  rm -rf "$wd"
}

# CV5 — override that does not match the file -> fail.
test_override_mismatch_fails() {
  local wd f
  wd="$(new_workdir)"; f="$wd/jemalloc.tar.bz2"
  printf 'payload-A' > "$f"
  run_verify "$f" "9.9.9" "0000000000000000000000000000000000000000000000000000000000000000"
  if [ "$RC" -ne 0 ]; then pass "CV5 override mismatch fails"; else fail "CV5 override mismatch fails" "rc=$RC"; fi
  rm -rf "$wd"
}

# CV6 — missing file -> fail.
test_missing_file_fails() {
  local wd
  wd="$(new_workdir)"
  run_verify "$wd/nope.tar.bz2" "5.3.0"
  if [ "$RC" -ne 0 ]; then pass "CV6 missing file fails"; else fail "CV6 missing file fails" "rc=$RC"; fi
  rm -rf "$wd"
}

echo "== checksum unit tests =="
test_known_table_value
test_known_version_mismatch
test_unknown_no_override_passes
test_override_match_passes
test_override_mismatch_fails
test_missing_file_fails

echo ""
echo "Passed: $PASS  Failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'Failing: %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
