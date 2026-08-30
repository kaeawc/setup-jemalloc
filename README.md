# setup-jemalloc GitHub Action
![badge](https://github.com/kaeawc/setup-jemalloc/actions/workflows/commit.yml/badge.svg)

This action downloads, installs, and caches jemalloc. Subsequent workflow steps should automatically benefit from jemalloc replacing the default malloc, which can free up native memory left otherwise unusable by fragmentation.

## Supported Platforms

Linux on both **x64** and **arm64**. The action builds jemalloc from source, so
it is distro-agnostic. CI exercises it end-to-end on each push across a wide
matrix of distros × architectures:

| Distro | libc | x64 | arm64 |
|--------|------|-----|-------|
| Ubuntu 22.04 / 24.04 | glibc | ✅ | ✅ |
| Debian 12 | glibc | ✅ | ✅ |
| Fedora 40 | glibc | ✅ | ✅ |
| Rocky Linux 9 | glibc | ✅ | ✅ |
| openSUSE Leap 15 | glibc | ✅ | ✅ |
| Arch Linux | glibc | ✅ | — (no official arm64 image) |
| Alpine 3.20 | **musl** | ✅ | — (GitHub runs JS actions in Alpine only on x64) |

The cache is keyed by OS, architecture, and distro/version, so a library built
for one platform is never restored into an incompatible one.

**Windows** is also supported, but through a different mechanism (a wrapped
launcher rather than transparent preload) — see the [Windows](#windows) section.

### Toolchain prerequisite

Because jemalloc is built from source, the runner (or container) must have a C
toolchain and a few utilities available **before** this action runs: `gcc`,
`make`, `curl`, `bzip2`, `tar`, and `ca-certificates`. GitHub-hosted `ubuntu-*`
runners already include these. In a minimal distro container, install them
first — for example:

```yaml
    # Debian/Ubuntu
    - run: apt-get update && apt-get install -y gcc make curl bzip2 tar ca-certificates
    # Alpine (musl) — gcompat/libstdc++ let GitHub's node run on musl
    - run: apk add --no-cache build-base curl bzip2 tar ca-certificates git bash gcompat libstdc++
    - uses: kaeawc/setup-jemalloc@v0.0.6
```

`scripts/linux/verify.sh` relies only on `/proc`, so it needs no extra tools.

## Windows

Windows has **no transparent allocator-preload mechanism** (no `LD_PRELOAD`
equivalent), so jemalloc cannot be injected into every step automatically the
way it is on Linux. Instead, the action builds `jemalloc.dll` plus a
**Detours-based launcher**, `jemalloc-run.exe`, and you **wrap** the command
whose allocations you want served by jemalloc:

```yaml
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up jemalloc
        id: jemalloc
        uses: kaeawc/setup-jemalloc@v0.0.6

      # Wrap your workload; its malloc/free/calloc/realloc are served by jemalloc.
      - name: Run with jemalloc
        run: |
          & "${{ steps.jemalloc.outputs.jemalloc-run }}" my-app.exe --args
```

`jemalloc-run.exe` injects a shim (via Microsoft Detours) that redirects the
child process's C runtime allocator to jemalloc. Notes and limitations:

- Only processes that use the **shared** Universal CRT (compiled `/MD`) are
  redirected; statically-linked-CRT binaries (`/MT`) are not.
- Only the wrapped process (and its allocations) are affected — not unrelated
  steps.
- The action needs a build toolchain on the runner; GitHub-hosted
  `windows-latest` has Visual Studio, and the action installs MSYS2/mingw for
  the jemalloc build itself.

## macOS

On modern macOS, `DYLD_INSERT_LIBRARIES`'ing jemalloc **alone does not replace
the allocator** (neither jemalloc's malloc-zone override nor flat-namespace
symbol interposition routes `malloc` to jemalloc — verified on `macos-14`). The
action instead builds a small **dyld interposer** dylib that redirects the C
allocator (`malloc`/`free`/`calloc`/`realloc`/`malloc_size`) to jemalloc's
`je_*`, and inserts *that* via `DYLD_INSERT_LIBRARIES`.

Like the Windows path, this is a **wrap-your-command** model (the action does
*not* insert jemalloc globally — doing so can deadlock complex tools such as
the compiler, and SIP would strip it from protected binaries anyway). The
action exposes the interposer as the `interpose-dylib` output; wrap the command
whose allocations you want served by jemalloc:

```yaml
    - name: Set up jemalloc
      id: jemalloc
      uses: kaeawc/setup-jemalloc@v0.0.6

    - name: Run with jemalloc
      run: |
        DYLD_INSERT_LIBRARIES="${{ steps.jemalloc.outputs.interpose-dylib }}" ./my-workload
```

**Limitations:**
- **SIP:** macOS strips `DYLD_*` when launching Apple-protected binaries
  (`/bin/*`, `/usr/bin/*`, hardened runtime), so jemalloc can only be inserted
  into non-restricted binaries (your own builds, Homebrew binaries).
- As with any malloc interposer, some programs may be incompatible; wrap the
  specific workload you want accelerated rather than inserting globally.
- arm64 (Apple silicon) and x64 are both supported; regular `arm64` dylibs
  inject fine (no `arm64e` needed).

## Unsupported Platforms

_None — Linux, macOS, and Windows are all supported (with the platform-specific
mechanisms and caveats described above)._

## Example
```yaml
jobs:
  build_your_app:

    # Add typical environment setup steps for node/java/python etc before jemalloc
    
    - name: Set up jemalloc
      uses: kaeawc/setup-jemalloc@v0.0.6

    # Any processes run (bash, java, golang, python, etc) will benefit from using jemalloc automatically.
    - name: Build Application
      run: make
    
```

## Re-invoking within a job

The action is safe to invoke more than once in the same job. Installs are atomic
and idempotent, so a later invocation will not disturb the `jemalloc` library
already preloaded into running processes.

## Inputs
| Argument | Description | Default | Required |
|----------|-------------|---------|---------|
| jemalloc-version | The version of jemalloc to be used | `5.3.0` | no |
| jemalloc-sha256 | Optional SHA-256 to verify the downloaded tarball against. Overrides the built-in checksum and lets you pin a version that has no baked-in value. When empty and the version is unknown, the integrity check is skipped with a warning. | `""` | no |

## Outputs
| Name | Description |
|------|-------------|
| cache-hit | Whether the jemalloc library was restored from cache (`true`/`false`; empty on non-Linux runners). |
| library-path | Absolute path to the installed `libjemalloc.so.2` (empty on non-Linux runners). |
| ld-preload | The `LD_PRELOAD` value the action set (empty on non-Linux runners). |

```yaml
    - name: Set up jemalloc
      id: jemalloc
      uses: kaeawc/setup-jemalloc@v0.0.6

    - name: Use the outputs
      run: |
        echo "cache-hit: ${{ steps.jemalloc.outputs.cache-hit }}"
        echo "library:   ${{ steps.jemalloc.outputs.library-path }}"
```

## Verification

You can use the scripts located in `./scripts/$platform/verify.sh` for the relevant platform
to verify a given PID is running with jemalloc preloaded.
