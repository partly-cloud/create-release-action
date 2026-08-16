# create-release-action

Composite GitHub Action that creates a semantic version tag and GitHub release, optionally marked as a prerelease.

## Requirements

The calling job must have `contents: write` permission so the action can push tags and create GitHub releases:

```yaml
jobs:
  my-job:
    permissions:
      contents: write
```

The calling workflow must also check out the repository before using this action, with full history and credentials so the action can push tags:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
    persist-credentials: true
```

## Usage

```yaml
- uses: partly-cloud/create-release-action@main
  with:
    branch: ${{ github.event.pull_request.head.ref }}
    pr_number: ${{ github.event.pull_request.number }}
    prerelease: "true"
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `branch` | yes | — | Branch name used for semver calculation |
| `pr_number` | no | `""` | Pull request number. Required when `prerelease` is `true` |
| `prerelease` | no | `"false"` | Set to `"true"` to create a prerelease tag (`<version>-rc-pr-<pr>-<sha>`) and mark the release as a prerelease. When `"false"`, a plain semver tag is created |

## Outputs

| Output | Description |
|---|---|
| `tag` | The tag that was created |
| `release_url` | The URL of the created GitHub release |

## Tag format

| Mode | Format | Example |
|---|---|---|
| Prerelease (`prerelease: "true"`) | `<version>-rc-pr-<pr_number>-<short_sha>` | `1.3.0-rc-pr-42-a1b2c3d` |
| Release (`prerelease: "false"`) | `<version>` | `1.3.0` |

The version follows [Semantic Versioning 2.0.0](https://semver.org) and is calculated from conventional commits on the branch using [semver-action](https://github.com/ietf-tools/semver-action). A `feat:` commit bumps the minor version, a `fix:` bumps the patch, and a breaking change bumps the major.

## Semver skip behavior

If the semver calculation step fails — for example when a PR contains no conventional commits that bump the version — the action silently skips tag and release creation without failing the workflow. This is intentional: not every PR warrants a new release, and a missing conventional commit prefix should not block a merge.
