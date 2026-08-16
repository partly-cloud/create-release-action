#!/usr/bin/env bash
set -euo pipefail

if [[ "$PRERELEASE" == "true" && -z "${PR_NUMBER:-}" ]]; then
  echo "::error::pr_number is required when prerelease is 'true'"
  exit 1
fi

if [[ "$PRERELEASE" == "true" ]]; then
  SHORT_SHA=$(git rev-parse --short HEAD)
  RELEASE_TAG="${NEXT_VERSION}-rc-pr-${PR_NUMBER}-${SHORT_SHA}"
else
  RELEASE_TAG="${NEXT_VERSION}"
fi

echo "Creating tag: $RELEASE_TAG"
echo "RELEASE_TAG=$RELEASE_TAG" >> "$GITHUB_ENV"
echo "tag=$RELEASE_TAG" >> "$GITHUB_OUTPUT"

git tag "$RELEASE_TAG"
git push origin "$RELEASE_TAG"
