# setup-jemalloc GitHub Action
![badge](https://github.com/kaeawc/setup-jemalloc/actions/workflows/commit.yml/badge.svg)

This action downloads, installs, and caches jemalloc. Subsequent workflow steps should automatically benefit from jemalloc replacing the default malloc, which can free up native memory left otherwise unusable by fragmentation.

## Supported Platforms

- `linux`

## In Development Platforms

- `macos`
- `windows` 

## Example
```yaml
jobs:
  hash_string:
    - name: Set up jemalloc
      uses: kaeawc/setup-jemalloc@v0.0.1
    - name: Build Application
      run: make
```

## Inputs
| Argument | Description | Default | Required |
|----------|-------------|---------|---------|
| jemalloc-version    | The version of jemalloc to be used | 5.3.0 | yes |
