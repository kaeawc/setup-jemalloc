# setup-jemalloc GitHub Action
![badge](https://github.com/kaeawc/setup-jemalloc/actions/workflows/mac.yml/badge.svg) ![badge](https://github.com/kaeawc/setup-jemalloc/actions/workflows/linux.yml/badge.svg) ![badge](https://github.com/kaeawc/setup-jemalloc/actions/workflows/windows.yml/badge.svg)

This action downloads, installs, and caches jemalloc on any platform runner. Subsequent workflow steps should automatically benefit from jemalloc replacing the default malloc, which can free up native memory left otherwise unusable by fragmentation.

## Supported Platforms

- `linux`
- `macos`

## In Development Platforms

- `windows` 

## Example
```yaml
jobs:
  hash_string:
    - name: Set up jemalloc
      uses: kaeawc/setup-jemalloc@v1
    - name: Build Application
      run: make
```

## Inputs
| Argument | Description | Default | Required |
|----------|-------------|---------|---------|
| jemalloc-version    | The version of jemalloc to be used | 5.3.0 | yes |
