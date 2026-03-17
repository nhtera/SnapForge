#!/bin/bash
# bump-version.sh - Bumps MARKETING_VERSION in project.yml
# Usage: ./scripts/bump-version.sh [patch|minor|major]

set -euo pipefail

PROJECT_FILE="project.yml"
BUMP_TYPE="${1:-patch}"

# Extract current MARKETING_VERSION
CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION:' "$PROJECT_FILE" | sed 's/.*: *"//' | sed 's/".*//')

if [ -z "$CURRENT_VERSION" ]; then
  echo "::error::Could not find MARKETING_VERSION in $PROJECT_FILE"
  exit 1
fi

# Parse semver
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

# Bump
case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "::error::Invalid bump type: $BUMP_TYPE (use patch, minor, or major)"
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Replace MARKETING_VERSION in project.yml
sed -i '' "s/MARKETING_VERSION: \"${CURRENT_VERSION}\"/MARKETING_VERSION: \"${NEW_VERSION}\"/" "$PROJECT_FILE"

# Bump build number
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' "$PROJECT_FILE" | sed 's/.*: *"//' | sed 's/".*//')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"${CURRENT_BUILD}\"/CURRENT_PROJECT_VERSION: \"${NEW_BUILD}\"/" "$PROJECT_FILE"

echo "version=${NEW_VERSION}"
echo "previous_version=${CURRENT_VERSION}"
echo "build_number=${NEW_BUILD}"
