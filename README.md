# setup-brel

GitHub Action to install [`brel`](https://github.com/better-releases/brel) from GitHub Releases and make it available in `PATH` for following steps.

## Usage

```yaml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup brel
        uses: better-releases/setup-brel@v1

      - name: Use brel
        run: brel next-version
```

### Pin a specific version

```yaml
- name: Setup brel
  uses: better-releases/setup-brel@v1
  with:
    version: v0.4.0
```

### Inputs

- `version`: release tag (`latest` by default)
- `release-repo`: release source repo in `owner/repo` format (`better-releases/brel` by default)
- `target`: target triple (`auto` by default)
- `install-dir`: custom install directory (defaults to `RUNNER_TEMP`)
- `github-token`: optional token for GitHub API requests

### Outputs

- `path`: directory added to `PATH`
- `version`: installed release tag
- `target`: installed target triple
- `binary`: full path to installed binary

## Releasing This Action

This repository includes `.github/workflows/release.yml`.

- Push a stable semver tag like `v1.0.0`.
- The workflow creates a GitHub Release for that tag (with generated notes).
- The workflow also force-updates the moving major tag (for example `v1`) to the same commit.
