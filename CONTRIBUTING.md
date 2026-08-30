# Contributing to setup-jemalloc

Thanks for helping improve this action! This is a small composite GitHub Action
that downloads, builds, caches, and `LD_PRELOAD`s jemalloc.

## Scope

- **Linux is the only supported platform today.** Every step in `action.yml` is
  gated on `runner.os == 'Linux'`, so the action is a graceful no-op elsewhere.
- macOS and Windows are **unsupported**. `scripts/mac/` is kept (and unit-tested)
  as scaffolding for a future macOS effort, but is not wired into `action.yml`.

## Layout

| Path | Purpose |
|------|---------|
| `action.yml` | The composite action (restore → relocate / download → verify → build → preload → save). |
| `scripts/linux/relocate.sh` | Atomic, idempotent install of the cached library (see #5). |
| `scripts/linux/checksums.sh` | SHA-256 verification of the downloaded tarball (see #13). |
| `scripts/{linux,mac}/verify.sh` | Read-only helpers that check a PID has jemalloc preloaded. |
| `tests/*.sh` | Dependency-free unit tests (no `bats`), runnable anywhere. |
| `.github/workflows/commit.yml` | CI: shellcheck + unit tests, plus end-to-end Linux jobs. |

## Development workflow (TDD)

1. **Write or update a test first** in `tests/` for the behavior you're changing.
   The tests are plain Bash with a tiny `pass`/`fail` harness — no dependencies.
2. Implement the change.
3. Run locally before pushing:
   ```bash
   shellcheck scripts/linux/*.sh scripts/mac/*.sh tests/*.sh
   bash tests/relocate_test.sh
   bash tests/checksum_test.sh
   ```
4. If your change touches the download/build/install path, exercise the
   **cache-miss** path (in CI, delete the `v7-Linux-jemalloc-*` cache and re-run)
   — the happy PR run often cache-hits and skips those steps.

## CI gates

Every PR must pass three checks: `unit_tests` (shellcheck + unit tests),
`linux` (installs the action and verifies a process is using jemalloc), and
`linux_double_invocation` (the #5 regression guard — invokes the action twice in
one job and asserts the first invocation's preloaded process survives the second).

## Releasing (maintainers)

1. Open a PR bumping the `uses: kaeawc/setup-jemalloc@vX.Y.Z` pin in `README.md`
   to the new version (direct pushes to `main` are blocked by the required checks).
2. After it merges and `main` is green, tag it and publish a GitHub release:
   ```bash
   git tag vX.Y.Z <merge-commit> && git push origin vX.Y.Z
   gh release create vX.Y.Z --target main --title vX.Y.Z --notes-file notes.md
   ```
