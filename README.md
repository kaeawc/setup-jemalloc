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
      uses: kaeawc/setup-jemalloc@v0.0.2

    # Any processes run (bash, java, golang, python, etc) will benefit from using jemalloc automatically.
    - name: Build Application
      run: make
    
```

## Inputs
| Argument | Description | Default | Required |
|----------|-------------|---------|---------|
| jemalloc-version    | The version of jemalloc to be used | 5.3.0 | yes |

## Verification

You can use the scripts located in `./scripts/$platform/verify.sh` for the relevant platform
to verify a given PID is running with jemalloc preloaded.
