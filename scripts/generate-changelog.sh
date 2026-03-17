#!/bin/bash
# generate-changelog.sh - Generates changelog from conventional commits between tags
# Usage: ./scripts/generate-changelog.sh [previous_tag]

set -euo pipefail

PREVIOUS_TAG="${1:-}"

# Find the previous tag if not provided
if [ -z "$PREVIOUS_TAG" ]; then
  PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
fi

# Build git log range
if [ -n "$PREVIOUS_TAG" ]; then
  RANGE="${PREVIOUS_TAG}..HEAD"
else
  RANGE="HEAD"
fi

# Collect commits by category
FEATURES=$(git log "$RANGE" --pretty=format:"%s (%h)" --grep="^feat" 2>/dev/null | sed 's/^feat[:(]//' | sed 's/^[^)]*): /: /' || true)
FIXES=$(git log "$RANGE" --pretty=format:"%s (%h)" --grep="^fix" 2>/dev/null | sed 's/^fix[:(]//' | sed 's/^[^)]*): /: /' || true)
CHORES=$(git log "$RANGE" --pretty=format:"%s (%h)" --grep="^chore\|^refactor\|^perf\|^style\|^ci\|^docs\|^build" 2>/dev/null || true)

# Collect contributors
CONTRIBUTORS=$(git log "$RANGE" --pretty=format:"%an" 2>/dev/null | sort -u | sed 's/^/- @/' || true)

# Build changelog
CHANGELOG=""

if [ -n "$FEATURES" ]; then
  CHANGELOG+="### Features"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$FEATURES"
  CHANGELOG+=$'\n'
fi

if [ -n "$FIXES" ]; then
  CHANGELOG+="### Bug Fixes"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$FIXES"
  CHANGELOG+=$'\n'
fi

if [ -n "$CHORES" ]; then
  CHANGELOG+="### Chore"$'\n'
  while IFS= read -r line; do
    CHANGELOG+="- ${line}"$'\n'
  done <<< "$CHORES"
  CHANGELOG+=$'\n'
fi

if [ -n "$CONTRIBUTORS" ]; then
  CHANGELOG+="### Contributors"$'\n'
  CHANGELOG+="${CONTRIBUTORS}"$'\n'
fi

# Fallback if no conventional commits found
if [ -z "$CHANGELOG" ]; then
  CHANGELOG="### Changes"$'\n'
  git log "$RANGE" --pretty=format:"- %s (%h)" 2>/dev/null | while IFS= read -r line; do
    CHANGELOG+="${line}"$'\n'
  done
fi

echo "$CHANGELOG"
