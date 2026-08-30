# setup-jemalloc GitHub Action
![badge](https://github.com/kaeawc/setup-jemalloc/actions/workflows/commit.yml/badge.svg)

This action downloads, installs, and caches jemalloc. Subsequent workflow steps should automatically benefit from jemalloc replacing the default malloc, which can free up native memory left otherwise unusable by fragmentation.

## Supported Platforms

- `linux`

## Unsupported Platforms

- `macos`: Requires jemalloc to be built with arm64e target architecture for M1/M2/M3.
- `windows` 

## Example
```yaml
jobs:
  build_your_app:

    # Add typical environment setup steps for node/java/python etc before jemalloc
    
    - name: Set up jemalloc
      uses: kaeawc/setup-jemalloc@v0.0.5

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
      uses: kaeawc/setup-jemalloc@v0.0.5

    - name: Use the outputs
      run: |
        echo "cache-hit: ${{ steps.jemalloc.outputs.cache-hit }}"
        echo "library:   ${{ steps.jemalloc.outputs.library-path }}"
```

## Verification

You can use the scripts located in `./scripts/$platform/verify.sh` for the relevant platform
to verify a given PID is running with jemalloc preloaded.
