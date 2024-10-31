# setup-jemalloc
A GitHub Action to download, install, and cache jemalloc on any platform runner. Subsequent workflow steps should automatically benefit from jemalloc replacing the default malloc, which can free up native memory left otherwise unusable by fragmentation.

## Supported Platforms

- `linux`
- `macos`
- `windows`

## Usage

To use this action in your workflow, add the following step:

```yaml
- name: Set up jemalloc
  uses: kaeawc/setup-jemalloc@v1
- name: Build Application
  run: make
```
