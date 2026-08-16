#!/usr/bin/env bash
set -euo pipefail

gh_args=(
  release create "$RELEASE_TAG"
  --generate-notes
  --title "$RELEASE_TAG"
)

[[ "$PRERELEASE" == "true" ]] && gh_args+=(--prerelease)

RELEASE_URL=$(gh "${gh_args[@]}")
echo "release_url=$RELEASE_URL" >> "$GITHUB_OUTPUT"
