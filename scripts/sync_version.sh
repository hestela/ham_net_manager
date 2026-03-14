#!/usr/bin/env bash
# Reads the version from pubspec.yaml and writes it into lib/app_version.dart.
# Optionally bumps the version before syncing.
#
# Usage:
#   ./sync_version.sh              # sync only
#   ./sync_version.sh --patch      # bump patch (1.2.3 -> 1.2.4), then sync
#   ./sync_version.sh --minor      # bump minor (1.2.3 -> 1.3.0), then sync
#   ./sync_version.sh --major      # bump major (1.2.3 -> 2.0.0), then sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
PUBSPEC="$ROOT/pubspec.yaml"

BUMP=""
for arg in "$@"; do
  case "$arg" in
    --patch) BUMP="patch" ;;
    --minor) BUMP="minor" ;;
    --major) BUMP="major" ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# Extract current version string (e.g. 1.8.0+1)
FULL_VERSION=$(grep '^version:' "$PUBSPEC" | sed 's/version: //')
# Semver part before the build number (e.g. 1.8.0)
SEMVER=$(echo "$FULL_VERSION" | sed 's/+.*//')
# Build number after '+' (e.g. 1)
BUILD=$(echo "$FULL_VERSION" | grep '+' | sed 's/.*+//')
BUILD=${BUILD:-1}

if [[ -n "$BUMP" ]]; then
  MAJOR=$(echo "$SEMVER" | cut -d. -f1)
  MINOR=$(echo "$SEMVER" | cut -d. -f2)
  PATCH=$(echo "$SEMVER" | cut -d. -f3)

  case "$BUMP" in
    patch) PATCH=$((PATCH + 1)) ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  esac

  NEW_BUILD=$((BUILD + 1))
  NEW_SEMVER="$MAJOR.$MINOR.$PATCH"
  NEW_FULL="$NEW_SEMVER+$NEW_BUILD"

  # Update pubspec.yaml
  sed -i "s/^version: .*/version: $NEW_FULL/" "$PUBSPEC"
  sed -i "s/msix_version: .*/msix_version: $NEW_SEMVER.0/" "$PUBSPEC"
  echo "Version bumped: $FULL_VERSION -> $NEW_FULL"

  SEMVER="$NEW_SEMVER"
fi

cat > "$ROOT/lib/app_version.dart" <<EOF
// App version constant — auto-generated from pubspec.yaml by scripts/sync_version.sh.
// Do not edit by hand; run 'make sync-version' or any build target instead.
const kAppVersion = '$SEMVER';
EOF

echo "app_version.dart updated to $SEMVER"
