#!/usr/bin/env bash
set -euo pipefail

OLD_RC_TAGS=$(git tag --list "*-rc-pr-${PR_NUMBER}-*")

echo "OLD_RC_TAGS<<EOF" >> "$GITHUB_ENV"
echo "$OLD_RC_TAGS" >> "$GITHUB_ENV"
echo "EOF" >> "$GITHUB_ENV"

for OLD_TAG in $OLD_RC_TAGS; do
  echo "Deleting existing release candidate tag: $OLD_TAG"
  gh release delete "$OLD_TAG" --yes --cleanup-tag 2>/dev/null || true
done
