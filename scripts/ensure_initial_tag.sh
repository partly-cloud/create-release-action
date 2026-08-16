#!/usr/bin/env bash
set -euo pipefail

if [ -z "$(git tag --list '[0-9]*.[0-9]*.[0-9]*')" ]; then
  echo "No semver tags found, creating initial 0.0.0 tag at root commit."
  git tag 0.0.0 "$(git rev-list --max-parents=0 HEAD)"
  git push origin 0.0.0
else
  echo "Semver tags found, skipping initial tag creation."
fi
