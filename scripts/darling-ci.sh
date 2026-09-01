#!/usr/bin/env bash
set -uo pipefail
#
# Experimental Darling CI (issue #34): exercise setup-jemalloc's macOS/Darwin
# path on a Linux runner via Darling (https://darlinghq.org).
#
# There is no Xcode project in this repo, so there is no xcodebuild step to
# port. What the macOS path actually consists of is:
#   1. the mac shell helpers (scripts/mac/*.sh, tested by tests/relocate_test.sh),
#   2. building jemalloc as a Darwin dylib (./configure && make), and
#   3. the dyld interposer (macos/jemalloc_interpose.c) that routes malloc to
#      jemalloc — verified via macos/zone_check.c.
# This script runs whatever of that Darling's userland supports, and probes for
# the rest. Results land in the job step summary.
#
# Exit status:
#   0 — Darling booted and the shell-level Darwin checks ran (build/interpose
#       steps are best-effort: reported, not fatal, since Darling's toolchain
#       coverage is incomplete).
#   1 — infrastructure failure: darling missing or the prefix would not boot.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"
DARLING_TIMEOUT="${DARLING_TIMEOUT:-300}"
JEMALLOC_VERSION="${JEMALLOC_VERSION:-5.3.0}"

summary() { printf '%s\n' "$*" >>"$SUMMARY_FILE"; }
log() { printf '\n=== %s\n' "$*"; }

# Run a command line inside the Darling prefix. `darling shell` treats its
# arguments as literal argv words, so hand the line to the guest bash. Darling
# maps the Linux cwd to the same path in the prefix, so relative paths work.
indarling() {
  timeout "$DARLING_TIMEOUT" darling shell /bin/bash -c "$*" </dev/null
}

if ! command -v darling >/dev/null 2>&1; then
  echo "error: darling is not installed" >&2
  exit 1
fi

log "Booting Darling prefix (first run initializes ~/.darling)"
if ! indarling 'sw_vers; uname -mrs'; then
  echo "error: Darling failed to boot" >&2
  exit 1
fi

summary "## Darling — setup-jemalloc Darwin path"
summary ""
summary "Darwin userland: \`$(indarling 'sw_vers -productName; sw_vers -productVersion' 2>/dev/null | tr '\n' ' ')\`"
summary ""

# ---------------------------------------------------------------------------
# Which macOS build/verify tools does Darling actually ship?
# ---------------------------------------------------------------------------
log "Probing for build/verify tools inside Darling"
summary "### tools available inside Darling"
summary ""
summary "| tool | present |"
summary "|------|---------|"
have_cc=""
have_make=""
for tool in clang cc gcc make ld otool install_name_tool nm lsof vmmap sysctl sw_vers curl tar bzip2 xcodebuild; do
  if path="$(indarling "command -v $tool" 2>/dev/null)"; then
    summary "| \`$tool\` | yes — \`$path\` |"
    case "$tool" in
      clang) have_cc="clang" ;;
      cc)    [ -z "$have_cc" ] && have_cc="cc" ;;
      make)  have_make="1" ;;
    esac
  else
    summary "| \`$tool\` | no |"
  fi
done
summary ""

# ---------------------------------------------------------------------------
# 1. The mac shell helpers, exercised on a real Darwin userland.
# ---------------------------------------------------------------------------
log "Running relocate unit tests under Darling"
if indarling 'bash tests/relocate_test.sh' >/tmp/reloc.log 2>&1; then
  summary "- relocate unit tests (scripts/mac + linux relocate.sh): **pass** on Darwin"
else
  summary "- relocate unit tests: **fail** on Darwin (see log)"
  sed 's/^/    /' /tmp/reloc.log | tail -20
fi

# ---------------------------------------------------------------------------
# 2 + 3. Build jemalloc + the interposer + verify — only if Darling ships a
#        C toolchain. (Reported, never fatal.)
# ---------------------------------------------------------------------------
if [ -n "$have_cc" ] && [ -n "$have_make" ]; then
  log "Building jemalloc under Darling ($have_cc)"
  build_ok=""
  if indarling "
    set -e
    curl -fLo jemalloc.tar.bz2 https://github.com/jemalloc/jemalloc/releases/download/$JEMALLOC_VERSION/jemalloc-$JEMALLOC_VERSION.tar.bz2
    bash scripts/linux/checksums.sh jemalloc.tar.bz2 $JEMALLOC_VERSION ''
    tar xf jemalloc.tar.bz2
    cd jemalloc-$JEMALLOC_VERSION
    ./configure --disable-cxx
    make -j2
    ls -la lib/
    file lib/libjemalloc.2.dylib
  " >/tmp/build.log 2>&1; then
    build_ok=1
    summary "- jemalloc Darwin build (\`./configure && make\`): **pass** — produced \`libjemalloc.2.dylib\`"
    grep -iE "Mach-O|dylib:" /tmp/build.log | sed 's/^/    /' | tail -3
  else
    summary "- jemalloc Darwin build: **fail** under Darling (see log)"
    tail -25 /tmp/build.log | sed 's/^/    /'
  fi

  if [ -n "$build_ok" ]; then
    log "Building the interposer + verifying jemalloc serves malloc under Darling"
    if indarling "
      set -e
      libdir=\"\$PWD/jemalloc-$JEMALLOC_VERSION/lib\"
      $have_cc -O2 -dynamiclib macos/jemalloc_interpose.c -o jemalloc_interpose.dylib -L \"\$libdir\" -ljemalloc -Wl,-rpath,\"\$libdir\"
      dep=\"\$(otool -L jemalloc_interpose.dylib | awk '/libjemalloc\\.2\\.dylib/{print \$1; exit}')\"
      install_name_tool -change \"\$dep\" \"\$libdir/libjemalloc.2.dylib\" jemalloc_interpose.dylib || true
      $have_cc -O2 -o zone_check macos/zone_check.c
      export JEMALLOC_INTERPOSE_STATS=\"\$PWD/calls.txt\"
      DYLD_INSERT_LIBRARIES=\"\$PWD/jemalloc_interpose.dylib\" ./zone_check || true
      echo \"interpose_calls=\$(cat calls.txt 2>/dev/null || echo 0)\"
    " >/tmp/interpose.log 2>&1; then
      calls="$(grep -oE 'interpose_calls=[0-9]+' /tmp/interpose.log | tail -1 | cut -d= -f2)"
      if [ "${calls:-0}" -gt 0 ] 2>/dev/null; then
        summary "- dyld interposer under Darling: **jemalloc served ${calls} malloc calls** 🎉"
      else
        summary "- dyld interposer under Darling: built + ran, but jemalloc served 0 calls (Darling dyld interposition limitation)"
      fi
      grep -iE "interpose_calls=|zone=|jemalloc_loaded=|served_by_jemalloc=" /tmp/interpose.log | sed 's/^/    /'
    else
      summary "- dyld interposer under Darling: **could not build/run** (see log)"
      tail -20 /tmp/interpose.log | sed 's/^/    /'
    fi
  fi
else
  summary "- jemalloc Darwin build: **skipped** — Darling's minimal CLI closure ships no C toolchain (clang/make). Building jemalloc under Darling would need a Darwin clang + SDK headers."
fi

# ---------------------------------------------------------------------------
# xcodebuild — expected unavailable (Darling ships no Xcode/SDK; setup-jemalloc
# has no Xcode project anyway). Recorded for completeness.
# ---------------------------------------------------------------------------
log "Attempting xcodebuild (expected: unavailable)"
if indarling 'xcodebuild -version' >/tmp/xcode.log 2>&1; then
  summary "- \`xcodebuild\`: unexpectedly available — $(head -1 /tmp/xcode.log)"
else
  summary "- \`xcodebuild\`: **unavailable** (Darling ships no Xcode/SDK; and this repo has no Xcode project — the macOS build is jemalloc's Darwin \`./configure && make\`)."
fi

log "Done"
exit 0
