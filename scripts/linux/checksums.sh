#!/usr/bin/env bash
#
# SHA-256 integrity verification for jemalloc release tarballs.
#
# The downloaded tarball is built and then LD_PRELOAD'd into every subsequent
# job step, so a corrupted or tampered download is a supply-chain hazard. This
# verifies the tarball against a known-good checksum before it is trusted.
#
# Resolution order for the expected checksum:
#   1. an explicit override (the action's `jemalloc-sha256` input), else
#   2. a known-good value baked in for a supported version, else
#   3. no expectation -> warn and proceed (keeps arbitrary-version usage working
#      without silently downgrading known versions).

# known_sha256 <version> -> prints the known-good sha256, or empty if unknown.
known_sha256() {
  case "$1" in
    5.3.0) echo "2db82d1e7119df3e71b7640219b6dfe84789bc0537983c3b7ac4f7189aecfeaa" ;;
    *)     echo "" ;;
  esac
}

# sha256_of <file> -> prints the file's sha256 (GNU sha256sum or BSD shasum).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# verify_checksum <file> <version> [expected_override]
#   returns 0 on match (or unknown-with-no-override), 1 on mismatch/missing file.
verify_checksum() {
  local file="$1" version="$2" override="${3:-}"
  local expected actual

  if [ ! -f "$file" ]; then
    echo "Checksum: file not found: $file" >&2
    return 1
  fi

  expected="$override"
  [ -z "$expected" ] && expected="$(known_sha256 "$version")"
  actual="$(sha256_of "$file")"

  if [ -z "$expected" ]; then
    echo "::warning::No known SHA-256 for jemalloc $version and no jemalloc-sha256 provided; skipping integrity check (downloaded $actual)"
    return 0
  fi

  if [ "$actual" != "$expected" ]; then
    echo "::error::Checksum mismatch for $file (jemalloc $version): expected $expected, got $actual" >&2
    return 1
  fi

  echo "Checksum OK for jemalloc $version: $actual"
  return 0
}

# Allow direct execution: checksums.sh <file> <version> [expected_override]
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  set -euo pipefail
  verify_checksum "$@"
fi
